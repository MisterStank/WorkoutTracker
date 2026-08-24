package service

import (
	"context"
	"crypto/rand"
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

	// A handful of retries absorbs the rare share-code collision (birthday
	// paradox over a 6-char code among currently-active workouts is low
	// odds, but the unique index means we must handle it, not just hope).
	const maxShareCodeAttempts = 5
	var w *domain.Workout
	for attempt := 0; attempt < maxShareCodeAttempts; attempt++ {
		code, err := generateShareCode()
		if err != nil {
			return nil, err
		}
		w = &domain.Workout{
			ID:         uuid.New(),
			UserID:     userID,
			StartedAt:  time.Now(),
			Status:     domain.WorkoutInProgress,
			TemplateID: templateID,
			ShareCode:  &code,
		}
		err = s.workouts.Create(ctx, w)
		if err == nil {
			return w, nil
		}
		if !errors.Is(err, domain.ErrShareCodeTaken) {
			return nil, err
		}
	}
	return nil, domain.ErrShareCodeTaken
}

// shareCodeCharset omits visually-ambiguous characters (0/O, 1/I) since the
// code is meant to be read off one phone and typed into another.
const shareCodeCharset = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

func generateShareCode() (string, error) {
	raw := make([]byte, 6)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	code := make([]byte, len(raw))
	for i, b := range raw {
		code[i] = shareCodeCharset[int(b)%len(shareCodeCharset)]
	}
	return string(code), nil
}

// GetSharedWorkout looks up an in-progress workout by its share code —
// deliberately no ownership check, since the whole point is letting someone
// else watch. SetsForSharedWorkout mirrors that: read-only, no ownership
// check, callable only once you already have the workout ID from the code.
func (s *WorkoutService) GetSharedWorkout(ctx context.Context, code string) (*domain.Workout, error) {
	if code == "" {
		return nil, domain.ErrWorkoutNotFound
	}
	return s.workouts.FindByShareCode(ctx, code)
}

func (s *WorkoutService) SetsForSharedWorkout(ctx context.Context, workoutID uuid.UUID) ([]*domain.WorkoutSet, error) {
	return s.sets.ListForWorkout(ctx, workoutID)
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
	if _, err := s.exercises.FindByID(ctx, exerciseID); err != nil {
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

	suggested := roundToNearest(last.WeightKg*multiplier, 1.25)
	return &ProgressionSuggestion{
		SuggestedWeightKg: suggested,
		SuggestedReps:     last.Reps,
		Reasoning:         reasoning,
		BasedOnRPE:        last.RPE,
	}, nil
}

func roundToNearest(value, step float64) float64 {
	return math.Round(value/step) * step
}
