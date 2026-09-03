package service_test

import (
	"context"
	"strings"
	"sync"
	"testing"

	"gymon/internal/domain"
	"gymon/internal/service"

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

func (f *fakeProgramRepo) SetActive(ctx context.Context, userID, programID uuid.UUID) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, p := range f.byID {
		if p.UserID == userID {
			p.IsActive = p.ID == programID
		}
	}
	return nil
}

func (f *fakeProgramRepo) FindActiveForUser(ctx context.Context, userID uuid.UUID) (*domain.Program, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, p := range f.byID {
		if p.UserID == userID && p.IsActive {
			return p, nil
		}
	}
	return nil, nil
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

// richCatalog covers every movement pattern the generator balances around,
// with 2+ options each, so a generated split can be checked for balance.
func richCatalog() []*domain.Exercise {
	mk := func(name, category, equipment string, muscleGroups ...string) *domain.Exercise {
		return &domain.Exercise{ID: uuid.New(), Name: name, Category: category, Equipment: equipment, MuscleGroups: muscleGroups}
	}
	return []*domain.Exercise{
		// squat (knee-dominant)
		mk("Back Squat", "legs", "barbell", "quads", "glutes"),
		mk("Leg Press", "legs", "machine", "quads", "glutes"),
		mk("Walking Lunge", "legs", "bodyweight", "quads", "glutes"),
		// hinge (hip-dominant)
		mk("Romanian Deadlift", "legs", "barbell", "hamstrings", "glutes"),
		mk("Hip Thrust", "legs", "barbell", "glutes", "hamstrings"),
		mk("Conventional Deadlift", "pull", "barbell", "hamstrings", "glutes", "back"),
		// horizontal push
		mk("Bench Press", "push", "barbell", "chest", "triceps", "shoulders"),
		mk("Push-Up", "push", "bodyweight", "chest", "triceps"),
		// vertical push
		mk("Overhead Press", "push", "barbell", "shoulders", "triceps"),
		mk("Pike Push-Up", "push", "bodyweight", "shoulders", "triceps"),
		// horizontal pull
		mk("Barbell Row", "pull", "barbell", "back", "biceps"),
		mk("Seated Cable Row", "pull", "cable", "back", "biceps"),
		// vertical pull
		mk("Pull-Up", "pull", "bodyweight", "back", "biceps"),
		mk("Lat Pulldown", "pull", "cable", "back", "biceps"),
		// arms
		mk("Barbell Curl", "arms", "barbell", "biceps"),
		mk("Cable Curl", "arms", "cable", "biceps"),
		mk("Triceps Pushdown", "arms", "cable", "triceps"),
		mk("Overhead Triceps Extension", "arms", "dumbbell", "triceps"),
		// core
		mk("Plank", "core", "bodyweight", "abs"),
		mk("Hanging Leg Raise", "core", "bodyweight", "abs"),
	}
}

// dayExerciseNames resolves a generated day's template exercise IDs back to
// names using the catalog that was fed to the service.
func dayExerciseNames(day *domain.ProgramDay, catalog []*domain.Exercise) []string {
	byID := map[uuid.UUID]string{}
	for _, e := range catalog {
		byID[e.ID] = e.Name
	}
	var names []string
	for _, te := range day.Template.Exercises {
		names = append(names, byID[te.ExerciseID])
	}
	return names
}

func containsAnyName(names []string, subs ...string) bool {
	for _, n := range names {
		for _, s := range subs {
			if strings.Contains(strings.ToLower(n), s) {
				return true
			}
		}
	}
	return false
}

func newTestProgramService(exercises ...*domain.Exercise) (*service.ProgramService, *fakeFitnessProfileRepo, *fakeProgramRepo) {
	workoutSvc, _ := newTestWorkoutServiceWithTemplates(exercises...)
	profiles := newFakeFitnessProfileRepo()
	programs := newFakeProgramRepo()
	exerciseRepo := newFakeExerciseRepo(exercises...)
	svc := service.NewProgramService(profiles, programs, exerciseRepo, workoutSvc)
	return svc, profiles, programs
}

func TestGenerateProgramBalancesMovementPatterns(t *testing.T) {
	ctx := context.Background()
	userID := uuid.New()
	catalog := richCatalog()
	svc, _, _ := newTestProgramService(catalog...)

	_, err := svc.SaveFitnessProfile(ctx, userID, domain.UserFitnessProfile{
		Goal: domain.GoalHypertrophy, ExperienceLevel: domain.ExperienceIntermediate, DaysPerWeek: 5,
	})
	require.NoError(t, err)

	program, err := svc.GenerateProgram(ctx, userID)
	require.NoError(t, err)
	assert.Empty(t, program.Notes, "a full catalog should fill every pattern: %s", program.Notes)

	for _, day := range program.Days {
		names := dayExerciseNames(day, catalog)
		switch {
		case strings.HasPrefix(day.DayLabel, "Legs"), strings.HasPrefix(day.DayLabel, "Lower"):
			assert.True(t, containsAnyName(names, "squat", "lunge", "leg press"), "%s needs a squat pattern: %v", day.DayLabel, names)
			assert.True(t, containsAnyName(names, "deadlift", "romanian", "hip thrust"), "%s needs a hinge pattern: %v", day.DayLabel, names)
		case strings.HasPrefix(day.DayLabel, "Push"):
			assert.True(t, containsAnyName(names, "bench", "push-up"), "%s needs a horizontal press: %v", day.DayLabel, names)
			assert.True(t, containsAnyName(names, "overhead", "pike"), "%s needs a vertical press: %v", day.DayLabel, names)
		case strings.HasPrefix(day.DayLabel, "Pull"):
			assert.True(t, containsAnyName(names, "pull-up", "pulldown"), "%s needs a vertical pull: %v", day.DayLabel, names)
			assert.True(t, containsAnyName(names, "row"), "%s needs a horizontal pull: %v", day.DayLabel, names)
		}
		// No day should use the same exercise twice.
		seen := map[string]bool{}
		for _, n := range names {
			assert.False(t, seen[n], "%s repeats exercise %q", day.DayLabel, n)
			seen[n] = true
		}
	}
}

func TestProgramDayTargetsSuggestsLoadsFromHistory(t *testing.T) {
	ctx := context.Background()
	userID := uuid.New()
	catalog := richCatalog()

	workoutSvc, _ := newTestWorkoutServiceWithTemplates(catalog...)
	profiles := newFakeFitnessProfileRepo()
	programs := newFakeProgramRepo()
	svc := service.NewProgramService(profiles, programs, newFakeExerciseRepo(catalog...), workoutSvc)

	_, err := svc.SaveFitnessProfile(ctx, userID, domain.UserFitnessProfile{
		Goal: domain.GoalStrength, ExperienceLevel: domain.ExperienceIntermediate, DaysPerWeek: 3,
	})
	require.NoError(t, err)
	program, err := svc.GenerateProgram(ctx, userID)
	require.NoError(t, err)

	day := program.Days[0]
	firstExerciseID := day.Template.Exercises[0].ExerciseID

	// No history yet → 0 suggestion, first-time reasoning.
	targets, err := svc.ProgramDayTargets(ctx, userID, day.ID)
	require.NoError(t, err)
	require.NotEmpty(t, targets)
	assert.Equal(t, 0.0, targets[0].SuggestedWeightKg)
	assert.Equal(t, 1, targets[0].WeekNumber)
	assert.Contains(t, targets[0].Reasoning, "First time")

	// Log a working set, then it should suggest at least that weight.
	w, err := workoutSvc.StartWorkout(ctx, userID, nil)
	require.NoError(t, err)
	_, err = workoutSvc.LogSet(ctx, userID, w.ID, firstExerciseID, 5, 100, nil, domain.SetTypeNormal, nil)
	require.NoError(t, err)

	targets, err = svc.ProgramDayTargets(ctx, userID, day.ID)
	require.NoError(t, err)
	assert.GreaterOrEqual(t, targets[0].SuggestedWeightKg, 100.0)
}

func TestGenerateProgramSupportsSevenDays(t *testing.T) {
	ctx := context.Background()
	userID := uuid.New()
	svc, _, _ := newTestProgramService(richCatalog()...)
	_, err := svc.SaveFitnessProfile(ctx, userID, domain.UserFitnessProfile{
		Goal: domain.GoalGeneralFitness, ExperienceLevel: domain.ExperienceAdvanced, DaysPerWeek: 7,
	})
	require.NoError(t, err)
	program, err := svc.GenerateProgram(ctx, userID)
	require.NoError(t, err)
	assert.Len(t, program.Days, 7)
	assert.Equal(t, 7, program.DaysPerWeek)
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
	assert.Contains(t, program.Notes, "squat", "the skip note should name the unfillable movement pattern")
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
