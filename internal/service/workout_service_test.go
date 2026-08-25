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

// ListFiltered mirrors repository.ExerciseRepository.ListFiltered's
// semantics: equipment empty matches any, excludeMuscleGroups skips any
// exercise touching one of them, category empty matches any. Sorted by
// name so callers relying on deterministic "first match" selection (the
// program generator) behave the same as against the real DB.
func (f *fakeExerciseRepo) ListFiltered(ctx context.Context, equipment []string, excludeMuscleGroups []string, category string) ([]*domain.Exercise, error) {
	var out []*domain.Exercise
	for _, e := range f.byID {
		if category != "" && e.Category != category {
			continue
		}
		if len(equipment) > 0 && !contains(equipment, e.Equipment) {
			continue
		}
		if overlaps(e.MuscleGroups, excludeMuscleGroups) {
			continue
		}
		out = append(out, e)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out, nil
}

func contains(list []string, s string) bool {
	for _, item := range list {
		if item == s {
			return true
		}
	}
	return false
}

func overlaps(a, b []string) bool {
	for _, x := range a {
		if contains(b, x) {
			return true
		}
	}
	return false
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

func (f *fakeWorkoutRepo) Delete(ctx context.Context, id uuid.UUID) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	w, ok := f.byID[id]
	if !ok {
		return nil
	}
	delete(f.byID, id)
	if f.activeOf[w.UserID] == id {
		delete(f.activeOf, w.UserID)
	}
	return nil
}

func (f *fakeWorkoutRepo) FindMostRecentFinishedByTemplateIDs(ctx context.Context, userID uuid.UUID, templateIDs []uuid.UUID) (*domain.Workout, error) {
	f.mu.Lock()
	defer f.mu.Unlock()

	inSet := func(id uuid.UUID) bool {
		for _, t := range templateIDs {
			if t == id {
				return true
			}
		}
		return false
	}

	var best *domain.Workout
	for _, w := range f.byID {
		if w.UserID != userID || w.Status != domain.WorkoutCompleted || w.TemplateID == nil || !inSet(*w.TemplateID) {
			continue
		}
		if best == nil || (w.EndedAt != nil && best.EndedAt != nil && w.EndedAt.After(*best.EndedAt)) {
			best = w
		}
	}
	return best, nil
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
	mu          sync.Mutex
	sets        map[uuid.UUID][]*domain.WorkoutSet
	records     map[string]*domain.PersonalRecord // key: userID|exerciseID|recordType
	workoutUser map[uuid.UUID]uuid.UUID
}

func newFakeWorkoutSetRepo() *fakeWorkoutSetRepo {
	return &fakeWorkoutSetRepo{
		sets:        map[uuid.UUID][]*domain.WorkoutSet{},
		records:     map[string]*domain.PersonalRecord{},
		workoutUser: map[uuid.UUID]uuid.UUID{},
	}
}

func (f *fakeWorkoutSetRepo) FindByID(ctx context.Context, id uuid.UUID) (*domain.WorkoutSet, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, sets := range f.sets {
		for _, s := range sets {
			if s.ID == id {
				return s, nil
			}
		}
	}
	return nil, domain.ErrWorkoutSetNotFound
}

func (f *fakeWorkoutSetRepo) Update(ctx context.Context, set *domain.WorkoutSet) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, sets := range f.sets {
		for _, s := range sets {
			if s.ID == set.ID {
				s.Reps = set.Reps
				s.WeightKg = set.WeightKg
				s.RPE = set.RPE
				s.SetType = set.SetType
				return nil
			}
		}
	}
	return domain.ErrWorkoutSetNotFound
}

func (f *fakeWorkoutSetRepo) Delete(ctx context.Context, id uuid.UUID) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	for workoutID, sets := range f.sets {
		for i, s := range sets {
			if s.ID == id {
				f.sets[workoutID] = append(sets[:i], sets[i+1:]...)
				return nil
			}
		}
	}
	return nil
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
	if set.SetType == "" {
		set.SetType = domain.SetTypeNormal
	}
	f.sets[set.WorkoutID] = append(f.sets[set.WorkoutID], set)
	f.workoutUser[set.WorkoutID] = userID

	if set.SetType == domain.SetTypeWarmup {
		return &domain.LoggedSet{Set: set}, nil
	}

	candidates := map[string]float64{
		domain.RecordTypeMaxWeight:    set.WeightKg,
		domain.RecordTypeMaxVolume:    set.WeightKg * float64(set.Reps),
		domain.RecordTypeEstimated1RM: set.WeightKg * (1 + float64(set.Reps)/30.0),
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

// Recompute mirrors repository.PersonalRecordRepository.Recompute: rebuild
// every record type for this user+exercise from scratch by rescanning all
// non-warmup sets, rather than trusting LogSet's incremental upsert.
func (f *fakePersonalRecordRepo) Recompute(ctx context.Context, userID, exerciseID uuid.UUID) error {
	f.sets.mu.Lock()
	defer f.sets.mu.Unlock()

	best := map[string]*domain.PersonalRecord{}
	for workoutID, sets := range f.sets.sets {
		if f.sets.workoutUser[workoutID] != userID {
			continue
		}
		for _, s := range sets {
			if s.ExerciseID != exerciseID || s.SetType == domain.SetTypeWarmup {
				continue
			}
			candidates := map[string]float64{
				domain.RecordTypeMaxWeight:    s.WeightKg,
				domain.RecordTypeMaxVolume:    s.WeightKg * float64(s.Reps),
				domain.RecordTypeEstimated1RM: s.WeightKg * (1 + float64(s.Reps)/30.0),
			}
			for recordType, value := range candidates {
				if existing, ok := best[recordType]; !ok || value > existing.Value {
					best[recordType] = &domain.PersonalRecord{
						ID: uuid.New(), UserID: userID, ExerciseID: exerciseID,
						RecordType: recordType, Value: value, AchievedAt: s.PerformedAt, WorkoutSetID: s.ID,
					}
				}
			}
		}
	}

	for _, recordType := range []string{domain.RecordTypeMaxWeight, domain.RecordTypeMaxVolume, domain.RecordTypeEstimated1RM} {
		key := userID.String() + "|" + exerciseID.String() + "|" + recordType
		if pr, ok := best[recordType]; ok {
			f.sets.records[key] = pr
		} else {
			delete(f.sets.records, key)
		}
	}
	return nil
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
		nil,
	)
	return svc, setRepo
}

type fakeWorkoutTemplateRepo struct {
	mu   sync.Mutex
	byID map[uuid.UUID]*domain.WorkoutTemplate
}

func newFakeWorkoutTemplateRepo() *fakeWorkoutTemplateRepo {
	return &fakeWorkoutTemplateRepo{byID: map[uuid.UUID]*domain.WorkoutTemplate{}}
}

func (f *fakeWorkoutTemplateRepo) Create(ctx context.Context, t *domain.WorkoutTemplate) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.byID[t.ID] = t
	return nil
}

func (f *fakeWorkoutTemplateRepo) ListForUser(ctx context.Context, userID uuid.UUID) ([]*domain.WorkoutTemplate, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []*domain.WorkoutTemplate
	for _, t := range f.byID {
		if t.UserID == userID {
			out = append(out, t)
		}
	}
	return out, nil
}

func (f *fakeWorkoutTemplateRepo) FindByID(ctx context.Context, id uuid.UUID) (*domain.WorkoutTemplate, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	t, ok := f.byID[id]
	if !ok {
		return nil, domain.ErrTemplateNotFound
	}
	return t, nil
}

func (f *fakeWorkoutTemplateRepo) Delete(ctx context.Context, id uuid.UUID) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	delete(f.byID, id)
	return nil
}

func newTestWorkoutServiceWithTemplates(exercises ...*domain.Exercise) (*service.WorkoutService, *fakeWorkoutTemplateRepo) {
	setRepo := newFakeWorkoutSetRepo()
	templateRepo := newFakeWorkoutTemplateRepo()
	svc := service.NewWorkoutService(
		newFakeExerciseRepo(exercises...),
		newFakeWorkoutRepo(),
		setRepo,
		&fakePersonalRecordRepo{sets: setRepo},
		templateRepo,
		nil,
		nil,
	)
	return svc, templateRepo
}

func TestStartWorkoutIsIdempotent(t *testing.T) {
	ctx := context.Background()
	svc, _ := newTestWorkoutService()
	userID := uuid.New()

	w1, err := svc.StartWorkout(ctx, userID, nil)
	require.NoError(t, err)

	w2, err := svc.StartWorkout(ctx, userID, nil)
	require.NoError(t, err)
	assert.Equal(t, w1.ID, w2.ID, "starting a workout twice should return the existing in-progress one")
}

func TestLogSetRejectsUnownedWorkout(t *testing.T) {
	ctx := context.Background()
	exercise := &domain.Exercise{ID: uuid.New(), Name: "Bench Press"}
	svc, _ := newTestWorkoutService(exercise)

	owner := uuid.New()
	attacker := uuid.New()

	w, err := svc.StartWorkout(ctx, owner, nil)
	require.NoError(t, err)

	_, err = svc.LogSet(ctx, attacker, w.ID, exercise.ID, 5, 100, nil, domain.SetTypeNormal, nil)
	assert.ErrorIs(t, err, domain.ErrWorkoutNotOwned)
}

func TestLogSetRejectsAfterFinish(t *testing.T) {
	ctx := context.Background()
	exercise := &domain.Exercise{ID: uuid.New(), Name: "Squat"}
	svc, _ := newTestWorkoutService(exercise)
	userID := uuid.New()

	w, err := svc.StartWorkout(ctx, userID, nil)
	require.NoError(t, err)

	_, err = svc.FinishWorkout(ctx, userID, w.ID, "done")
	require.NoError(t, err)

	_, err = svc.LogSet(ctx, userID, w.ID, exercise.ID, 5, 100, nil, domain.SetTypeNormal, nil)
	assert.ErrorIs(t, err, domain.ErrWorkoutNotActive)
}

func TestLogSetDetectsNewPersonalRecords(t *testing.T) {
	ctx := context.Background()
	exercise := &domain.Exercise{ID: uuid.New(), Name: "Deadlift"}
	svc, _ := newTestWorkoutService(exercise)
	userID := uuid.New()

	w, err := svc.StartWorkout(ctx, userID, nil)
	require.NoError(t, err)

	first, err := svc.LogSet(ctx, userID, w.ID, exercise.ID, 5, 100, nil, domain.SetTypeNormal, nil)
	require.NoError(t, err)
	assert.Len(t, first.NewRecords, 3, "first set at any weight/volume/1RM is always a new PR across all three record types")

	// a heavier set at fewer reps: breaks max_weight and estimated 1RM
	// (110*(1+2/30)=117.3 > 100*(1+5/30)=116.7), not max_volume (100*5=500 > 110*2=220)
	second, err := svc.LogSet(ctx, userID, w.ID, exercise.ID, 2, 110, nil, domain.SetTypeNormal, nil)
	require.NoError(t, err)
	require.Len(t, second.NewRecords, 2)
	gotTypes := []string{second.NewRecords[0].RecordType, second.NewRecords[1].RecordType}
	assert.Contains(t, gotTypes, domain.RecordTypeMaxWeight)
	assert.Contains(t, gotTypes, domain.RecordTypeEstimated1RM)

	// a lighter set that doesn't beat either record
	third, err := svc.LogSet(ctx, userID, w.ID, exercise.ID, 3, 90, nil, domain.SetTypeNormal, nil)
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
		w, err := svc.StartWorkout(ctx, userID, nil)
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

	w, err := svc.StartWorkout(ctx, userID, nil)
	require.NoError(t, err)

	warmup, err := svc.LogSet(ctx, userID, w.ID, exercise.ID, 10, 20, nil, domain.SetTypeWarmup, nil)
	require.NoError(t, err)
	assert.Empty(t, warmup.NewRecords, "a warm-up set should never register a PR")
	assert.Equal(t, domain.SetTypeWarmup, warmup.Set.SetType)

	working, err := svc.LogSet(ctx, userID, w.ID, exercise.ID, 5, 60, nil, domain.SetTypeNormal, nil)
	require.NoError(t, err)
	assert.Len(t, working.NewRecords, 3, "the first working set should still register all PR types, unaffected by the earlier warm-up")
}

func TestDropSetAndFailureSetCountTowardRecords(t *testing.T) {
	ctx := context.Background()
	exercise := &domain.Exercise{ID: uuid.New(), Name: "Leg Press"}
	svc, _ := newTestWorkoutService(exercise)
	userID := uuid.New()

	w, err := svc.StartWorkout(ctx, userID, nil)
	require.NoError(t, err)

	_, err = svc.LogSet(ctx, userID, w.ID, exercise.ID, 8, 100, nil, domain.SetTypeNormal, nil)
	require.NoError(t, err)

	dropSet, err := svc.LogSet(ctx, userID, w.ID, exercise.ID, 12, 120, nil, domain.SetTypeDropset, nil)
	require.NoError(t, err)
	assert.NotEmpty(t, dropSet.NewRecords, "a drop set is real working effort and should be able to set a PR")

	failureSet, err := svc.LogSet(ctx, userID, w.ID, exercise.ID, 15, 130, nil, domain.SetTypeFailure, nil)
	require.NoError(t, err)
	assert.NotEmpty(t, failureSet.NewRecords, "a failure set is real working effort and should be able to set a PR")
}

func TestSupersetIDPassesThrough(t *testing.T) {
	ctx := context.Background()
	exercise := &domain.Exercise{ID: uuid.New(), Name: "Barbell Bench Press"}
	svc, _ := newTestWorkoutService(exercise)
	userID := uuid.New()

	w, err := svc.StartWorkout(ctx, userID, nil)
	require.NoError(t, err)

	supersetID := uuid.New()
	logged, err := svc.LogSet(ctx, userID, w.ID, exercise.ID, 8, 60, nil, domain.SetTypeNormal, &supersetID)
	require.NoError(t, err)
	require.NotNil(t, logged.Set.SupersetID)
	assert.Equal(t, supersetID, *logged.Set.SupersetID)
}

func TestLastSetForExercise(t *testing.T) {
	ctx := context.Background()
	exercise := &domain.Exercise{ID: uuid.New(), Name: "Barbell Row"}
	svc, _ := newTestWorkoutService(exercise)
	userID := uuid.New()

	none, err := svc.LastSetForExercise(ctx, userID, exercise.ID)
	require.NoError(t, err)
	assert.Nil(t, none, "no error and a nil result when the exercise has never been logged")

	w, err := svc.StartWorkout(ctx, userID, nil)
	require.NoError(t, err)
	_, err = svc.LogSet(ctx, userID, w.ID, exercise.ID, 8, 40, nil, domain.SetTypeNormal, nil)
	require.NoError(t, err)
	_, err = svc.LogSet(ctx, userID, w.ID, exercise.ID, 6, 45, nil, domain.SetTypeNormal, nil)
	require.NoError(t, err)

	last, err := svc.LastSetForExercise(ctx, userID, exercise.ID)
	require.NoError(t, err)
	require.NotNil(t, last)
	assert.Equal(t, 45.0, last.WeightKg, "should return the most recently logged set, not the first")
}

func TestCreateAndStartWorkoutFromTemplate(t *testing.T) {
	ctx := context.Background()
	exercise := &domain.Exercise{ID: uuid.New(), Name: "Bench Press"}
	svc, _ := newTestWorkoutServiceWithTemplates(exercise)
	userID := uuid.New()

	tmpl, err := svc.CreateTemplate(ctx, userID, "Push Day", []*domain.TemplateExercise{
		{ExerciseID: exercise.ID, TargetSets: 3, TargetReps: intPtr(8)},
	})
	require.NoError(t, err)
	require.Len(t, tmpl.Exercises, 1)
	assert.Equal(t, 0, tmpl.Exercises[0].Position)

	templates, err := svc.ListTemplates(ctx, userID)
	require.NoError(t, err)
	assert.Len(t, templates, 1)

	w, err := svc.StartWorkout(ctx, userID, &tmpl.ID)
	require.NoError(t, err)
	require.NotNil(t, w.TemplateID)
	assert.Equal(t, tmpl.ID, *w.TemplateID)
}

func TestStartWorkoutRejectsUnownedTemplate(t *testing.T) {
	ctx := context.Background()
	svc, _ := newTestWorkoutServiceWithTemplates()
	owner := uuid.New()
	attacker := uuid.New()

	tmpl, err := svc.CreateTemplate(ctx, owner, "Leg Day", nil)
	require.NoError(t, err)

	_, err = svc.StartWorkout(ctx, attacker, &tmpl.ID)
	assert.ErrorIs(t, err, domain.ErrTemplateNotOwned)
}

func TestDeleteTemplateRejectsUnowned(t *testing.T) {
	ctx := context.Background()
	svc, _ := newTestWorkoutServiceWithTemplates()
	owner := uuid.New()
	attacker := uuid.New()

	tmpl, err := svc.CreateTemplate(ctx, owner, "Pull Day", nil)
	require.NoError(t, err)

	err = svc.DeleteTemplate(ctx, attacker, tmpl.ID)
	assert.ErrorIs(t, err, domain.ErrTemplateNotOwned)

	require.NoError(t, svc.DeleteTemplate(ctx, owner, tmpl.ID))
	templates, err := svc.ListTemplates(ctx, owner)
	require.NoError(t, err)
	assert.Empty(t, templates)
}

func intPtr(v int) *int { return &v }

func TestSuggestNextSetWithNoHistory(t *testing.T) {
	ctx := context.Background()
	exercise := &domain.Exercise{ID: uuid.New(), Name: "Bench Press"}
	svc, _ := newTestWorkoutService(exercise)
	userID := uuid.New()

	suggestion, err := svc.SuggestNextSet(ctx, userID, exercise.ID)
	require.NoError(t, err)
	assert.Nil(t, suggestion, "no prior set means no suggestion, not an error")
}

func TestSuggestNextSetAutoregulatesByRPE(t *testing.T) {
	ctx := context.Background()
	exercise := &domain.Exercise{ID: uuid.New(), Name: "Bench Press"}
	svc, _ := newTestWorkoutService(exercise)
	userID := uuid.New()
	w, err := svc.StartWorkout(ctx, userID, nil)
	require.NoError(t, err)

	easy := 6.5
	_, err = svc.LogSet(ctx, userID, w.ID, exercise.ID, 5, 100, &easy, domain.SetTypeNormal, nil)
	require.NoError(t, err)
	suggestion, err := svc.SuggestNextSet(ctx, userID, exercise.ID)
	require.NoError(t, err)
	require.NotNil(t, suggestion)
	assert.Greater(t, suggestion.SuggestedWeightKg, 100.0, "an easy RPE should suggest going heavier")

	hard := 9.5
	_, err = svc.LogSet(ctx, userID, w.ID, exercise.ID, 5, 100, &hard, domain.SetTypeNormal, nil)
	require.NoError(t, err)
	suggestion, err = svc.SuggestNextSet(ctx, userID, exercise.ID)
	require.NoError(t, err)
	require.NotNil(t, suggestion)
	assert.Less(t, suggestion.SuggestedWeightKg, 100.0, "a near-failure RPE should suggest backing off")
}

func TestUpdateSetChangesValuesAndRecomputesRecords(t *testing.T) {
	ctx := context.Background()
	exercise := &domain.Exercise{ID: uuid.New(), Name: "Squat"}
	svc, _ := newTestWorkoutService(exercise)
	userID := uuid.New()
	w, err := svc.StartWorkout(ctx, userID, nil)
	require.NoError(t, err)

	logged, err := svc.LogSet(ctx, userID, w.ID, exercise.ID, 5, 100, nil, domain.SetTypeNormal, nil)
	require.NoError(t, err)
	require.Len(t, logged.NewRecords, 3, "a first-ever set sets all three record types")

	updated, err := svc.UpdateSet(ctx, userID, logged.Set.ID, 8, 120, nil, domain.SetTypeNormal)
	require.NoError(t, err)
	assert.Equal(t, 8, updated.Reps)
	assert.Equal(t, 120.0, updated.WeightKg)

	records, err := svc.PersonalRecords(ctx, userID)
	require.NoError(t, err)
	require.Len(t, records, 3)
	for _, r := range records {
		if r.RecordType == domain.RecordTypeMaxWeight {
			assert.Equal(t, 120.0, r.Value, "PR should reflect the edited weight, not the original")
		}
	}
}

func TestUpdateSetRejectsUnowned(t *testing.T) {
	ctx := context.Background()
	exercise := &domain.Exercise{ID: uuid.New(), Name: "Squat"}
	svc, _ := newTestWorkoutService(exercise)
	owner := uuid.New()
	intruder := uuid.New()
	w, err := svc.StartWorkout(ctx, owner, nil)
	require.NoError(t, err)
	logged, err := svc.LogSet(ctx, owner, w.ID, exercise.ID, 5, 100, nil, domain.SetTypeNormal, nil)
	require.NoError(t, err)

	_, err = svc.UpdateSet(ctx, intruder, logged.Set.ID, 5, 999, nil, domain.SetTypeNormal)
	assert.ErrorIs(t, err, domain.ErrWorkoutNotOwned)
}

func TestDeleteSetRemovesRecordAndFallsBackToNextBest(t *testing.T) {
	ctx := context.Background()
	exercise := &domain.Exercise{ID: uuid.New(), Name: "Bench Press"}
	svc, _ := newTestWorkoutService(exercise)
	userID := uuid.New()
	w, err := svc.StartWorkout(ctx, userID, nil)
	require.NoError(t, err)

	lighter, err := svc.LogSet(ctx, userID, w.ID, exercise.ID, 5, 80, nil, domain.SetTypeNormal, nil)
	require.NoError(t, err)
	heavier, err := svc.LogSet(ctx, userID, w.ID, exercise.ID, 5, 100, nil, domain.SetTypeNormal, nil)
	require.NoError(t, err)
	require.NotEmpty(t, heavier.NewRecords)

	err = svc.DeleteSet(ctx, userID, heavier.Set.ID)
	require.NoError(t, err)

	sets, err := svc.SetsForWorkout(ctx, userID, w.ID)
	require.NoError(t, err)
	require.Len(t, sets, 1, "the deleted set should be gone")
	assert.Equal(t, lighter.Set.ID, sets[0].ID)

	records, err := svc.PersonalRecords(ctx, userID)
	require.NoError(t, err)
	for _, r := range records {
		if r.RecordType == domain.RecordTypeMaxWeight {
			assert.Equal(t, 80.0, r.Value, "with the 100kg set gone, the 80kg set should now hold the PR")
		}
	}
}

func TestDeleteSetRejectsUnowned(t *testing.T) {
	ctx := context.Background()
	exercise := &domain.Exercise{ID: uuid.New(), Name: "Squat"}
	svc, _ := newTestWorkoutService(exercise)
	owner := uuid.New()
	intruder := uuid.New()
	w, err := svc.StartWorkout(ctx, owner, nil)
	require.NoError(t, err)
	logged, err := svc.LogSet(ctx, owner, w.ID, exercise.ID, 5, 100, nil, domain.SetTypeNormal, nil)
	require.NoError(t, err)

	err = svc.DeleteSet(ctx, intruder, logged.Set.ID)
	assert.ErrorIs(t, err, domain.ErrWorkoutNotOwned)
}

func TestDeleteWorkoutRemovesItAndItsRecords(t *testing.T) {
	ctx := context.Background()
	exercise := &domain.Exercise{ID: uuid.New(), Name: "Deadlift"}
	svc, _ := newTestWorkoutService(exercise)
	userID := uuid.New()
	w, err := svc.StartWorkout(ctx, userID, nil)
	require.NoError(t, err)
	logged, err := svc.LogSet(ctx, userID, w.ID, exercise.ID, 5, 150, nil, domain.SetTypeNormal, nil)
	require.NoError(t, err)
	require.NotEmpty(t, logged.NewRecords)

	err = svc.DeleteWorkout(ctx, userID, w.ID)
	require.NoError(t, err)

	_, err = svc.SetsForWorkout(ctx, userID, w.ID)
	assert.ErrorIs(t, err, domain.ErrWorkoutNotFound)

	records, err := svc.PersonalRecords(ctx, userID)
	require.NoError(t, err)
	assert.Empty(t, records, "deleting the only workout should leave no personal records behind")
}

func TestDeleteWorkoutRejectsUnowned(t *testing.T) {
	ctx := context.Background()
	svc, _ := newTestWorkoutService()
	owner := uuid.New()
	intruder := uuid.New()
	w, err := svc.StartWorkout(ctx, owner, nil)
	require.NoError(t, err)

	err = svc.DeleteWorkout(ctx, intruder, w.ID)
	assert.ErrorIs(t, err, domain.ErrWorkoutNotOwned)
}
