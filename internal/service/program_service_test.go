package service_test

import (
	"context"
	"sync"
	"testing"

	"workouttracker/internal/domain"
	"workouttracker/internal/service"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type fakeFitnessProfileRepo struct {
	mu   sync.Mutex
	byID map[uuid.UUID]*domain.UserFitnessProfile
}

func newFakeFitnessProfileRepo() *fakeFitnessProfileRepo {
	return &fakeFitnessProfileRepo{byID: map[uuid.UUID]*domain.UserFitnessProfile{}}
}

func (f *fakeFitnessProfileRepo) Get(ctx context.Context, userID uuid.UUID) (*domain.UserFitnessProfile, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	p, ok := f.byID[userID]
	if !ok {
		return nil, domain.ErrFitnessProfileNotFound
	}
	return p, nil
}

func (f *fakeFitnessProfileRepo) Upsert(ctx context.Context, p *domain.UserFitnessProfile) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	cp := *p
	f.byID[p.UserID] = &cp
	return nil
}

type fakeProgramRepo struct {
	mu   sync.Mutex
	byID map[uuid.UUID]*domain.Program
}

func newFakeProgramRepo() *fakeProgramRepo {
	return &fakeProgramRepo{byID: map[uuid.UUID]*domain.Program{}}
}

func (f *fakeProgramRepo) Create(ctx context.Context, p *domain.Program) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.byID[p.ID] = p
	return nil
}

func (f *fakeProgramRepo) ListForUser(ctx context.Context, userID uuid.UUID) ([]*domain.Program, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []*domain.Program
	for _, p := range f.byID {
		if p.UserID == userID {
			out = append(out, p)
		}
	}
	return out, nil
}

func (f *fakeProgramRepo) FindByID(ctx context.Context, id uuid.UUID) (*domain.Program, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	p, ok := f.byID[id]
	if !ok {
		return nil, domain.ErrProgramNotFound
	}
	return p, nil
}

func (f *fakeProgramRepo) Delete(ctx context.Context, id uuid.UUID) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	delete(f.byID, id)
	return nil
}

// fullCatalog is a small but complete-enough exercise set for the
// generator's tests: at least one bodyweight and one non-bodyweight option
// per category, and a distinct muscle group per exercise so
// avoid-muscle-group exclusion tests have something unambiguous to exclude.
func fullCatalog() []*domain.Exercise {
	mk := func(name, category, equipment string, muscleGroups ...string) *domain.Exercise {
		return &domain.Exercise{ID: uuid.New(), Name: name, Category: category, Equipment: equipment, MuscleGroups: muscleGroups}
	}
	return []*domain.Exercise{
		mk("Bench Press", "push", "barbell", "chest", "triceps"),
		mk("Push-Up", "push", "bodyweight", "chest", "triceps"),
		mk("Barbell Row", "pull", "barbell", "back", "biceps"),
		mk("Inverted Row", "pull", "bodyweight", "back", "biceps"),
		mk("Back Squat", "legs", "barbell", "quads", "glutes"),
		mk("Bodyweight Squat", "legs", "bodyweight", "quads", "glutes"),
		mk("Barbell Curl", "arms", "barbell", "biceps"),
		mk("Dips", "arms", "bodyweight", "triceps"),
		mk("Plank", "core", "bodyweight", "abs"),
	}
}

func newTestProgramService(exercises ...*domain.Exercise) (*service.ProgramService, *fakeFitnessProfileRepo, *fakeProgramRepo) {
	workoutSvc, _ := newTestWorkoutServiceWithTemplates(exercises...)
	profiles := newFakeFitnessProfileRepo()
	programs := newFakeProgramRepo()
	exerciseRepo := newFakeExerciseRepo(exercises...)
	svc := service.NewProgramService(profiles, programs, exerciseRepo, workoutSvc)
	return svc, profiles, programs
}

func TestGenerateProgramRejectsWithoutSavedProfile(t *testing.T) {
	ctx := context.Background()
	svc, _, _ := newTestProgramService(fullCatalog()...)

	_, err := svc.GenerateProgram(ctx, uuid.New())
	assert.ErrorIs(t, err, domain.ErrFitnessProfileNotFound)
}

func TestGenerateProgramPicksSplitByDaysPerWeek(t *testing.T) {
	ctx := context.Background()
	userID := uuid.New()

	cases := []struct {
		days          int
		wantDayCount  int
		wantDayLabels []string
	}{
		{days: 3, wantDayCount: 3, wantDayLabels: []string{"Full Body 1", "Full Body 2", "Full Body 3"}},
		{days: 4, wantDayCount: 4, wantDayLabels: []string{"Upper 1", "Lower 1", "Upper 2", "Lower 2"}},
		{days: 6, wantDayCount: 6, wantDayLabels: []string{"Push 1", "Pull 1", "Legs 1", "Push 2", "Pull 2", "Legs 2"}},
	}

	for _, tc := range cases {
		svc, _, _ := newTestProgramService(fullCatalog()...)
		_, err := svc.SaveFitnessProfile(ctx, userID, domain.UserFitnessProfile{
			Goal: domain.GoalGeneralFitness, ExperienceLevel: domain.ExperienceBeginner, DaysPerWeek: tc.days,
		})
		require.NoError(t, err)

		program, err := svc.GenerateProgram(ctx, userID)
		require.NoError(t, err)
		require.Len(t, program.Days, tc.wantDayCount)

		var labels []string
		for _, d := range program.Days {
			labels = append(labels, d.DayLabel)
		}
		assert.Equal(t, tc.wantDayLabels, labels)
	}
}

func TestGenerateProgramRespectsEquipmentAccess(t *testing.T) {
	ctx := context.Background()
	userID := uuid.New()
	catalog := fullCatalog()
	svc, _, _ := newTestProgramService(catalog...)

	_, err := svc.SaveFitnessProfile(ctx, userID, domain.UserFitnessProfile{
		Goal: domain.GoalGeneralFitness, ExperienceLevel: domain.ExperienceBeginner, DaysPerWeek: 3,
		EquipmentAccess: []string{"bodyweight"},
	})
	require.NoError(t, err)

	program, err := svc.GenerateProgram(ctx, userID)
	require.NoError(t, err)
	require.NotEmpty(t, program.Days)

	sawAnyExercise := false
	for _, day := range program.Days {
		for _, te := range day.Template.Exercises {
			ex := findExercise(catalog, te.ExerciseID)
			require.NotNil(t, ex)
			assert.Equal(t, "bodyweight", ex.Equipment, "equipment_access: [bodyweight] should never select a barbell exercise")
			sawAnyExercise = true
		}
	}
	assert.True(t, sawAnyExercise, "expected at least one exercise to be selected")
}

func findExercise(catalog []*domain.Exercise, id uuid.UUID) *domain.Exercise {
	for _, e := range catalog {
		if e.ID == id {
			return e
		}
	}
	return nil
}

func TestGenerateProgramExcludesAvoidedMuscleGroups(t *testing.T) {
	ctx := context.Background()
	userID := uuid.New()
	catalog := fullCatalog()
	svc, _, _ := newTestProgramService(catalog...)

	_, err := svc.SaveFitnessProfile(ctx, userID, domain.UserFitnessProfile{
		Goal: domain.GoalGeneralFitness, ExperienceLevel: domain.ExperienceBeginner, DaysPerWeek: 3,
		AvoidMuscleGroups: []string{"quads", "glutes"},
	})
	require.NoError(t, err)

	program, err := svc.GenerateProgram(ctx, userID)
	require.NoError(t, err)

	for _, day := range program.Days {
		for _, te := range day.Template.Exercises {
			ex := findExercise(catalog, te.ExerciseID)
			require.NotNil(t, ex)
			assert.NotContains(t, ex.MuscleGroups, "quads")
			assert.NotContains(t, ex.MuscleGroups, "glutes")
		}
	}
	// legs day should have skipped or fallen back — either way, no leg
	// exercise touching quads/glutes was selected, which the loop above
	// already confirms; also check the day ran without hard-failing.
	require.NotEmpty(t, program.Days)
}

func TestGenerateProgramNotesSkippedGroupsRatherThanFailing(t *testing.T) {
	ctx := context.Background()
	userID := uuid.New()
	// A catalog with no leg exercises at all forces "legs" to be
	// unfillable — generation should still succeed and explain why via
	// Notes, not error out.
	catalog := []*domain.Exercise{
		{ID: uuid.New(), Name: "Bench Press", Category: "push", Equipment: "barbell", MuscleGroups: []string{"chest"}},
		{ID: uuid.New(), Name: "Barbell Row", Category: "pull", Equipment: "barbell", MuscleGroups: []string{"back"}},
		{ID: uuid.New(), Name: "Barbell Curl", Category: "arms", Equipment: "barbell", MuscleGroups: []string{"biceps"}},
		{ID: uuid.New(), Name: "Plank", Category: "core", Equipment: "bodyweight", MuscleGroups: []string{"abs"}},
	}
	svc, _, _ := newTestProgramService(catalog...)

	_, err := svc.SaveFitnessProfile(ctx, userID, domain.UserFitnessProfile{
		Goal: domain.GoalGeneralFitness, ExperienceLevel: domain.ExperienceBeginner, DaysPerWeek: 3,
	})
	require.NoError(t, err)

	program, err := svc.GenerateProgram(ctx, userID)
	require.NoError(t, err, "missing exercises for one category should degrade gracefully, not fail generation")
	assert.NotEmpty(t, program.Notes, "should explain that no leg exercise was available")
	assert.Contains(t, program.Notes, "legs")
}

func TestSaveFitnessProfileRoundTrips(t *testing.T) {
	ctx := context.Background()
	userID := uuid.New()
	svc, _, _ := newTestProgramService(fullCatalog()...)

	saved, err := svc.SaveFitnessProfile(ctx, userID, domain.UserFitnessProfile{
		Goal: domain.GoalStrength, ExperienceLevel: domain.ExperienceAdvanced, DaysPerWeek: 5,
		EquipmentAccess: []string{"barbell", "dumbbell"}, AvoidMuscleGroups: []string{"abs"},
	})
	require.NoError(t, err)
	assert.Equal(t, domain.GoalStrength, saved.Goal)

	got, err := svc.MyFitnessProfile(ctx, userID)
	require.NoError(t, err)
	require.NotNil(t, got)
	assert.Equal(t, domain.ExperienceAdvanced, got.ExperienceLevel)
	assert.Equal(t, 5, got.DaysPerWeek)
}

func TestMyFitnessProfileReturnsNilWithoutError(t *testing.T) {
	ctx := context.Background()
	svc, _, _ := newTestProgramService(fullCatalog()...)

	profile, err := svc.MyFitnessProfile(ctx, uuid.New())
	require.NoError(t, err)
	assert.Nil(t, profile)
}
