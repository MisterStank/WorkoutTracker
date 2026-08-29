package repository_test

import (
	"context"
	"sync"
	"testing"

	"workouttracker/internal/domain"
	"workouttracker/internal/repository"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func prValue(t *testing.T, pool *pgxpool.Pool, userID, exerciseID uuid.UUID, recordType string) (float64, bool) {
	t.Helper()
	var v float64
	err := pool.QueryRow(context.Background(),
		`SELECT value FROM personal_records WHERE user_id=$1 AND exercise_id=$2 AND record_type=$3`,
		userID, exerciseID, recordType).Scan(&v)
	return v, err == nil
}

func hasRecordType(records []*domain.PersonalRecord, rt string) bool {
	for _, r := range records {
		if r.RecordType == rt {
			return true
		}
	}
	return false
}

func TestLogSet_FirstWorkingSetCreatesRecordsAndRollup(t *testing.T) {
	pool := requireDB(t)
	user := makeUser(t, pool)
	workout := makeActiveWorkout(t, pool, user.ID)
	exID := anyExerciseID(t, pool, "Barbell Bench Press")
	repo := repository.NewWorkoutSetRepository(pool)
	ctx := context.Background()

	logged, err := repo.LogSet(ctx, user.ID, &domain.WorkoutSet{
		WorkoutID: workout.ID, ExerciseID: exID, Reps: 5, WeightKg: 100,
	})
	require.NoError(t, err)
	assert.Equal(t, 1, logged.Set.SetNumber)
	assert.NotEmpty(t, logged.NewRecords, "the very first set should set every applicable PR")

	mw, ok := prValue(t, pool, user.ID, exID, "max_weight")
	require.True(t, ok)
	assert.Equal(t, 100.0, mw)
	mv, _ := prValue(t, pool, user.ID, exID, "max_volume")
	assert.Equal(t, 500.0, mv)

	var totalVolume, rollupMaxWeight float64
	var setCount int
	require.NoError(t, pool.QueryRow(ctx,
		`SELECT total_volume, max_weight, set_count FROM progress_daily_rollup
		 WHERE user_id=$1 AND exercise_id=$2`, user.ID, exID).Scan(&totalVolume, &rollupMaxWeight, &setCount))
	assert.Equal(t, 500.0, totalVolume)
	assert.Equal(t, 100.0, rollupMaxWeight)
	assert.Equal(t, 1, setCount)
}

func TestLogSet_HeavierSetRaisesPR_LighterDoesNot(t *testing.T) {
	pool := requireDB(t)
	user := makeUser(t, pool)
	workout := makeActiveWorkout(t, pool, user.ID)
	exID := anyExerciseID(t, pool, "Barbell Back Squat")
	repo := repository.NewWorkoutSetRepository(pool)
	ctx := context.Background()

	_, err := repo.LogSet(ctx, user.ID, &domain.WorkoutSet{WorkoutID: workout.ID, ExerciseID: exID, Reps: 5, WeightKg: 100})
	require.NoError(t, err)

	heavier, err := repo.LogSet(ctx, user.ID, &domain.WorkoutSet{WorkoutID: workout.ID, ExerciseID: exID, Reps: 3, WeightKg: 120})
	require.NoError(t, err)
	assert.True(t, hasRecordType(heavier.NewRecords, "max_weight"))
	mw, _ := prValue(t, pool, user.ID, exID, "max_weight")
	assert.Equal(t, 120.0, mw)

	lighter, err := repo.LogSet(ctx, user.ID, &domain.WorkoutSet{WorkoutID: workout.ID, ExerciseID: exID, Reps: 8, WeightKg: 80})
	require.NoError(t, err)
	assert.False(t, hasRecordType(lighter.NewRecords, "max_weight"))
	mw, _ = prValue(t, pool, user.ID, exID, "max_weight")
	assert.Equal(t, 120.0, mw, "a lighter set must never lower an existing PR")

	var setCount int
	var totalVolume float64
	require.NoError(t, pool.QueryRow(ctx,
		`SELECT set_count, total_volume FROM progress_daily_rollup WHERE user_id=$1 AND exercise_id=$2`,
		user.ID, exID).Scan(&setCount, &totalVolume))
	assert.Equal(t, 3, setCount)
	assert.InDelta(t, 100*5+120*3+80*8, totalVolume, 0.001)
}

func TestLogSet_WarmupExcludedFromRecordsAndRollup(t *testing.T) {
	pool := requireDB(t)
	user := makeUser(t, pool)
	workout := makeActiveWorkout(t, pool, user.ID)
	exID := anyExerciseID(t, pool, "Conventional Deadlift")
	repo := repository.NewWorkoutSetRepository(pool)
	ctx := context.Background()

	logged, err := repo.LogSet(ctx, user.ID, &domain.WorkoutSet{
		WorkoutID: workout.ID, ExerciseID: exID, Reps: 10, WeightKg: 60, SetType: domain.SetTypeWarmup,
	})
	require.NoError(t, err)
	assert.Empty(t, logged.NewRecords)

	_, ok := prValue(t, pool, user.ID, exID, "max_weight")
	assert.False(t, ok, "a warm-up set must not create a PR")

	var n int
	require.NoError(t, pool.QueryRow(ctx,
		`SELECT count(*) FROM progress_daily_rollup WHERE user_id=$1 AND exercise_id=$2`,
		user.ID, exID).Scan(&n))
	assert.Equal(t, 0, n, "a warm-up set must not create a rollup row")
}

// TestLogSet_ConcurrentSetsSerializeOnPR fires several sets at once; exactly
// the heaviest weight must end up as the PR, and every set must be counted.
func TestLogSet_ConcurrentSetsSerializeOnPR(t *testing.T) {
	pool := requireDB(t)
	user := makeUser(t, pool)
	workout := makeActiveWorkout(t, pool, user.ID)
	exID := anyExerciseID(t, pool, "Overhead Press")
	repo := repository.NewWorkoutSetRepository(pool)

	weights := []float64{60, 70, 80, 90, 100, 110}
	var wg sync.WaitGroup
	for _, w := range weights {
		wg.Add(1)
		go func(weight float64) {
			defer wg.Done()
			_, err := repo.LogSet(context.Background(), user.ID, &domain.WorkoutSet{
				WorkoutID: workout.ID, ExerciseID: exID, Reps: 3, WeightKg: weight,
			})
			assert.NoError(t, err)
		}(w)
	}
	wg.Wait()

	mw, _ := prValue(t, pool, user.ID, exID, "max_weight")
	assert.Equal(t, 110.0, mw)

	var setCount int
	require.NoError(t, pool.QueryRow(context.Background(),
		`SELECT set_count FROM progress_daily_rollup WHERE user_id=$1 AND exercise_id=$2`,
		user.ID, exID).Scan(&setCount))
	assert.Equal(t, len(weights), setCount, "every concurrent set must be counted exactly once")
}
