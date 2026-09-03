package repository

import (
	"context"
	"errors"
	"time"

	"gymon/internal/domain"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type WorkoutSetRepository struct {
	db *pgxpool.Pool
}

func NewWorkoutSetRepository(db *pgxpool.Pool) *WorkoutSetRepository {
	return &WorkoutSetRepository{db: db}
}

func (r *WorkoutSetRepository) ListForWorkout(ctx context.Context, workoutID uuid.UUID) ([]*domain.WorkoutSet, error) {
	rows, err := r.db.Query(ctx,
		`SELECT id, workout_id, exercise_id, set_number, reps, weight_kg, rpe, set_type, superset_id, performed_at
		 FROM workout_sets WHERE workout_id = $1 ORDER BY set_number`, workoutID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var sets []*domain.WorkoutSet
	for rows.Next() {
		var s domain.WorkoutSet
		if err := rows.Scan(&s.ID, &s.WorkoutID, &s.ExerciseID, &s.SetNumber, &s.Reps, &s.WeightKg, &s.RPE, &s.SetType, &s.SupersetID, &s.PerformedAt); err != nil {
			return nil, err
		}
		sets = append(sets, &s)
	}
	return sets, rows.Err()
}

func (r *WorkoutSetRepository) LastForExercise(ctx context.Context, userID, exerciseID uuid.UUID) (*domain.WorkoutSet, error) {
	var s domain.WorkoutSet
	err := r.db.QueryRow(ctx,
		`SELECT ws.id, ws.workout_id, ws.exercise_id, ws.set_number, ws.reps, ws.weight_kg, ws.rpe, ws.set_type, ws.superset_id, ws.performed_at
		 FROM workout_sets ws
		 JOIN workouts w ON w.id = ws.workout_id
		 WHERE w.user_id = $1 AND ws.exercise_id = $2
		 ORDER BY ws.performed_at DESC
		 LIMIT 1`,
		userID, exerciseID,
	).Scan(&s.ID, &s.WorkoutID, &s.ExerciseID, &s.SetNumber, &s.Reps, &s.WeightKg, &s.RPE, &s.SetType, &s.SupersetID, &s.PerformedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrWorkoutSetNotFound
	}
	if err != nil {
		return nil, err
	}
	return &s, nil
}

func (r *WorkoutSetRepository) FindByID(ctx context.Context, id uuid.UUID) (*domain.WorkoutSet, error) {
	var s domain.WorkoutSet
	err := r.db.QueryRow(ctx,
		`SELECT id, workout_id, exercise_id, set_number, reps, weight_kg, rpe, set_type, superset_id, performed_at
		 FROM workout_sets WHERE id = $1`,
		id,
	).Scan(&s.ID, &s.WorkoutID, &s.ExerciseID, &s.SetNumber, &s.Reps, &s.WeightKg, &s.RPE, &s.SetType, &s.SupersetID, &s.PerformedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrWorkoutSetNotFound
	}
	if err != nil {
		return nil, err
	}
	return &s, nil
}

func (r *WorkoutSetRepository) Update(ctx context.Context, set *domain.WorkoutSet) error {
	_, err := r.db.Exec(ctx,
		`UPDATE workout_sets SET reps = $2, weight_kg = $3, rpe = $4, set_type = $5 WHERE id = $1`,
		set.ID, set.Reps, set.WeightKg, set.RPE, set.SetType,
	)
	return err
}

func (r *WorkoutSetRepository) Delete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, `DELETE FROM workout_sets WHERE id = $1`, id)
	return err
}

// LogSet inserts a set and, unless it's a warm-up, atomically upserts any
// personal records it breaks (heaviest weight, best single-set volume,
// estimated 1RM) in the same transaction, so two concurrent set inserts
// can't both "win" the same PR — the row lock taken by the first
// INSERT ... ON CONFLICT serializes the second.
func (r *WorkoutSetRepository) LogSet(ctx context.Context, userID uuid.UUID, set *domain.WorkoutSet) (*domain.LoggedSet, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var setNumber int
	if err := tx.QueryRow(ctx,
		`SELECT COALESCE(MAX(set_number), 0) + 1 FROM workout_sets WHERE workout_id = $1`,
		set.WorkoutID,
	).Scan(&setNumber); err != nil {
		return nil, err
	}

	set.ID = uuid.New()
	set.SetNumber = setNumber
	set.PerformedAt = time.Now()
	if set.SetType == "" {
		set.SetType = domain.SetTypeNormal
	}

	if _, err := tx.Exec(ctx,
		`INSERT INTO workout_sets (id, workout_id, exercise_id, set_number, reps, weight_kg, rpe, set_type, superset_id, performed_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
		set.ID, set.WorkoutID, set.ExerciseID, set.SetNumber, set.Reps, set.WeightKg, set.RPE, set.SetType, set.SupersetID, set.PerformedAt,
	); err != nil {
		return nil, err
	}

	if set.SetType == domain.SetTypeWarmup {
		// Warm-up sets don't count toward PRs or training-volume rollups —
		// they'd otherwise pollute progress charts with unrepresentative light
		// sets. Drop sets and failure sets are real working effort and do count.
		if err := tx.Commit(ctx); err != nil {
			return nil, err
		}
		return &domain.LoggedSet{Set: set}, nil
	}

	// Ordered, not a map: two concurrent LogSet calls for the same
	// (user, exercise) each take a row lock per personal_records row via the
	// upsert below. If they acquired those locks in different orders (Go
	// randomizes map iteration) Postgres would detect a deadlock and abort
	// one of them. A fixed order means every transaction locks the PR rows
	// in the same sequence, so the second simply waits for the first.
	candidates := []struct {
		recordType string
		value      float64
	}{
		{domain.RecordTypeMaxWeight, set.WeightKg},
		{domain.RecordTypeMaxVolume, set.WeightKg * float64(set.Reps)},
		{domain.RecordTypeEstimated1RM, estimated1RM(set.WeightKg, set.Reps)},
		{domain.RecordTypeMaxReps, float64(set.Reps)},
	}

	var newRecords []*domain.PersonalRecord
	for _, c := range candidates {
		recordType, value := c.recordType, c.value
		// Weight-based records are meaningless for a bodyweight set logged
		// at 0 (or assisted, negative) added load — only the rep count is.
		if value <= 0 {
			continue
		}
		var returnedID uuid.UUID
		err := tx.QueryRow(ctx,
			`INSERT INTO personal_records (id, user_id, exercise_id, record_type, value, achieved_at, workout_set_id)
			 VALUES ($1, $2, $3, $4, $5, $6, $7)
			 ON CONFLICT (user_id, exercise_id, record_type) DO UPDATE
			   SET value = EXCLUDED.value, achieved_at = EXCLUDED.achieved_at, workout_set_id = EXCLUDED.workout_set_id
			   WHERE personal_records.value < EXCLUDED.value
			 RETURNING id`,
			uuid.New(), userID, set.ExerciseID, recordType, value, set.PerformedAt, set.ID,
		).Scan(&returnedID)
		if errors.Is(err, pgx.ErrNoRows) {
			continue // existing record still stands, not a new PR
		}
		if err != nil {
			return nil, err
		}
		newRecords = append(newRecords, &domain.PersonalRecord{
			ID:           returnedID,
			UserID:       userID,
			ExerciseID:   set.ExerciseID,
			RecordType:   recordType,
			Value:        value,
			AchievedAt:   set.PerformedAt,
			WorkoutSetID: set.ID,
		})
	}

	volume := set.WeightKg * float64(set.Reps)
	if _, err := tx.Exec(ctx,
		`INSERT INTO progress_daily_rollup (user_id, exercise_id, day, total_volume, max_weight, set_count)
		 VALUES ($1, $2, date_trunc('day', $3::timestamptz), $4, $5, 1)
		 ON CONFLICT (user_id, exercise_id, day) DO UPDATE
		   SET total_volume = progress_daily_rollup.total_volume + EXCLUDED.total_volume,
		       max_weight = GREATEST(progress_daily_rollup.max_weight, EXCLUDED.max_weight),
		       set_count = progress_daily_rollup.set_count + 1`,
		userID, set.ExerciseID, set.PerformedAt, volume, set.WeightKg,
	); err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return &domain.LoggedSet{Set: set, NewRecords: newRecords}, nil
}

// estimated1RM uses the Epley formula — the industry-standard estimate for
// a true one-rep max from a set done at any rep range. Reps of 1 return the
// weight itself, matching the formula's own behavior at reps=1.
func estimated1RM(weightKg float64, reps int) float64 {
	return weightKg * (1 + float64(reps)/30.0)
}
