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

func TestPersonalRecordRepository_RecomputeFromSets(t *testing.T) {
	pool := requireDB(t)
	user := makeUser(t, pool)
	workout := makeActiveWorkout(t, pool, user.ID)
	exID := anyExerciseID(t, pool, "Barbell Row")
	setRepo := repository.NewWorkoutSetRepository(pool)
	prRepo := repository.NewPersonalRecordRepository(pool)
	ctx := context.Background()

	for _, w := range []float64{60, 80, 100} {
		_, err := setRepo.LogSet(ctx, user.ID, &domain.WorkoutSet{WorkoutID: workout.ID, ExerciseID: exID, Reps: 5, WeightKg: w})
		require.NoError(t, err)
	}

	// Corrupt the PR table, then Recompute should restore the truth from sets.
	_, err := pool.Exec(ctx,
		`UPDATE personal_records SET value = 9999 WHERE user_id=$1 AND exercise_id=$2 AND record_type='max_weight'`,
		user.ID, exID)
	require.NoError(t, err)

	require.NoError(t, prRepo.Recompute(ctx, user.ID, exID))

	mw, ok := prValue(t, pool, user.ID, exID, "max_weight")
	require.True(t, ok)
	assert.Equal(t, 100.0, mw)

	records, err := prRepo.ListForUser(ctx, user.ID)
	require.NoError(t, err)
	assert.NotEmpty(t, records)
	for _, r := range records {
		assert.Equal(t, user.ID, r.UserID)
	}
}

func TestPersonalRecordRepository_RecomputeDropsRecordsWhenNoWorkingSets(t *testing.T) {
	pool := requireDB(t)
	user := makeUser(t, pool)
	workout := makeActiveWorkout(t, pool, user.ID)
	exID := anyExerciseID(t, pool, "Pull-Up")
	setRepo := repository.NewWorkoutSetRepository(pool)
	prRepo := repository.NewPersonalRecordRepository(pool)
	ctx := context.Background()

	_, err := setRepo.LogSet(ctx, user.ID, &domain.WorkoutSet{WorkoutID: workout.ID, ExerciseID: exID, Reps: 8, WeightKg: 0})
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `DELETE FROM workout_sets WHERE workout_id=$1`, workout.ID)
	require.NoError(t, err)

	require.NoError(t, prRepo.Recompute(ctx, user.ID, exID))
	_, ok := prValue(t, pool, user.ID, exID, "max_reps")
	assert.False(t, ok, "no working sets left -> no records")
}

func TestProgressRollupRepository_RangeAndRecomputeDay(t *testing.T) {
	pool := requireDB(t)
	user := makeUser(t, pool)
	workout := makeActiveWorkout(t, pool, user.ID)
	exID := anyExerciseID(t, pool, "Leg Press")
	setRepo := repository.NewWorkoutSetRepository(pool)
	rollup := repository.NewProgressRollupRepository(pool)
	ctx := context.Background()

	_, err := setRepo.LogSet(ctx, user.ID, &domain.WorkoutSet{WorkoutID: workout.ID, ExerciseID: exID, Reps: 10, WeightKg: 100})
	require.NoError(t, err)
	_, err = setRepo.LogSet(ctx, user.ID, &domain.WorkoutSet{WorkoutID: workout.ID, ExerciseID: exID, Reps: 10, WeightKg: 120})
	require.NoError(t, err)

	points, err := rollup.RangeForExercise(ctx, user.ID, exID, time.Now().Add(-24*time.Hour))
	require.NoError(t, err)
	require.Len(t, points, 1)
	assert.Equal(t, 120.0, points[0].MaxWeight)
	assert.Equal(t, 2, points[0].SetCount)
	assert.InDelta(t, 100*10+120*10, points[0].TotalVolume, 0.001)

	userPoints, err := rollup.RangeForUser(ctx, user.ID, time.Now().Add(-24*time.Hour))
	require.NoError(t, err)
	assert.Len(t, userPoints, 1)

	// delete one set, RecomputeDay should re-derive the row
	_, err = pool.Exec(ctx, `DELETE FROM workout_sets WHERE workout_id=$1 AND weight_kg=120`, workout.ID)
	require.NoError(t, err)
	require.NoError(t, rollup.RecomputeDay(ctx, user.ID, exID, time.Now()))

	points, err = rollup.RangeForExercise(ctx, user.ID, exID, time.Now().Add(-24*time.Hour))
	require.NoError(t, err)
	require.Len(t, points, 1)
	assert.Equal(t, 100.0, points[0].MaxWeight)
	assert.Equal(t, 1, points[0].SetCount)
}

func TestBodyMetricRepository_CreateAndList(t *testing.T) {
	pool := requireDB(t)
	user := makeUser(t, pool)
	other := makeUser(t, pool)
	repo := repository.NewBodyMetricRepository(pool)
	ctx := context.Background()

	now := time.Now()
	for i, v := range []float64{80.5, 80.2, 79.9} {
		require.NoError(t, repo.Create(ctx, &domain.BodyMetric{
			ID: uuid.New(), UserID: user.ID, MetricType: "bodyweight_kg", Value: v,
			RecordedAt: now.Add(time.Duration(-i) * 24 * time.Hour),
		}))
	}
	require.NoError(t, repo.Create(ctx, &domain.BodyMetric{
		ID: uuid.New(), UserID: user.ID, MetricType: "waist_cm", Value: 82, RecordedAt: now,
	}))
	require.NoError(t, repo.Create(ctx, &domain.BodyMetric{
		ID: uuid.New(), UserID: other.ID, MetricType: "bodyweight_kg", Value: 99, RecordedAt: now,
	}))

	got, err := repo.ListForUser(ctx, user.ID, "bodyweight_kg", now.Add(-10*24*time.Hour))
	require.NoError(t, err)
	assert.Len(t, got, 3, "only this user's bodyweight_kg entries, other metric types and users excluded")
	// ascending by recorded_at
	assert.True(t, got[0].RecordedAt.Before(got[2].RecordedAt))

	recent, err := repo.ListForUser(ctx, user.ID, "bodyweight_kg", now.Add(-1*time.Hour))
	require.NoError(t, err)
	assert.Len(t, recent, 1, "the `since` filter is applied")
}

func TestFitnessProfileRepository_UpsertAndGet(t *testing.T) {
	pool := requireDB(t)
	user := makeUser(t, pool)
	repo := repository.NewFitnessProfileRepository(pool)
	ctx := context.Background()

	_, err := repo.Get(ctx, user.ID)
	assert.ErrorIs(t, err, domain.ErrFitnessProfileNotFound)

	p := &domain.UserFitnessProfile{
		UserID: user.ID, Goal: domain.GoalStrength, ExperienceLevel: domain.ExperienceIntermediate,
		DaysPerWeek: 4, EquipmentAccess: []string{"barbell", "dumbbell"}, AvoidMuscleGroups: []string{"lower_back"},
		UpdatedAt: time.Now(),
	}
	require.NoError(t, repo.Upsert(ctx, p))

	got, err := repo.Get(ctx, user.ID)
	require.NoError(t, err)
	assert.Equal(t, 4, got.DaysPerWeek)
	assert.Equal(t, []string{"barbell", "dumbbell"}, got.EquipmentAccess)

	// upsert again -> updates in place, still one row
	p.DaysPerWeek = 3
	require.NoError(t, repo.Upsert(ctx, p))
	got, err = repo.Get(ctx, user.ID)
	require.NoError(t, err)
	assert.Equal(t, 3, got.DaysPerWeek)
}
