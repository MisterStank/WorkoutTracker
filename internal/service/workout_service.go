package service

import (
	"context"
	"errors"
	"fmt"
	"math"
	"time"

	"workouttracker/internal/domain"

	"github.com/google/uuid"
)

// WorkoutService depends only on domain interfaces, same as AuthService, so
// business rules (ownership checks, active-workout invariants) stay testable
// without a real Postgres.
type WorkoutService struct {
	exercises domain.ExerciseRepository
	workouts  domain.WorkoutRepository
	sets      domain.WorkoutSetRepository
	records   domain.PersonalRecordRepository
	templates domain.WorkoutTemplateRepository

	// analytics and events are optional (nil is fine, e.g. in unit tests):
	// analytics's cache is invalidated and an event published after a set
	// is logged, but neither failing should fail the mutation itself.
	analytics *AnalyticsService
	events    domain.WorkoutEventPublisher
}

func NewWorkoutService(
	exercises domain.ExerciseRepository,
	workouts domain.WorkoutRepository,
	sets domain.WorkoutSetRepository,
	records domain.PersonalRecordRepository,
	templates domain.WorkoutTemplateRepository,
	analytics *AnalyticsService,
	events domain.WorkoutEventPublisher,
) *WorkoutService {
	return &WorkoutService{
		exercises: exercises, workouts: workouts, sets: sets, records: records, templates: templates,
		analytics: analytics, events: events,
	}
}

const defaultHistoryPageSize = 20

type WorkoutHistoryPage struct {
	Workouts  []*domain.Workout
	HasMore   bool
	EndCursor string
}

func (s *WorkoutService) ListExercises(ctx context.Context, userID uuid.UUID, search string) ([]*domain.Exercise, error) {
	return s.exercises.List(ctx, userID, search)
}

// CreateExercise adds a user-owned custom exercise. name/category/equipment
// are validated the same way the program generator expects them.
func (s *WorkoutService) CreateExercise(ctx context.Context, userID uuid.UUID, name, category string, muscleGroups []string, equipment string) (*domain.Exercise, error) {
	name, err := ValidateExerciseInput(name, category, equipment)
	if err != nil {
		return nil, err
	}
	e := &domain.Exercise{
		ID:           uuid.New(),
		Name:         name,
		Category:     category,
		MuscleGroups: normalizeStrings(muscleGroups),
		Equipment:    equipment,
		IsCustom:     true,
		CreatedBy:    &userID,
		CreatedAt:    time.Now(),
	}
	if err := s.exercises.Create(ctx, e); err != nil {
		return nil, err
	}
	return e, nil
}

func (s *WorkoutService) UpdateExercise(ctx context.Context, userID, exerciseID uuid.UUID, name, category string, muscleGroups []string, equipment string) (*domain.Exercise, error) {
	existing, err := s.ownedExercise(ctx, userID, exerciseID)
	if err != nil {
		return nil, err
	}
	name, err = ValidateExerciseInput(name, category, equipment)
	if err != nil {
		return nil, err
	}
	existing.Name = name
	existing.Category = category
	existing.MuscleGroups = normalizeStrings(muscleGroups)
	existing.Equipment = equipment
	if err := s.exercises.Update(ctx, existing); err != nil {
		return nil, err
	}
	return existing, nil
}

func (s *WorkoutService) DeleteExercise(ctx context.Context, userID, exerciseID uuid.UUID) error {
	if _, err := s.ownedExercise(ctx, userID, exerciseID); err != nil {
		return err
	}
	refs, err := s.exercises.CountReferences(ctx, exerciseID)
	if err != nil {
		return err
	}
	if refs > 0 {
		return domain.ErrExerciseInUse
	}
	return s.exercises.Delete(ctx, exerciseID)
}

// ownedExercise loads a custom exercise and confirms the caller owns it —
// built-ins (CreatedBy == nil) and other users' exercises both return
// ErrExerciseNotOwned.
func (s *WorkoutService) ownedExercise(ctx context.Context, userID, exerciseID uuid.UUID) (*domain.Exercise, error) {
	e, err := s.exercises.FindByID(ctx, exerciseID)
	if err != nil {
		return nil, err
	}
	if e.CreatedBy == nil || *e.CreatedBy != userID {
		return nil, domain.ErrExerciseNotOwned
	}
	return e, nil
}

// StartWorkout is idempotent: if the user already has a workout in
// progress, it's returned rather than erroring, so a flaky client retry
// doesn't need special-case handling. templateID is optional — when set,
// the workout is linked to that template so the client can show the
// planned exercise list instead of starting from a blank slate.
func (s *WorkoutService) StartWorkout(ctx context.Context, userID uuid.UUID, templateID *uuid.UUID) (*domain.Workout, error) {
	if active, err := s.workouts.FindActiveForUser(ctx, userID); err == nil {
		return active, nil
	} else if !errors.Is(err, domain.ErrWorkoutNotFound) {
		return nil, err
	}

	if templateID != nil {
		tmpl, err := s.templates.FindByID(ctx, *templateID)
		if err != nil {
			return nil, err
		}
		if tmpl.UserID != userID {
			return nil, domain.ErrTemplateNotOwned
		}
	}

	w := &domain.Workout{
		ID:         uuid.New(),
		UserID:     userID,
		StartedAt:  time.Now(),
		Status:     domain.WorkoutInProgress,
		TemplateID: templateID,
	}
	if err := s.workouts.Create(ctx, w); err != nil {
		return nil, err
	}
	return w, nil
}

func (s *WorkoutService) CreateTemplate(ctx context.Context, userID uuid.UUID, name string, exercises []*domain.TemplateExercise) (*domain.WorkoutTemplate, error) {
	name, err := ValidateTemplateName(name)
	if err != nil {
		return nil, err
	}
	if len(exercises) == 0 {
		return nil, domain.ErrTemplateNoExercises
	}
	for i, ex := range exercises {
		ex.ID = uuid.New()
		ex.Position = i
	}
	t := &domain.WorkoutTemplate{
		ID:        uuid.New(),
		UserID:    userID,
		Name:      name,
		CreatedAt: time.Now(),
		Exercises: exercises,
	}
	if err := s.templates.Create(ctx, t); err != nil {
		return nil, err
	}
	return t, nil
}

// UpdateTemplate replaces a template's name and full exercise list. Same
// validation and ownership rules as CreateTemplate.
func (s *WorkoutService) UpdateTemplate(ctx context.Context, userID, templateID uuid.UUID, name string, exercises []*domain.TemplateExercise) (*domain.WorkoutTemplate, error) {
	existing, err := s.GetTemplate(ctx, userID, templateID)
	if err != nil {
		return nil, err
	}
	name, err = ValidateTemplateName(name)
	if err != nil {
		return nil, err
	}
	if len(exercises) == 0 {
		return nil, domain.ErrTemplateNoExercises
	}
	for i, ex := range exercises {
		ex.ID = uuid.New()
		ex.Position = i
	}
	updated := &domain.WorkoutTemplate{
		ID:        existing.ID,
		UserID:    userID,
		Name:      name,
		CreatedAt: existing.CreatedAt,
		Exercises: exercises,
	}
	if err := s.templates.Update(ctx, updated); err != nil {
		return nil, err
	}
	return updated, nil
}

func (s *WorkoutService) ListTemplates(ctx context.Context, userID uuid.UUID) ([]*domain.WorkoutTemplate, error) {
	return s.templates.ListForUser(ctx, userID)
}

func (s *WorkoutService) DeleteTemplate(ctx context.Context, userID, templateID uuid.UUID) error {
	t, err := s.GetTemplate(ctx, userID, templateID)
	if err != nil {
		return err
	}
	return s.templates.Delete(ctx, t.ID)
}

// GetTemplate returns domain.ErrTemplateNotOwned if templateID exists but
// belongs to a different user, so callers (here and ProgramService's manual
// program builder) can't be pointed at someone else's template.
func (s *WorkoutService) GetTemplate(ctx context.Context, userID, templateID uuid.UUID) (*domain.WorkoutTemplate, error) {
	t, err := s.templates.FindByID(ctx, templateID)
	if err != nil {
		return nil, err
	}
	if t.UserID != userID {
		return nil, domain.ErrTemplateNotOwned
	}
	return t, nil
}

// MostRecentFinishedByTemplateIDs is a thin passthrough to the repository,
// exposed here (rather than adding a direct WorkoutRepository dependency to
// ProgramService) so ProgramService keeps depending only on *WorkoutService
// for anything workout-related, matching how it already reuses CreateTemplate.
func (s *WorkoutService) MostRecentFinishedByTemplateIDs(ctx context.Context, userID uuid.UUID, templateIDs []uuid.UUID) (*domain.Workout, error) {
	return s.workouts.FindMostRecentFinishedByTemplateIDs(ctx, userID, templateIDs)
}

func (s *WorkoutService) ActiveWorkout(ctx context.Context, userID uuid.UUID) (*domain.Workout, error) {
	w, err := s.workouts.FindActiveForUser(ctx, userID)
	if errors.Is(err, domain.ErrWorkoutNotFound) {
		return nil, nil
	}
	return w, err
}

func (s *WorkoutService) LogSet(ctx context.Context, userID, workoutID, exerciseID uuid.UUID, reps int, weightKg float64, rpe *float64, setType domain.SetType, supersetID *uuid.UUID) (*domain.LoggedSet, error) {
	workout, err := s.workouts.FindByID(ctx, workoutID)
	if err != nil {
		return nil, err
	}
	if workout.UserID != userID {
		return nil, domain.ErrWorkoutNotOwned
	}
	if workout.Status != domain.WorkoutInProgress {
		return nil, domain.ErrWorkoutNotActive
	}
	exercise, err := s.exercises.FindByID(ctx, exerciseID)
	if err != nil {
		return nil, err
	}
	if err := ValidateSetInput(reps, weightKg, rpe, isBodyweight(exercise)); err != nil {
		return nil, err
	}
	if setType == "" {
		setType = domain.SetTypeNormal
	}

	set := &domain.WorkoutSet{
		WorkoutID:  workoutID,
		ExerciseID: exerciseID,
		Reps:       reps,
		WeightKg:   weightKg,
		RPE:        rpe,
		SetType:    setType,
		SupersetID: supersetID,
	}
	logged, err := s.sets.LogSet(ctx, userID, set)
	if err != nil {
		return nil, err
	}

	if s.analytics != nil {
		s.analytics.InvalidateForSet(ctx, userID, exerciseID)
	}
	if s.events != nil {
		_ = s.events.PublishSetLogged(ctx, workoutID, logged)
	}

	return logged, nil
}

// UpdateSet corrects a mis-logged set's reps/weight/RPE/type after the
// fact. Recomputes that day's rollup and the exercise's personal records
// from scratch afterward — a plain in-place edit can silently make a value
// wrong in either direction (raise it above the current PR, or lower it
// below one it used to hold).
func (s *WorkoutService) UpdateSet(ctx context.Context, userID, setID uuid.UUID, reps int, weightKg float64, rpe *float64, setType domain.SetType) (*domain.WorkoutSet, error) {
	set, err := s.sets.FindByID(ctx, setID)
	if err != nil {
		return nil, err
	}
	if err := s.checkSetOwnership(ctx, userID, set); err != nil {
		return nil, err
	}

	exercise, err := s.exercises.FindByID(ctx, set.ExerciseID)
	if err != nil {
		return nil, err
	}
	if err := ValidateSetInput(reps, weightKg, rpe, isBodyweight(exercise)); err != nil {
		return nil, err
	}

	set.Reps = reps
	set.WeightKg = weightKg
	set.RPE = rpe
	if setType == "" {
		setType = domain.SetTypeNormal
	}
	set.SetType = setType

	if err := s.sets.Update(ctx, set); err != nil {
		return nil, err
	}
	s.recomputeAfterSetChange(ctx, userID, set)
	return set, nil
}

// DeleteSet removes one logged set and recomputes that day's rollup and
// the exercise's personal records afterward, in case the deleted set was
// the one holding either.
func (s *WorkoutService) DeleteSet(ctx context.Context, userID, setID uuid.UUID) error {
	set, err := s.sets.FindByID(ctx, setID)
	if err != nil {
		return err
	}
	if err := s.checkSetOwnership(ctx, userID, set); err != nil {
		return err
	}
	if err := s.sets.Delete(ctx, setID); err != nil {
		return err
	}
	s.recomputeAfterSetChange(ctx, userID, set)
	return nil
}

// DeleteWorkout removes an entire workout and recomputes the rollup/records
// for every exercise+day it touched, since any of its sets could have been
// holding a personal record. Sets are deleted explicitly rather than left
// to the database's ON DELETE CASCADE, so this stays correct regardless of
// what's enforcing referential integrity underneath the repository.
func (s *WorkoutService) DeleteWorkout(ctx context.Context, userID, workoutID uuid.UUID) error {
	workout, err := s.workouts.FindByID(ctx, workoutID)
	if err != nil {
		return err
	}
	if workout.UserID != userID {
		return domain.ErrWorkoutNotOwned
	}

	sets, err := s.sets.ListForWorkout(ctx, workoutID)
	if err != nil {
		return err
	}

	if err := s.workouts.Delete(ctx, workoutID); err != nil {
		return err
	}

	for _, set := range sets {
		_ = s.sets.Delete(ctx, set.ID)
		s.recomputeAfterSetChange(ctx, userID, set)
	}
	return nil
}

func (s *WorkoutService) checkSetOwnership(ctx context.Context, userID uuid.UUID, set *domain.WorkoutSet) error {
	workout, err := s.workouts.FindByID(ctx, set.WorkoutID)
	if err != nil {
		return err
	}
	if workout.UserID != userID {
		return domain.ErrWorkoutNotOwned
	}
	return nil
}

// recomputeAfterSetChange is best-effort, matching LogSet's treatment of
// analytics: a recompute failure shouldn't fail the edit/delete the user
// actually asked for.
func (s *WorkoutService) recomputeAfterSetChange(ctx context.Context, userID uuid.UUID, set *domain.WorkoutSet) {
	if s.analytics != nil {
		_ = s.analytics.RecomputeAfterSetChange(ctx, userID, set.ExerciseID, set.PerformedAt)
	}
	_ = s.records.Recompute(ctx, userID, set.ExerciseID)
}

func (s *WorkoutService) FinishWorkout(ctx context.Context, userID, workoutID uuid.UUID, notes string) (*domain.Workout, error) {
	workout, err := s.workouts.FindByID(ctx, workoutID)
	if err != nil {
		return nil, err
	}
	if workout.UserID != userID {
		return nil, domain.ErrWorkoutNotOwned
	}
	if workout.Status != domain.WorkoutInProgress {
		return nil, domain.ErrWorkoutNotActive
	}
	if err := ValidateNotes(notes); err != nil {
		return nil, err
	}
	if err := s.workouts.Finish(ctx, workoutID, time.Now(), notes); err != nil {
		return nil, err
	}
	return s.workouts.FindByID(ctx, workoutID)
}

// LastSetForExercise powers "pre-fill the log-set form with what you did
// last time" — returns nil (not an error) if the exercise has never been
// logged, since that's an expected first-time state, not a failure.
func (s *WorkoutService) LastSetForExercise(ctx context.Context, userID, exerciseID uuid.UUID) (*domain.WorkoutSet, error) {
	set, err := s.sets.LastForExercise(ctx, userID, exerciseID)
	if errors.Is(err, domain.ErrWorkoutSetNotFound) {
		return nil, nil
	}
	return set, err
}

func (s *WorkoutService) SetsForWorkout(ctx context.Context, userID, workoutID uuid.UUID) ([]*domain.WorkoutSet, error) {
	workout, err := s.workouts.FindByID(ctx, workoutID)
	if err != nil {
		return nil, err
	}
	if workout.UserID != userID {
		return nil, domain.ErrWorkoutNotOwned
	}
	return s.sets.ListForWorkout(ctx, workoutID)
}

func (s *WorkoutService) WorkoutHistory(ctx context.Context, userID uuid.UUID, first int, after string) (*WorkoutHistoryPage, error) {
	if first <= 0 || first > 100 {
		first = defaultHistoryPageSize
	}

	var afterStartedAt *time.Time
	var afterID *uuid.UUID
	if after != "" {
		startedAt, id, err := decodeCursor(after)
		if err != nil {
			return nil, err
		}
		afterStartedAt, afterID = &startedAt, &id
	}

	// Fetch one extra row to know whether another page exists without a
	// separate COUNT query.
	workouts, err := s.workouts.ListForUser(ctx, userID, first+1, afterStartedAt, afterID)
	if err != nil {
		return nil, err
	}

	hasMore := len(workouts) > first
	if hasMore {
		workouts = workouts[:first]
	}

	page := &WorkoutHistoryPage{Workouts: workouts, HasMore: hasMore}
	if len(workouts) > 0 {
		last := workouts[len(workouts)-1]
		page.EndCursor = encodeCursor(last.StartedAt, last.ID)
	}
	return page, nil
}

func (s *WorkoutService) PersonalRecords(ctx context.Context, userID uuid.UUID) ([]*domain.PersonalRecord, error) {
	return s.records.ListForUser(ctx, userID)
}

// ProgressionSuggestion is a simple RPE-based autoregulation recommendation
// for the next time this exercise is trained: how hard the last set felt
// (not just what it weighed) drives whether to push, hold, or back off.
type ProgressionSuggestion struct {
	SuggestedWeightKg float64
	SuggestedReps     int
	Reasoning         string
	BasedOnRPE        *float64
}

// SuggestNextSet implements straightforward RPE-based autoregulation: an
// easy last set (RPE <= 7) suggests a small increase, a solid one (RPE
// 7.5-8.5) suggests repeating the weight for another rep or two, and a
// near-failure one (RPE > 8.5) suggests backing off slightly rather than
// grinding through another session at the same intensity. Returns nil (not
// an error) when there's no prior set to base a suggestion on.
func (s *WorkoutService) SuggestNextSet(ctx context.Context, userID, exerciseID uuid.UUID) (*ProgressionSuggestion, error) {
	last, err := s.sets.LastForExercise(ctx, userID, exerciseID)
	if errors.Is(err, domain.ErrWorkoutSetNotFound) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	if last.RPE == nil {
		return &ProgressionSuggestion{
			SuggestedWeightKg: last.WeightKg,
			SuggestedReps:     last.Reps,
			Reasoning:         "No RPE logged last time — repeat the same weight, or log RPE next time for a tailored suggestion.",
		}, nil
	}

	rpe := *last.RPE
	var multiplier float64
	var reasoning string
	switch {
	case rpe <= 7.0:
		multiplier = 1.025
		reasoning = fmt.Sprintf("Last set felt easy (RPE %.1f) — try a bit heavier.", rpe)
	case rpe <= 8.5:
		multiplier = 1.0
		reasoning = fmt.Sprintf("Solid effort last time (RPE %.1f) — repeat this weight, aim for an extra rep.", rpe)
	default:
		multiplier = 0.95
		reasoning = fmt.Sprintf("Last set was near failure (RPE %.1f) — consider backing off slightly.", rpe)
	}

	var suggested float64
	switch {
	case multiplier == 1.0:
		// "Repeat" — hand back exactly what they lifted, no rounding.
		suggested = last.WeightKg
	case multiplier > 1.0:
		// Going up: round the target, but never below the next loadable step
		// above the last weight (coarse rounding must not turn "go heavier"
		// into "stay the same").
		suggested = roundToNearest(last.WeightKg*multiplier, loadableStepKg)
		if floor := math.Floor(last.WeightKg/loadableStepKg) * loadableStepKg; suggested <= floor {
			suggested = floor + loadableStepKg
		}
	default:
		// Backing off: round down so it's genuinely lighter, but keep at
		// least one step on the bar.
		suggested = math.Floor(last.WeightKg*multiplier/loadableStepKg) * loadableStepKg
		if suggested < loadableStepKg {
			suggested = loadableStepKg
		}
	}
	return &ProgressionSuggestion{
		SuggestedWeightKg: suggested,
		SuggestedReps:     last.Reps,
		Reasoning:         reasoning,
		BasedOnRPE:        last.RPE,
	}, nil
}

// loadableStepKg is the smallest weight change a lifter can actually make on
// a standard barbell — 1.25 kg plates per side, so 2.5 kg total. Progression
// suggestions round to this so the pre-filled weight is a number you can
// load without micro-plates (and one the app can display cleanly), instead
// of e.g. 66.25 kg.
const loadableStepKg = 2.5

func roundToNearest(value, step float64) float64 {
	return math.Round(value/step) * step
}
