package service_test

import (
	"context"
	"testing"

	"workouttracker/internal/domain"
	"workouttracker/internal/service"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// newTestProgramServiceFull is like newTestProgramService but also exposes
// the underlying WorkoutService, so tests can start/finish workouts against
// the same in-memory fakes to drive NextWorkout's rotation logic.
func newTestProgramServiceFull(exercises ...*domain.Exercise) (*service.ProgramService, *fakeProgramRepo, *service.WorkoutService) {
	workoutSvc, templateRepo := newTestWorkoutServiceWithTemplates(exercises...)
	profiles := newFakeFitnessProfileRepo()
	programs := newFakeProgramRepo()
	exerciseRepo := newFakeExerciseRepo(exercises...)
	svc := service.NewProgramService(profiles, programs, exerciseRepo, workoutSvc)
	_ = templateRepo
	return svc, programs, workoutSvc
}

func twoExerciseCatalog() []*domain.Exercise {
	return []*domain.Exercise{
		{ID: uuid.New(), Name: "Bench Press", Category: "push", Equipment: "barbell", MuscleGroups: []string{"chest"}},
		{ID: uuid.New(), Name: "Barbell Row", Category: "pull", Equipment: "barbell", MuscleGroups: []string{"back"}},
	}
}

// buildTwoDayProgram creates two templates via WorkoutService and a program
// referencing them via CreateFromTemplates — the exact path a manually-built
// program takes, reused as test setup for the NextWorkout tests below.
func buildTwoDayProgram(t *testing.T, ctx context.Context, svc *service.ProgramService, workoutSvc *service.WorkoutService, userID uuid.UUID, exercises []*domain.Exercise) *domain.Program {
	t.Helper()
	dayA, err := workoutSvc.CreateTemplate(ctx, userID, "Day A", []*domain.TemplateExercise{{ExerciseID: exercises[0].ID, TargetSets: 3}})
	require.NoError(t, err)
	dayB, err := workoutSvc.CreateTemplate(ctx, userID, "Day B", []*domain.TemplateExercise{{ExerciseID: exercises[1].ID, TargetSets: 3}})
	require.NoError(t, err)

	program, err := svc.CreateFromTemplates(ctx, userID, "Test Program", []service.DayInput{
		{DayLabel: "Day A", TemplateID: dayA.ID},
		{DayLabel: "Day B", TemplateID: dayB.ID},
	})
	require.NoError(t, err)
	return program
}

func TestCreateFromTemplatesBuildsOrderedDaysAndDefaultsGoal(t *testing.T) {
	ctx := context.Background()
	userID := uuid.New()
	exercises := twoExerciseCatalog()
	svc, _, workoutSvc := newTestProgramServiceFull(exercises...)

	program := buildTwoDayProgram(t, ctx, svc, workoutSvc, userID, exercises)

	assert.Equal(t, "Test Program", program.Name)
	assert.Equal(t, domain.GoalGeneralFitness, program.Goal, "hand-built programs default to general fitness — no questionnaire to derive a real goal from")
	assert.Equal(t, 2, program.DaysPerWeek)
	require.Len(t, program.Days, 2)
	assert.Equal(t, "Day A", program.Days[0].DayLabel)
	assert.Equal(t, 0, program.Days[0].Position)
	assert.Equal(t, "Day B", program.Days[1].DayLabel)
	assert.Equal(t, 1, program.Days[1].Position)
}

func TestCreateFromTemplatesActivatesTheNewProgram(t *testing.T) {
	ctx := context.Background()
	userID := uuid.New()
	exercises := twoExerciseCatalog()
	svc, _, workoutSvc := newTestProgramServiceFull(exercises...)

	first := buildTwoDayProgram(t, ctx, svc, workoutSvc, userID, exercises)
	assert.True(t, first.IsActive, "the only program should become active on creation")

	second := buildTwoDayProgram(t, ctx, svc, workoutSvc, userID, exercises)
	assert.True(t, second.IsActive, "newly-created program becomes active")

	programs, err := svc.MyPrograms(ctx, userID)
	require.NoError(t, err)
	activeCount := 0
	for _, p := range programs {
		if p.IsActive {
			activeCount++
			assert.Equal(t, second.ID, p.ID, "creating a second program should deactivate the first")
		}
	}
	assert.Equal(t, 1, activeCount, "at most one program is ever active at a time")
}

func TestCreateFromTemplatesRejectsATemplateOwnedByAnotherUser(t *testing.T) {
	ctx := context.Background()
	owner := uuid.New()
	attacker := uuid.New()
	exercises := twoExerciseCatalog()
	svc, _, workoutSvc := newTestProgramServiceFull(exercises...)

	template, err := workoutSvc.CreateTemplate(ctx, owner, "Owner's template", []*domain.TemplateExercise{{ExerciseID: exercises[0].ID, TargetSets: 3}})
	require.NoError(t, err)

	_, err = svc.CreateFromTemplates(ctx, attacker, "Stolen program", []service.DayInput{
		{DayLabel: "Day A", TemplateID: template.ID},
	})
	assert.ErrorIs(t, err, domain.ErrTemplateNotOwned)
}

func TestSetActiveProgramSwitchesWhichProgramIsActive(t *testing.T) {
	ctx := context.Background()
	userID := uuid.New()
	exercises := twoExerciseCatalog()
	svc, _, workoutSvc := newTestProgramServiceFull(exercises...)

	first := buildTwoDayProgram(t, ctx, svc, workoutSvc, userID, exercises)
	second := buildTwoDayProgram(t, ctx, svc, workoutSvc, userID, exercises)
	require.True(t, second.IsActive)

	updated, err := svc.SetActiveProgram(ctx, userID, first.ID)
	require.NoError(t, err)
	assert.True(t, updated.IsActive)

	programs, err := svc.MyPrograms(ctx, userID)
	require.NoError(t, err)
	for _, p := range programs {
		assert.Equal(t, p.ID == first.ID, p.IsActive, "exactly the reactivated program should be active")
	}
}

func TestSetActiveProgramRejectsAProgramOwnedByAnotherUser(t *testing.T) {
	ctx := context.Background()
	owner := uuid.New()
	attacker := uuid.New()
	exercises := twoExerciseCatalog()
	svc, _, workoutSvc := newTestProgramServiceFull(exercises...)

	program := buildTwoDayProgram(t, ctx, svc, workoutSvc, owner, exercises)

	_, err := svc.SetActiveProgram(ctx, attacker, program.ID)
	assert.ErrorIs(t, err, domain.ErrProgramNotOwned)
}

func TestNextWorkoutIsNilWithoutAnActiveProgram(t *testing.T) {
	ctx := context.Background()
	userID := uuid.New()
	svc, _, _ := newTestProgramServiceFull(twoExerciseCatalog()...)

	next, err := svc.NextWorkout(ctx, userID)
	require.NoError(t, err)
	assert.Nil(t, next)
}

func TestNextWorkoutStartsAtPositionZeroForAFreshProgram(t *testing.T) {
	ctx := context.Background()
	userID := uuid.New()
	exercises := twoExerciseCatalog()
	svc, _, workoutSvc := newTestProgramServiceFull(exercises...)
	program := buildTwoDayProgram(t, ctx, svc, workoutSvc, userID, exercises)

	next, err := svc.NextWorkout(ctx, userID)
	require.NoError(t, err)
	require.NotNil(t, next)
	assert.Equal(t, program.ID, next.Program.ID)
	assert.Equal(t, "Day A", next.Day.DayLabel)
	assert.Equal(t, 0, next.Day.Position)
}

func TestNextWorkoutAdvancesAfterFinishingADayAndWrapsAround(t *testing.T) {
	ctx := context.Background()
	userID := uuid.New()
	exercises := twoExerciseCatalog()
	svc, _, workoutSvc := newTestProgramServiceFull(exercises...)
	program := buildTwoDayProgram(t, ctx, svc, workoutSvc, userID, exercises)

	finishTemplate := func(templateID uuid.UUID) {
		w, err := workoutSvc.StartWorkout(ctx, userID, &templateID)
		require.NoError(t, err)
		_, err = workoutSvc.FinishWorkout(ctx, userID, w.ID, "")
		require.NoError(t, err)
	}

	// Finish Day A -> next should be Day B (position 1).
	finishTemplate(program.Days[0].TemplateID)
	next, err := svc.NextWorkout(ctx, userID)
	require.NoError(t, err)
	require.NotNil(t, next)
	assert.Equal(t, "Day B", next.Day.DayLabel)
	assert.Equal(t, 1, next.Day.Position)

	// Finish Day B -> wraps back around to Day A (position 0).
	finishTemplate(program.Days[1].TemplateID)
	next, err = svc.NextWorkout(ctx, userID)
	require.NoError(t, err)
	require.NotNil(t, next)
	assert.Equal(t, "Day A", next.Day.DayLabel)
	assert.Equal(t, 0, next.Day.Position)
}

func TestNextWorkoutFollowsTheActiveProgramNotTheMostRecentlyCreated(t *testing.T) {
	ctx := context.Background()
	userID := uuid.New()
	exercises := twoExerciseCatalog()
	svc, _, workoutSvc := newTestProgramServiceFull(exercises...)

	older := buildTwoDayProgram(t, ctx, svc, workoutSvc, userID, exercises)
	_ = buildTwoDayProgram(t, ctx, svc, workoutSvc, userID, exercises) // becomes active on creation

	// Explicitly switch back to the older program.
	_, err := svc.SetActiveProgram(ctx, userID, older.ID)
	require.NoError(t, err)

	next, err := svc.NextWorkout(ctx, userID)
	require.NoError(t, err)
	require.NotNil(t, next)
	assert.Equal(t, older.ID, next.Program.ID, "NextWorkout must follow whichever program is active, not just the newest one")
}
