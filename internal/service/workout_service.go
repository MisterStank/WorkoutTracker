package service

import (
	"context"
	"errors"
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

func (s *WorkoutService) ListExercises(ctx context.Context, search string) ([]*domain.Exercise, error) {
	return s.exercises.List(ctx, search)
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

func (s *WorkoutService) ListTemplates(ctx context.Context, userID uuid.UUID) ([]*domain.WorkoutTemplate, error) {
	return s.templates.ListForUser(ctx, userID)
}

func (s *WorkoutService) DeleteTemplate(ctx context.Context, userID, templateID uuid.UUID) error {
	t, err := s.templates.FindByID(ctx, templateID)
	if err != nil {
		return err
	}
	if t.UserID != userID {
		return domain.ErrTemplateNotOwned
	}
	return s.templates.Delete(ctx, templateID)
}

func (s *WorkoutService) ActiveWorkout(ctx context.Context, userID uuid.UUID) (*domain.Workout, error) {
	w, err := s.workouts.FindActiveForUser(ctx, userID)
	if errors.Is(err, domain.ErrWorkoutNotFound) {
		return nil, nil
	}
	return w, err
}

func (s *WorkoutService) LogSet(ctx context.Context, userID, workoutID, exerciseID uuid.UUID, reps int, weightKg float64, rpe *float64, isWarmup bool) (*domain.LoggedSet, error) {
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
	if _, err := s.exercises.FindByID(ctx, exerciseID); err != nil {
		return nil, err
	}

	set := &domain.WorkoutSet{
		WorkoutID:  workoutID,
		ExerciseID: exerciseID,
		Reps:       reps,
		WeightKg:   weightKg,
		RPE:        rpe,
		IsWarmup:   isWarmup,
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
