package service

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"gymon/internal/domain"

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
	if err := s.programs.SetActive(ctx, userID, program.ID); err != nil {
		return nil, err
	}
	program.IsActive = true
	return program, nil
}

// SetActiveProgram marks program as the one the user is currently
// following — the explicit "use this program" action on the Programs tab.
// Returns domain.ErrProgramNotOwned if programID belongs to another user.
func (s *ProgramService) SetActiveProgram(ctx context.Context, userID, programID uuid.UUID) (*domain.Program, error) {
	program, err := s.programs.FindByID(ctx, programID)
	if err != nil {
		return nil, err
	}
	if program.UserID != userID {
		return nil, domain.ErrProgramNotOwned
	}
	if err := s.programs.SetActive(ctx, userID, programID); err != nil {
		return nil, err
	}
	program.IsActive = true
	return program, nil
}

// NextWorkout derives "what should I train next" from the user's active
// program (see SetActiveProgram) plus their finished-workout history — see
// domain.NextWorkout's doc comment for the wraparound logic. Returns nil,
// nil (not an error) if the user has no active program.
func (s *ProgramService) NextWorkout(ctx context.Context, userID uuid.UUID) (*domain.NextWorkout, error) {
	program, err := s.programs.FindActiveForUser(ctx, userID)
	if err != nil {
		return nil, err
	}
	if program == nil || len(program.Days) == 0 {
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

// ProgramDayTargets computes each exercise's prescription for a program
// day *this week*: the template's sets/reps plus a suggested load derived
// from the user's last working set and the program's progression rule.
// Week 1 is the week the program was created; every 4th week is a lighter
// deload.
func (s *ProgramService) ProgramDayTargets(ctx context.Context, userID, programDayID uuid.UUID) ([]*domain.ExerciseTarget, error) {
	programs, err := s.programs.ListForUser(ctx, userID)
	if err != nil {
		return nil, err
	}
	var program *domain.Program
	var day *domain.ProgramDay
	for _, p := range programs {
		for _, d := range p.Days {
			if d.ID == programDayID {
				program, day = p, d
			}
		}
	}
	if day == nil || day.Template == nil {
		return nil, domain.ErrProgramNotFound
	}

	weeksElapsed := int(time.Since(program.CreatedAt).Hours() / (24 * 7))
	weekNumber := weeksElapsed + 1
	isDeload := weekNumber%4 == 0
	rule := domain.ProgressionRuleForGoal(program.Goal)

	targets := make([]*domain.ExerciseTarget, 0, len(day.Template.Exercises))
	for _, te := range day.Template.Exercises {
		last, err := s.workouts.LastSetForExercise(ctx, userID, te.ExerciseID)
		if err != nil {
			return nil, err
		}
		base := 0.0
		if last != nil {
			base = last.WeightKg
		}

		exercise, err := s.exercises.FindByID(ctx, te.ExerciseID)
		if err != nil {
			return nil, err
		}
		compound := isCompoundPattern(movementPattern(exercise))

		suggested, reasoning := progressionTarget(rule, base, weekNumber, isDeload, compound)
		targets = append(targets, &domain.ExerciseTarget{
			ExerciseID:        te.ExerciseID,
			TargetSets:        te.TargetSets,
			TargetReps:        te.TargetReps,
			SuggestedWeightKg: suggested,
			WeekNumber:        weekNumber,
			Reasoning:         reasoning,
		})
	}
	return targets, nil
}

func progressionTarget(rule domain.ProgressionRule, base float64, week int, deload, compound bool) (float64, string) {
	if base <= 0 {
		return 0, "First time — pick a weight you can control for all sets."
	}
	if deload {
		return roundToNearest(base*0.9, loadableStepKg), fmt.Sprintf("Week %d is a deload — ~10%% lighter to recover.", week)
	}
	switch rule {
	case domain.ProgressionLinear:
		step := 1.25
		if compound {
			step = 2.5
		}
		add := step * float64(week-1)
		if add == 0 {
			return base, fmt.Sprintf("Week 1 — start at your last working weight (%gkg).", base)
		}
		return roundToNearest(base+add, loadableStepKg), fmt.Sprintf("Linear progression — up ~%.2gkg/week from your last %gkg.", step, base)
	case domain.ProgressionDouble:
		return base, "Double progression — hold this weight and add reps until you hit the top of the range, then go up."
	default:
		return base, fmt.Sprintf("Repeat your last working weight (%gkg).", base)
	}
}

// dayPlan is one training day within a split: a label plus an ordered list
// of movement patterns to fill it with, compound patterns first. A pattern
// listed twice means "two exercises for that pattern"; the generator picks
// a different exercise each time.
type dayPlan struct {
	label    string
	patterns []string
}

// splitForDaysPerWeek is the generator's core lookup table. Every lower /
// full-body day contains both a squat and a hinge so hamstrings and glutes
// aren't skipped; push days pair a horizontal and a vertical press, pull
// days a horizontal and a vertical pull. 1-3 days is full-body, 4 is
// upper/lower, 5-7 is a push/pull/legs rotation with extra upper/lower or
// arm days as the count grows.
func splitForDaysPerWeek(days int) []dayPlan {
	fullBody := dayPlan{"Full Body", []string{
		patternSquat, patternHinge, patternHorizontalPush, patternHorizontalPull, patternVerticalPush, patternCore,
	}}
	upper := dayPlan{"Upper", []string{
		patternHorizontalPush, patternHorizontalPull, patternVerticalPush, patternVerticalPull, patternTriceps, patternBiceps,
	}}
	lower := dayPlan{"Lower", []string{
		patternSquat, patternHinge, patternSquat, patternHinge, patternCore,
	}}
	push := dayPlan{"Push", []string{
		patternHorizontalPush, patternVerticalPush, patternHorizontalPush, patternTriceps,
	}}
	pull := dayPlan{"Pull", []string{
		patternVerticalPull, patternHorizontalPull, patternHorizontalPull, patternBiceps,
	}}
	legs := dayPlan{"Legs", []string{
		patternSquat, patternHinge, patternSquat, patternHinge, patternCore,
	}}
	arms := dayPlan{"Arms & Core", []string{
		patternBiceps, patternTriceps, patternBiceps, patternTriceps, patternCore,
	}}

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
	case days == 6:
		return []dayPlan{push, pull, legs, push, pull, legs}
	default: // 7
		return []dayPlan{push, pull, legs, upper, lower, arms, legs}
	}
}

// setsRepsFor returns (targetSets, targetReps) for one exercise, varying by
// goal and by whether its pattern is a compound or an accessory — compounds
// get more sets at lower reps for strength, accessories stay higher-rep
// regardless of goal.
func setsRepsFor(goal domain.Goal, pattern string) (int, int) {
	compound := isCompoundPattern(pattern)
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
	if days > 7 {
		days = 7
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
		for _, pattern := range day.patterns {
			exercise, err := s.pickExercise(ctx, userID, pattern, profile.EquipmentAccess, profile.AvoidMuscleGroups, usedExerciseIDs)
			if err != nil {
				return nil, err
			}
			if exercise == nil {
				skipped = append(skipped, fmt.Sprintf("%s: no eligible %s exercise for your equipment/exclusions", day.label, strings.ReplaceAll(pattern, "_", " ")))
				continue
			}
			usedExerciseIDs[exercise.ID] = true
			sets, reps := setsRepsFor(profile.Goal, pattern)
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

		if len(templateExercises) == 0 {
			skipped = append(skipped, fmt.Sprintf("%s: no eligible exercises, day omitted", dayLabel))
			continue
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
	if err := s.programs.SetActive(ctx, userID, program.ID); err != nil {
		return nil, err
	}
	program.IsActive = true
	return program, nil
}

// patternCategory maps a movement pattern back to the exercise category it
// lives in, so ListFiltered can narrow the candidate set at the DB.
var patternCategory = map[string]string{
	patternSquat:          "legs",
	patternHinge:          "legs",
	patternHorizontalPush: "push",
	patternVerticalPush:   "push",
	patternHorizontalPull: "pull",
	patternVerticalPull:   "pull",
	patternBiceps:         "arms",
	patternTriceps:        "arms",
	patternCore:           "core",
}

// pickExercise returns the first (by name) eligible exercise matching the
// movement pattern and not already used elsewhere in the same day. Falls
// back to any exercise in the pattern's category if nothing matches the
// pattern exactly (e.g. a restrictive equipment list), or nil if none.
func (s *ProgramService) pickExercise(ctx context.Context, userID uuid.UUID, pattern string, equipment, avoidMuscleGroups []string, used map[uuid.UUID]bool) (*domain.Exercise, error) {
	category := patternCategory[pattern]
	// The hinge pattern also lives in the "pull" category (deadlifts), so
	// widen the DB filter for it and match on pattern afterward.
	dbCategory := category
	if pattern == patternHinge {
		dbCategory = ""
	}
	candidates, err := s.exercises.ListFiltered(ctx, userID, equipment, avoidMuscleGroups, dbCategory)
	if err != nil {
		return nil, err
	}

	var categoryFallback *domain.Exercise
	for _, c := range candidates {
		if used[c.ID] {
			continue
		}
		if movementPattern(c) == pattern {
			return c, nil
		}
		if categoryFallback == nil && c.Category == category {
			categoryFallback = c
		}
	}
	return categoryFallback, nil
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
