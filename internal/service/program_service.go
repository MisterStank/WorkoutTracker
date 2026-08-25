package service

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"workouttracker/internal/domain"

	"github.com/google/uuid"
)

// ProgramService generates a multi-day training split from a saved
// UserFitnessProfile — a deterministic rule-based lookup (split pattern by
// days/week, set/rep ranges by goal), not a model call, matching
// WorkoutService.SuggestNextSet and AnalyticsService.DetectPlateau's style
// elsewhere in this codebase. Each day is persisted as an ordinary
// WorkoutTemplate (via WorkoutService.CreateTemplate, so it gets the exact
// same ID/position handling a hand-built template does) and the Program
// itself just names and orders them.
type ProgramService struct {
	profiles  domain.UserFitnessProfileRepository
	programs  domain.ProgramRepository
	exercises domain.ExerciseRepository
	workouts  *WorkoutService
}

func NewProgramService(
	profiles domain.UserFitnessProfileRepository,
	programs domain.ProgramRepository,
	exercises domain.ExerciseRepository,
	workouts *WorkoutService,
) *ProgramService {
	return &ProgramService{profiles: profiles, programs: programs, exercises: exercises, workouts: workouts}
}

func (s *ProgramService) SaveFitnessProfile(ctx context.Context, userID uuid.UUID, profile domain.UserFitnessProfile) (*domain.UserFitnessProfile, error) {
	profile.UserID = userID
	profile.UpdatedAt = time.Now()
	if err := s.profiles.Upsert(ctx, &profile); err != nil {
		return nil, err
	}
	return &profile, nil
}

// MyFitnessProfile returns nil (not an error) if the user has never saved
// one — an expected first-time state, not a failure.
func (s *ProgramService) MyFitnessProfile(ctx context.Context, userID uuid.UUID) (*domain.UserFitnessProfile, error) {
	p, err := s.profiles.Get(ctx, userID)
	if errors.Is(err, domain.ErrFitnessProfileNotFound) {
		return nil, nil
	}
	return p, err
}

func (s *ProgramService) MyPrograms(ctx context.Context, userID uuid.UUID) ([]*domain.Program, error) {
	return s.programs.ListForUser(ctx, userID)
}

// DayInput is one day of a manually-built program: a caller-chosen label
// plus the ID of an already-existing template to use for that day.
type DayInput struct {
	DayLabel   string
	TemplateID uuid.UUID
}

// CreateFromTemplates builds a Program out of the caller's own existing
// templates rather than generating new ones — the "manually assemble a
// program" path alongside GenerateProgram's AI-questionnaire path. Goal
// defaults to GoalGeneralFitness since there's no fitness-profile
// questionnaire to derive a real one from.
func (s *ProgramService) CreateFromTemplates(ctx context.Context, userID uuid.UUID, name string, days []DayInput) (*domain.Program, error) {
	program := &domain.Program{
		ID:          uuid.New(),
		UserID:      userID,
		Name:        name,
		Goal:        domain.GoalGeneralFitness,
		DaysPerWeek: len(days),
		CreatedAt:   time.Now(),
	}

	for i, day := range days {
		tmpl, err := s.workouts.GetTemplate(ctx, userID, day.TemplateID)
		if err != nil {
			return nil, err
		}
		program.Days = append(program.Days, &domain.ProgramDay{
			ID:         uuid.New(),
			DayLabel:   day.DayLabel,
			Position:   i,
			TemplateID: tmpl.ID,
			Template:   tmpl,
		})
	}

	if err := s.programs.Create(ctx, program); err != nil {
		return nil, err
	}
	return program, nil
}

// NextWorkout derives "what should I train next" from the user's most
// recently created program plus their finished-workout history — see
// domain.NextWorkout's doc comment for the wraparound logic. Returns nil,
// nil (not an error) if the user has no programs yet.
func (s *ProgramService) NextWorkout(ctx context.Context, userID uuid.UUID) (*domain.NextWorkout, error) {
	programs, err := s.programs.ListForUser(ctx, userID)
	if err != nil {
		return nil, err
	}
	if len(programs) == 0 {
		return nil, nil
	}
	program := programs[0]
	if len(program.Days) == 0 {
		return nil, nil
	}

	templateIDs := make([]uuid.UUID, len(program.Days))
	for i, d := range program.Days {
		templateIDs[i] = d.TemplateID
	}

	mostRecent, err := s.workouts.MostRecentFinishedByTemplateIDs(ctx, userID, templateIDs)
	if err != nil {
		return nil, err
	}

	nextPosition := 0
	if mostRecent != nil && mostRecent.TemplateID != nil {
		for _, d := range program.Days {
			if d.TemplateID == *mostRecent.TemplateID {
				nextPosition = (d.Position + 1) % len(program.Days)
				break
			}
		}
	}

	var nextDay *domain.ProgramDay
	for _, d := range program.Days {
		if d.Position == nextPosition {
			nextDay = d
			break
		}
	}
	if nextDay == nil {
		nextDay = program.Days[0]
	}

	return &domain.NextWorkout{Program: program, Day: nextDay}, nil
}

// dayPlan is one training day within a split: a label plus a sequence of
// exercise categories to fill it with (the same "push"/"pull"/"legs"/
// "arms"/"core" taxonomy exercises are already tagged with — a category
// listed twice means "two exercises from that category", not one repeated
// exercise).
type dayPlan struct {
	label      string
	categories []string
}

// splitForDaysPerWeek is the generator's core lookup table: 1-3 days/week
// gets full-body sessions (there isn't enough weekly volume to specialize),
// 4 alternates upper/lower, 5-6 moves to a push/pull/legs rotation — the
// same progression most evidence-based programming guides recommend, kept
// here as a fixed table rather than derived, so output is predictable and
// testable.
func splitForDaysPerWeek(days int) []dayPlan {
	fullBody := dayPlan{"Full Body", []string{"push", "pull", "legs", "arms", "core"}}
	upper := dayPlan{"Upper", []string{"push", "push", "pull", "pull", "arms"}}
	lower := dayPlan{"Lower", []string{"legs", "legs", "legs", "core"}}
	push := dayPlan{"Push", []string{"push", "push", "push", "arms"}}
	pull := dayPlan{"Pull", []string{"pull", "pull", "pull", "arms"}}
	legs := dayPlan{"Legs", []string{"legs", "legs", "legs", "legs"}}

	switch {
	case days <= 3:
		out := make([]dayPlan, days)
		for i := range out {
			out[i] = fullBody
		}
		return out
	case days == 4:
		return []dayPlan{upper, lower, upper, lower}
	case days == 5:
		return []dayPlan{push, pull, legs, upper, lower}
	default: // 6+
		return []dayPlan{push, pull, legs, push, pull, legs}
	}
}

// setsRepsFor returns (targetSets, targetReps) for one exercise, varying by
// goal and by whether it's a compound movement (push/pull/legs) or an
// accessory (arms/core) — compounds get more sets at lower reps for
// strength, accessories stay higher-rep regardless of goal.
func setsRepsFor(goal domain.Goal, category string) (int, int) {
	compound := category == "push" || category == "pull" || category == "legs"
	switch goal {
	case domain.GoalStrength:
		if compound {
			return 5, 5
		}
		return 3, 8
	case domain.GoalHypertrophy:
		if compound {
			return 4, 10
		}
		return 3, 12
	default: // fat_loss, general_fitness
		if compound {
			return 3, 12
		}
		return 3, 15
	}
}

// GenerateProgram builds and persists a full split from the caller's saved
// profile. Returns domain.ErrFitnessProfileNotFound if none has been saved
// yet — the client is expected to prompt for one first.
func (s *ProgramService) GenerateProgram(ctx context.Context, userID uuid.UUID) (*domain.Program, error) {
	profile, err := s.profiles.Get(ctx, userID)
	if err != nil {
		return nil, err
	}

	days := profile.DaysPerWeek
	if days < 1 {
		days = 1
	}
	if days > 6 {
		days = 6
	}
	plan := splitForDaysPerWeek(days)

	program := &domain.Program{
		ID:          uuid.New(),
		UserID:      userID,
		Name:        fmt.Sprintf("%d-Day %s Program", days, splitName(plan)),
		Goal:        profile.Goal,
		DaysPerWeek: days,
		CreatedAt:   time.Now(),
	}

	var skipped []string
	for i, day := range plan {
		usedExerciseIDs := map[uuid.UUID]bool{}
		var templateExercises []*domain.TemplateExercise
		for _, category := range day.categories {
			exercise, err := s.pickExercise(ctx, category, profile.EquipmentAccess, profile.AvoidMuscleGroups, usedExerciseIDs)
			if err != nil {
				return nil, err
			}
			if exercise == nil {
				skipped = append(skipped, fmt.Sprintf("%s: no eligible %s exercise for your equipment/exclusions", day.label, category))
				continue
			}
			usedExerciseIDs[exercise.ID] = true
			sets, reps := setsRepsFor(profile.Goal, category)
			templateExercises = append(templateExercises, &domain.TemplateExercise{
				ExerciseID: exercise.ID,
				TargetSets: sets,
				TargetReps: &reps,
			})
		}

		dayLabel := day.label
		if len(plan) > 1 {
			countOfLabel := 0
			for _, d := range plan[:i+1] {
				if d.label == day.label {
					countOfLabel++
				}
			}
			totalOfLabel := 0
			for _, d := range plan {
				if d.label == day.label {
					totalOfLabel++
				}
			}
			if totalOfLabel > 1 {
				dayLabel = fmt.Sprintf("%s %d", day.label, countOfLabel)
			}
		}

		tmpl, err := s.workouts.CreateTemplate(ctx, userID, dayLabel, templateExercises)
		if err != nil {
			return nil, err
		}
		program.Days = append(program.Days, &domain.ProgramDay{
			ID:         uuid.New(),
			DayLabel:   dayLabel,
			Position:   i,
			TemplateID: tmpl.ID,
			Template:   tmpl,
		})
	}
	program.Notes = strings.Join(skipped, "; ")

	if err := s.programs.Create(ctx, program); err != nil {
		return nil, err
	}
	return program, nil
}

// pickExercise returns the first (by name) eligible exercise in category
// not already used elsewhere in the same day, or nil if none qualify.
func (s *ProgramService) pickExercise(ctx context.Context, category string, equipment, avoidMuscleGroups []string, used map[uuid.UUID]bool) (*domain.Exercise, error) {
	candidates, err := s.exercises.ListFiltered(ctx, equipment, avoidMuscleGroups, category)
	if err != nil {
		return nil, err
	}
	for _, c := range candidates {
		if !used[c.ID] {
			return c, nil
		}
	}
	return nil, nil
}

func splitName(plan []dayPlan) string {
	seen := map[string]bool{}
	var labels []string
	for _, d := range plan {
		if !seen[d.label] {
			seen[d.label] = true
			labels = append(labels, d.label)
		}
	}
	return strings.Join(labels, "/")
}
