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

func TestWorkoutRepository_CreateFindActiveFinish(t *testing.T) {
	pool := requireDB(t)
	user := makeUser(t, pool)
	repo := repository.NewWorkoutRepository(pool)
	ctx := context.Background()

	w := &domain.Workout{ID: uuid.New(), UserID: user.ID, StartedAt: time.Now(), Status: domain.WorkoutInProgress}
	require.NoError(t, repo.Create(ctx, w))

	active, err := repo.FindActiveForUser(ctx, user.ID)
	require.NoError(t, err)
	assert.Equal(t, w.ID, active.ID)

	require.NoError(t, repo.Finish(ctx, w.ID, time.Now(), "felt strong"))

	_, err = repo.FindActiveForUser(ctx, user.ID)
	assert.ErrorIs(t, err, domain.ErrWorkoutNotFound, "a finished workout is no longer active")

	got, err := repo.FindByID(ctx, w.ID)
	require.NoError(t, err)
	assert.Equal(t, domain.WorkoutCompleted, got.Status)
	assert.Equal(t, "felt strong", got.Notes)
	assert.NotNil(t, got.EndedAt)
}

func TestWorkoutRepository_OnlyOneActiveWorkoutPerUser(t *testing.T) {
	pool := requireDB(t)
	user := makeUser(t, pool)
	repo := repository.NewWorkoutRepository(pool)
	ctx := context.Background()

	require.NoError(t, repo.Create(ctx, &domain.Workout{
		ID: uuid.New(), UserID: user.ID, StartedAt: time.Now(), Status: domain.WorkoutInProgress,
	}))
	err := repo.Create(ctx, &domain.Workout{
		ID: uuid.New(), UserID: user.ID, StartedAt: time.Now(), Status: domain.WorkoutInProgress,
	})
	assert.Error(t, err, "the partial unique index must forbid a second in-progress workout")
}

func TestWorkoutRepository_ListForUserIsPaginatedAndScoped(t *testing.T) {
	pool := requireDB(t)
	user := makeUser(t, pool)
	stranger := makeUser(t, pool)
	repo := repository.NewWorkoutRepository(pool)
	ctx := context.Background()

	base := time.Now().Add(-100 * time.Hour)
	for i := 0; i < 5; i++ {
		w := &domain.Workout{ID: uuid.New(), UserID: user.ID, StartedAt: base.Add(time.Duration(i) * time.Hour), Status: domain.WorkoutCompleted}
		require.NoError(t, repo.Create(ctx, w))
		require.NoError(t, repo.Finish(ctx, w.ID, w.StartedAt.Add(time.Hour), ""))
	}
	// stranger's workout must never appear in the user's list
	sw := &domain.Workout{ID: uuid.New(), UserID: stranger.ID, StartedAt: time.Now(), Status: domain.WorkoutCompleted}
	require.NoError(t, repo.Create(ctx, sw))

	page1, err := repo.ListForUser(ctx, user.ID, 3, nil, nil)
	require.NoError(t, err)
	require.Len(t, page1, 3)
	// newest first
	assert.True(t, page1[0].StartedAt.After(page1[1].StartedAt))

	last := page1[len(page1)-1]
	page2, err := repo.ListForUser(ctx, user.ID, 3, &last.StartedAt, &last.ID)
	require.NoError(t, err)
	assert.Len(t, page2, 2, "keyset pagination returns the remaining rows")

	for _, w := range append(page1, page2...) {
		assert.Equal(t, user.ID, w.UserID)
	}
}
