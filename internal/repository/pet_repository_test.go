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

func TestPetRepository_CreateFindUpdate(t *testing.T) {
	pool := requireDB(t)
	ctx := context.Background()
	user := makeUser(t, pool)
	repo := repository.NewPetRepository(pool)

	_, err := repo.FindByUser(ctx, user.ID)
	assert.ErrorIs(t, err, domain.ErrPetNotFound)

	now := time.Now()
	pet := &domain.Pet{
		ID: uuid.New(), UserID: user.ID, Name: "Rex", Species: "sprout", Color: "green",
		Stage: domain.PetStageEgg, StageUpdatedAt: now, CreatedAt: now,
	}
	require.NoError(t, repo.Create(ctx, pet))

	got, err := repo.FindByUser(ctx, user.ID)
	require.NoError(t, err)
	assert.Equal(t, "Rex", got.Name)
	assert.Equal(t, domain.PetStageEgg, got.Stage)
	assert.Nil(t, got.HatchedAt)

	hatched := now
	got.Stage = domain.PetStageJuvenile
	got.LongestStreak = 9
	got.HatchedAt = &hatched
	got.Name = "Maximus"
	require.NoError(t, repo.Update(ctx, got))

	got2, err := repo.FindByUser(ctx, user.ID)
	require.NoError(t, err)
	assert.Equal(t, domain.PetStageJuvenile, got2.Stage)
	assert.Equal(t, 9, got2.LongestStreak)
	assert.Equal(t, "Maximus", got2.Name)
	require.NotNil(t, got2.HatchedAt)
}

func TestAccessoryRepository_UnlockAndEquipOnePerSlot(t *testing.T) {
	pool := requireDB(t)
	ctx := context.Background()
	user := makeUser(t, pool)
	pets := repository.NewPetRepository(pool)
	acc := repository.NewAccessoryRepository(pool)

	now := time.Now()
	pet := &domain.Pet{ID: uuid.New(), UserID: user.ID, Name: "Rex", Species: "ember", Color: "red", StageUpdatedAt: now, CreatedAt: now}
	require.NoError(t, pets.Create(ctx, pet))

	catalog, err := acc.ListCatalog(ctx)
	require.NoError(t, err)
	require.NotEmpty(t, catalog)

	// two accessories that share a slot
	var a, b *domain.Accessory
	for _, c := range catalog {
		if c.Slot != "head" {
			continue
		}
		if a == nil {
			a = c
		} else {
			b = c
			break
		}
	}
	require.NotNil(t, a)
	require.NotNil(t, b)

	require.NoError(t, acc.Unlock(ctx, pet.ID, a.ID, a.Slot, now))
	require.NoError(t, acc.Unlock(ctx, pet.ID, a.ID, a.Slot, now)) // idempotent
	require.NoError(t, acc.Unlock(ctx, pet.ID, b.ID, b.Slot, now))

	owned, err := acc.ListOwned(ctx, pet.ID)
	require.NoError(t, err)
	assert.Len(t, owned, 2)

	require.NoError(t, acc.SetEquipped(ctx, pet.ID, a.ID, true))
	require.NoError(t, acc.SetEquipped(ctx, pet.ID, b.ID, true)) // must unequip a

	owned, err = acc.ListOwned(ctx, pet.ID)
	require.NoError(t, err)
	equipped := 0
	for _, o := range owned {
		if o.Equipped {
			equipped++
			assert.Equal(t, b.ID, o.Accessory.ID)
		}
	}
	assert.Equal(t, 1, equipped)
}

func TestPetStatsRepository_GatherStats(t *testing.T) {
	pool := requireDB(t)
	ctx := context.Background()
	user := makeUser(t, pool)
	stats := repository.NewPetStatsRepository(pool)

	// no history yet
	snap, err := stats.GatherStats(ctx, user.ID)
	require.NoError(t, err)
	assert.Empty(t, snap.FinishedWorkoutEndTimes)
	assert.Equal(t, 0, snap.DistinctExercisesLogged)

	// one finished workout with a working set
	ex := anyExerciseID(t, pool, "Barbell Bench Press")
	wid := uuid.New()
	end := time.Now().Add(-time.Hour)
	_, err = pool.Exec(ctx,
		`INSERT INTO workouts (id, user_id, started_at, ended_at, status) VALUES ($1,$2,$3,$4,'completed')`,
		wid, user.ID, end.Add(-time.Hour), end)
	require.NoError(t, err)
	_, err = pool.Exec(ctx,
		`INSERT INTO workout_sets (id, workout_id, exercise_id, set_number, reps, weight_kg, set_type, performed_at)
		 VALUES ($1,$2,$3,1,5,100,'normal',$4)`,
		uuid.New(), wid, ex, end)
	require.NoError(t, err)

	snap, err = stats.GatherStats(ctx, user.ID)
	require.NoError(t, err)
	assert.Len(t, snap.FinishedWorkoutEndTimes, 1)
	assert.Equal(t, 1, snap.DistinctExercisesLogged)
	assert.GreaterOrEqual(t, snap.DistinctMuscleGroups, 1)
}
