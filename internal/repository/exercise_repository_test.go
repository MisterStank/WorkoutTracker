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

func TestExerciseRepository_ListReturnsBuiltInsAndSearches(t *testing.T) {
	pool := requireDB(t)
	user := makeUser(t, pool)
	repo := repository.NewExerciseRepository(pool)
	ctx := context.Background()

	all, err := repo.List(ctx, user.ID, "")
	require.NoError(t, err)
	assert.NotEmpty(t, all, "the seeded catalog should be visible to every user")

	hits, err := repo.List(ctx, user.ID, "bench")
	require.NoError(t, err)
	require.NotEmpty(t, hits)
	for _, e := range hits {
		assert.Contains(t, e.Name, "Bench")
	}
}

func TestExerciseRepository_CustomExerciseIsPrivateToOwner(t *testing.T) {
	pool := requireDB(t)
	owner := makeUser(t, pool)
	stranger := makeUser(t, pool)
	repo := repository.NewExerciseRepository(pool)
	ctx := context.Background()

	custom := &domain.Exercise{
		ID:           uuid.New(),
		Name:         "My Weird Cable Thing " + uuid.NewString()[:8],
		Category:     "pull",
		MuscleGroups: []string{"back"},
		Equipment:    "cable",
		CreatedBy:    &owner.ID,
		CreatedAt:    time.Now(),
	}
	require.NoError(t, repo.Create(ctx, custom))

	ownerList, err := repo.List(ctx, owner.ID, "Weird Cable")
	require.NoError(t, err)
	assert.Len(t, ownerList, 1, "the owner sees their custom exercise")

	strangerList, err := repo.List(ctx, stranger.ID, "Weird Cable")
	require.NoError(t, err)
	assert.Empty(t, strangerList, "another user must not see someone else's custom exercise")
}

func TestExerciseRepository_DuplicateCustomNameRejected(t *testing.T) {
	pool := requireDB(t)
	owner := makeUser(t, pool)
	repo := repository.NewExerciseRepository(pool)
	ctx := context.Background()

	name := "Dup Custom " + uuid.NewString()[:8]
	mk := func() error {
		return repo.Create(ctx, &domain.Exercise{
			ID: uuid.New(), Name: name, Category: "core", MuscleGroups: []string{"abs"},
			Equipment: "bodyweight", CreatedBy: &owner.ID, CreatedAt: time.Now(),
		})
	}
	require.NoError(t, mk())
	assert.ErrorIs(t, mk(), domain.ErrExerciseNameTaken)
}

func TestExerciseRepository_CountReferences(t *testing.T) {
	pool := requireDB(t)
	user := makeUser(t, pool)
	workout := makeActiveWorkout(t, pool, user.ID)
	exID := anyExerciseID(t, pool, "Leg Press")
	exRepo := repository.NewExerciseRepository(pool)
	setRepo := repository.NewWorkoutSetRepository(pool)
	ctx := context.Background()

	n, err := exRepo.CountReferences(ctx, exID)
	require.NoError(t, err)
	before := n

	_, err = setRepo.LogSet(ctx, user.ID, &domain.WorkoutSet{WorkoutID: workout.ID, ExerciseID: exID, Reps: 10, WeightKg: 80})
	require.NoError(t, err)

	n, err = exRepo.CountReferences(ctx, exID)
	require.NoError(t, err)
	assert.Equal(t, before+1, n)
}
