package service_test

import (
	"context"
	"sort"
	"sync"
	"testing"
	"time"

	"workouttracker/internal/domain"
	"workouttracker/internal/service"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// fakeExerciseRepo, fakeWorkoutRepo, fakeWorkoutSetRepo, and
// fakePersonalRecordRepo are in-memory domain.*Repository implementations,
// letting WorkoutService be tested without a real Postgres (same pattern as
// auth_service_test.go). fakeWorkoutSetRepo replicates the PR-upsert rule
// from repository.WorkoutSetRepository.LogSet (heaviest weight, best
// single-set volume) so the service's ownership/state rules can be tested
// end-to-end.

type fakeExerciseRepo struct {
	byID map[uuid.UUID]*domain.Exercise
}

func newFakeExerciseRepo(exercises ...*domain.Exercise) *fakeExerciseRepo {
	f := &fakeExerciseRepo{byID: map[uuid.UUID]*domain.Exercise{}}
	for _, e := range exercises {
		f.byID[e.ID] = e
	}
	return f
}

func (f *fakeExerciseRepo) List(ctx context.Context, search string) ([]*domain.Exercise, error) {
	var out []*domain.Exercise
	for _, e := range f.byID {
		out = append(out, e)
	}
	return out, nil
}

func (f *fakeExerciseRepo) FindByID(ctx context.Context, id uuid.UUID) (*domain.Exercise, error) {
	e, ok := f.byID[id]
	if !ok {
		return nil, domain.ErrExerciseNotFound
	}
	return e, nil
}

type fakeWorkoutRepo struct {
	mu       sync.Mutex
	byID     map[uuid.UUID]*domain.Workout
	activeOf map[uuid.UUID]uuid.UUID
}

func newFakeWorkoutRepo() *fakeWorkoutRepo {
	return &fakeWorkoutRepo{byID: map[uuid.UUID]*domain.Workout{}, activeOf: map[uuid.UUID]uuid.UUID{}}
}

func (f *fakeWorkoutRepo) Create(ctx context.Context, w *domain.Workout) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.byID[w.ID] = w
	f.activeOf[w.UserID] = w.ID
	return nil
}

func (f *fakeWorkoutRepo) FindByID(ctx context.Context, id uuid.UUID) (*domain.Workout, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	w, ok := f.byID[id]
	if !ok {
		return nil, domain.ErrWorkoutNotFound
	}
	return w, nil
}

func (f *fakeWorkoutRepo) FindActiveForUser(ctx context.Context, userID uuid.UUID) (*domain.Workout, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	id, ok := f.activeOf[userID]
	if !ok {
		return nil, domain.ErrWorkoutNotFound
	}
	return f.byID[id], nil
}

func (f *fakeWorkoutRepo) Finish(ctx context.Context, id uuid.UUID, endedAt time.Time, notes string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	w, ok := f.byID[id]
	if !ok {
		return domain.ErrWorkoutNotFound
	}
	w.EndedAt = &endedAt
	w.Notes = notes
	w.Status = domain.WorkoutCompleted
	delete(f.activeOf, w.UserID)
	return nil
}

func (f *fakeWorkoutRepo) ListForUser(ctx context.Context, userID uuid.UUID, limit int, afterStartedAt *time.Time, afterID *uuid.UUID) ([]*domain.Workout, error) {
	f.mu.Lock()
	defer f.mu.Unlock()

	var all []*domain.Workout
	for _, w := range f.byID {
		if w.UserID == userID {
			all = append(all, w)
		}
	}
	sort.Slice(all, func(i, j int) bool {
		if all[i].StartedAt.Equal(all[j].StartedAt) {
			return all[i].ID.String() > all[j].ID.String()
		}
		return all[i].StartedAt.After(all[j].StartedAt)
	})

	if afterStartedAt != nil && afterID != nil {
		idx := 0
		for i, w := range all {
			if w.StartedAt.Before(*afterStartedAt) || (w.StartedAt.Equal(*afterStartedAt) && w.ID.String() < afterID.String()) {
				idx = i
				break
			}
			idx = i + 1
		}
		all = all[idx:]
	}

	if len(all) > limit {
		all = all[:limit]
	}
	return all, nil
}

type fakeWorkoutSetRepo struct {
	mu      sync.Mutex
	sets    map[uuid.UUID][]*domain.WorkoutSet
	records map[string]*domain.PersonalRecord // key: userID|exerciseID|recordType
}

func newFakeWorkoutSetRepo() *fakeWorkoutSetRepo {
	return &fakeWorkoutSetRepo{sets: map[uuid.UUID][]*domain.WorkoutSet{}, records: map[string]*domain.PersonalRecord{}}
}

func (f *fakeWorkoutSetRepo) ListForWorkout(ctx context.Context, workoutID uuid.UUID) ([]*domain.WorkoutSet, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.sets[workoutID], nil
}

func (f *fakeWorkoutSetRepo) LastForExercise(ctx context.Context, userID, exerciseID uuid.UUID) (*domain.WorkoutSet, error) {
	f.mu.Lock()
	defer f.mu.Unlock()

	var latest *domain.WorkoutSet
	for _, sets := range f.sets {
		for _, s := range sets {
			if s.ExerciseID != exerciseID {
				continue
			}
			if latest == nil || s.PerformedAt.After(latest.PerformedAt) {
				latest = s
			}
		}
	}
	if latest == nil {
		return nil, domain.ErrWorkoutSetNotFound
	}
	return latest, nil
}

func (f *fakeWorkoutSetRepo) LogSet(ctx context.Context, userID uuid.UUID, set *domain.WorkoutSet) (*domain.LoggedSet, error) {
	f.mu.Lock()
	defer f.mu.Unlock()

	set.ID = uuid.New()
	set.SetNumber = len(f.sets[set.WorkoutID]) + 1
	set.PerformedAt = time.Now()
	f.sets[set.WorkoutID] = append(f.sets[set.WorkoutID], set)

	if set.IsWarmup {
		return &domain.LoggedSet{Set: set}, nil
	}

	candidates := map[string]float64{
		domain.RecordTypeMaxWeight: set.WeightKg,
		domain.RecordTypeMaxVolume: set.WeightKg * float64(set.Reps),
	}

	var newRecords []*domain.PersonalRecord
	for recordType, value := range candidates {
		key := userID.String() + "|" + set.ExerciseID.String() + "|" + recordType
		if existing, ok := f.records[key]; !ok || value > existing.Value {
			pr := &domain.PersonalRecord{
				ID: uuid.New(), UserID: userID, ExerciseID: set.ExerciseID,
				RecordType: recordType, Value: value, AchievedAt: set.PerformedAt, WorkoutSetID: set.ID,
			}
			f.records[key] = pr
			newRecords = append(newRecords, pr)
		}
	}

	return &domain.LoggedSet{Set: set, NewRecords: newRecords}, nil
}

type fakePersonalRecordRepo struct {
	sets *fakeWorkoutSetRepo
}

func (f *fakePersonalRecordRepo) ListForUser(ctx context.Context, userID uuid.UUID) ([]*domain.PersonalRecord, error) {
	f.sets.mu.Lock()
	defer f.sets.mu.Unlock()
	var out []*domain.PersonalRecord
	for key, pr := range f.sets.records {
		if key[:len(userID.String())] == userID.String() {
			out = append(out, pr)
		}
	}
	return out, nil
}

func newTestWorkoutService(exercises ...*domain.Exercise) (*service.WorkoutService, *fakeWorkoutSetRepo) {
	setRepo := newFakeWorkoutSetRepo()
	svc := service.NewWorkoutService(
		newFakeExerciseRepo(exercises...),
		newFakeWorkoutRepo(),
		setRepo,
		&fakePersonalRecordRepo{sets: setRepo},
		nil,
		nil,
	)
	return svc, setRepo
}

func TestStartWorkoutIsIdempotent(t *testing.T) {
	ctx := context.Background()
	svc, _ := newTestWorkoutService()
	userID := uuid.New()

	w1, err := svc.StartWorkout(ctx, userID)
	require.NoError(t, err)

	w2, err := svc.StartWorkout(ctx, userID)
	require.NoError(t, err)
	assert.Equal(t, w1.ID, w2.ID, "starting a workout twice should return the existing in-progress one")
}

func TestLogSetRejectsUnownedWorkout(t *testing.T) {
	ctx := context.Background()
	exercise := &domain.Exercise{ID: uuid.New(), Name: "Bench Press"}
	svc, _ := newTestWorkoutService(exercise)

	owner := uuid.New()
	attacker := uuid.New()

	w, err := svc.StartWorkout(ctx, owner)
	require.NoError(t, err)

	_, err = svc.LogSet(ctx, attacker, w.ID, exercise.ID, 5, 100, nil, false)
	assert.ErrorIs(t, err, domain.ErrWorkoutNotOwned)
}

func TestLogSetRejectsAfterFinish(t *testing.T) {
	ctx := context.Background()
	exercise := &domain.Exercise{ID: uuid.New(), Name: "Squat"}
	svc, _ := newTestWorkoutService(exercise)
	userID := uuid.New()

	w, err := svc.StartWorkout(ctx, userID)
	require.NoError(t, err)

	_, err = svc.FinishWorkout(ctx, userID, w.ID, "done")
	require.NoError(t, err)

	_, err = svc.LogSet(ctx, userID, w.ID, exercise.ID, 5, 100, nil, false)
	assert.ErrorIs(t, err, domain.ErrWorkoutNotActive)
}

func TestLogSetDetectsNewPersonalRecords(t *testing.T) {
	ctx := context.Background()
	exercise := &domain.Exercise{ID: uuid.New(), Name: "Deadlift"}
	svc, _ := newTestWorkoutService(exercise)
	userID := uuid.New()

	w, err := svc.StartWorkout(ctx, userID)
	require.NoError(t, err)

	first, err := svc.LogSet(ctx, userID, w.ID, exercise.ID, 5, 100, nil, false)
	require.NoError(t, err)
	assert.Len(t, first.NewRecords, 2, "first set at any weight/volume is always a new max_weight and max_volume PR")

	// a heavier set at fewer reps: breaks max_weight, not max_volume (100*5=500 > 110*2=220)
	second, err := svc.LogSet(ctx, userID, w.ID, exercise.ID, 2, 110, nil, false)
	require.NoError(t, err)
	require.Len(t, second.NewRecords, 1)
	assert.Equal(t, domain.RecordTypeMaxWeight, second.NewRecords[0].RecordType)

	// a lighter set that doesn't beat either record
	third, err := svc.LogSet(ctx, userID, w.ID, exercise.ID, 3, 90, nil, false)
	require.NoError(t, err)
	assert.Empty(t, third.NewRecords)
}

func TestWorkoutHistoryPaginates(t *testing.T) {
	ctx := context.Background()
	svc, _ := newTestWorkoutService()
	userID := uuid.New()

	// StartWorkout is idempotent, so simulate 3 separate completed workouts
	// directly through the repo-backed service calls.
	for i := 0; i < 3; i++ {
		w, err := svc.StartWorkout(ctx, userID)
		require.NoError(t, err)
		_, err = svc.FinishWorkout(ctx, userID, w.ID, "")
		require.NoError(t, err)
		time.Sleep(time.Millisecond) // ensure distinct StartedAt ordering
	}

	page1, err := svc.WorkoutHistory(ctx, userID, 2, "")
	require.NoError(t, err)
	assert.Len(t, page1.Workouts, 2)
	assert.True(t, page1.HasMore)

	page2, err := svc.WorkoutHistory(ctx, userID, 2, page1.EndCursor)
	require.NoError(t, err)
	assert.Len(t, page2.Workouts, 1)
	assert.False(t, page2.HasMore)
}

func TestWarmupSetsDoNotCountAsRecords(t *testing.T) {
	ctx := context.Background()
	exercise := &domain.Exercise{ID: uuid.New(), Name: "Overhead Press"}
	svc, _ := newTestWorkoutService(exercise)
	userID := uuid.New()

	w, err := svc.StartWorkout(ctx, userID)
	require.NoError(t, err)

	warmup, err := svc.LogSet(ctx, userID, w.ID, exercise.ID, 10, 20, nil, true)
	require.NoError(t, err)
	assert.Empty(t, warmup.NewRecords, "a warm-up set should never register a PR")
	assert.True(t, warmup.Set.IsWarmup)

	working, err := svc.LogSet(ctx, userID, w.ID, exercise.ID, 5, 60, nil, false)
	require.NoError(t, err)
	assert.Len(t, working.NewRecords, 2, "the first working set should still register both PR types, unaffected by the earlier warm-up")
}

func TestLastSetForExercise(t *testing.T) {
	ctx := context.Background()
	exercise := &domain.Exercise{ID: uuid.New(), Name: "Barbell Row"}
	svc, _ := newTestWorkoutService(exercise)
	userID := uuid.New()

	none, err := svc.LastSetForExercise(ctx, userID, exercise.ID)
	require.NoError(t, err)
	assert.Nil(t, none, "no error and a nil result when the exercise has never been logged")

	w, err := svc.StartWorkout(ctx, userID)
	require.NoError(t, err)
	_, err = svc.LogSet(ctx, userID, w.ID, exercise.ID, 8, 40, nil, false)
	require.NoError(t, err)
	_, err = svc.LogSet(ctx, userID, w.ID, exercise.ID, 6, 45, nil, false)
	require.NoError(t, err)

	last, err := svc.LastSetForExercise(ctx, userID, exercise.ID)
	require.NoError(t, err)
	require.NotNil(t, last)
	assert.Equal(t, 45.0, last.WeightKg, "should return the most recently logged set, not the first")
}
