package repository_test

import (
	"context"
	"testing"
	"time"

	"gymon/internal/domain"
	"gymon/internal/repository"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func intPtr(v int) *int { return &v }

func makeTemplate(t *testing.T, repo *repository.WorkoutTemplateRepository, userID uuid.UUID, name string, exerciseIDs ...uuid.UUID) *domain.WorkoutTemplate {
	t.Helper()
	tmpl := &domain.WorkoutTemplate{ID: uuid.New(), UserID: userID, Name: name, CreatedAt: time.Now()}
	for i, exID := range exerciseIDs {
		tmpl.Exercises = append(tmpl.Exercises, &domain.TemplateExercise{
			ID: uuid.New(), ExerciseID: exID, Position: i, TargetSets: 3, TargetReps: intPtr(8),
		})
	}
	require.NoError(t, repo.Create(context.Background(), tmpl))
	return tmpl
}

func TestWorkoutTemplateRepository_CreateFindList(t *testing.T) {
	pool := requireDB(t)
	user := makeUser(t, pool)
	repo := repository.NewWorkoutTemplateRepository(pool)
	ctx := context.Background()

	bench := anyExerciseID(t, pool, "Barbell Bench Press")
	squat := anyExerciseID(t, pool, "Barbell Back Squat")
	tmpl := makeTemplate(t, repo, user.ID, "Push Day "+uuid.NewString()[:6], bench, squat)

	got, err := repo.FindByID(ctx, tmpl.ID)
	require.NoError(t, err)
	assert.Equal(t, tmpl.Name, got.Name)
	require.Len(t, got.Exercises, 2)
	assert.Equal(t, bench, got.Exercises[0].ExerciseID) // ordered by position
	assert.Equal(t, 3, got.Exercises[0].TargetSets)

	list, err := repo.ListForUser(ctx, user.ID)
	require.NoError(t, err)
	require.Len(t, list, 1)
	assert.Len(t, list[0].Exercises, 2)
}

func TestWorkoutTemplateRepository_UpdateReplacesExercises(t *testing.T) {
	pool := requireDB(t)
	user := makeUser(t, pool)
	repo := repository.NewWorkoutTemplateRepository(pool)
	ctx := context.Background()

	bench := anyExerciseID(t, pool, "Barbell Bench Press")
	row := anyExerciseID(t, pool, "Barbell Row")
	tmpl := makeTemplate(t, repo, user.ID, "Original "+uuid.NewString()[:6], bench)

	tmpl.Name = "Renamed"
	tmpl.Exercises = []*domain.TemplateExercise{
		{ID: uuid.New(), ExerciseID: row, Position: 0, TargetSets: 4, TargetReps: intPtr(6)},
	}
	require.NoError(t, repo.Update(ctx, tmpl))

	got, err := repo.FindByID(ctx, tmpl.ID)
	require.NoError(t, err)
	assert.Equal(t, "Renamed", got.Name)
	require.Len(t, got.Exercises, 1)
	assert.Equal(t, row, got.Exercises[0].ExerciseID)
	assert.Equal(t, 4, got.Exercises[0].TargetSets)
}

func TestWorkoutTemplateRepository_UpdateMissingReturnsNotFound(t *testing.T) {
	pool := requireDB(t)
	repo := repository.NewWorkoutTemplateRepository(pool)

	err := repo.Update(context.Background(), &domain.WorkoutTemplate{ID: uuid.New(), Name: "ghost"})
	assert.ErrorIs(t, err, domain.ErrTemplateNotFound)
}

func TestWorkoutTemplateRepository_DeleteCascadesExercises(t *testing.T) {
	pool := requireDB(t)
	user := makeUser(t, pool)
	repo := repository.NewWorkoutTemplateRepository(pool)
	ctx := context.Background()

	tmpl := makeTemplate(t, repo, user.ID, "Doomed "+uuid.NewString()[:6], anyExerciseID(t, pool, "Leg Press"))
	require.NoError(t, repo.Delete(ctx, tmpl.ID))

	_, err := repo.FindByID(ctx, tmpl.ID)
	assert.ErrorIs(t, err, domain.ErrTemplateNotFound)

	var n int
	require.NoError(t, pool.QueryRow(ctx,
		`SELECT count(*) FROM workout_template_exercises WHERE template_id=$1`, tmpl.ID).Scan(&n))
	assert.Equal(t, 0, n, "template_exercises should be gone via FK ON DELETE CASCADE")
}
