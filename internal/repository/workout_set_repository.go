package repository

import (
	"context"
	"errors"
	"time"

	"workouttracker/internal/domain"

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
		`SELECT id, workout_id, exercise_id, set_number, reps, weight_kg, rpe, performed_at
		 FROM workout_sets WHERE workout_id = $1 ORDER BY set_number`, workoutID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var sets []*domain.WorkoutSet
	for rows.Next() {
		var s domain.WorkoutSet
		if err := rows.Scan(&s.ID, &s.WorkoutID, &s.ExerciseID, &s.SetNumber, &s.Reps, &s.WeightKg, &s.RPE, &s.PerformedAt); err != nil {
			return nil, err
		}
		sets = append(sets, &s)
	}
	return sets, rows.Err()
}

// LogSet inserts a set and atomically upserts any personal records it
// breaks (heaviest weight, best single-set volume) in the same transaction,
// so two concurrent set inserts can't both "win" the same PR — the row
// lock taken by the first INSERT ... ON CONFLICT serializes the second.
func (r *WorkoutSetRepository) LogSet(ctx context.Context, userID uuid.UUID, set *domain.WorkoutSet) (*domain.LoggedSet, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

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

	if _, err := tx.Exec(ctx,
		`INSERT INTO workout_sets (id, workout_id, exercise_id, set_number, reps, weight_kg, rpe, performed_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
		set.ID, set.WorkoutID, set.ExerciseID, set.SetNumber, set.Reps, set.WeightKg, set.RPE, set.PerformedAt,
	); err != nil {
		return nil, err
	}

	candidates := map[string]float64{
		domain.RecordTypeMaxWeight: set.WeightKg,
		domain.RecordTypeMaxVolume: set.WeightKg * float64(set.Reps),
	}

	var newRecords []*domain.PersonalRecord
	for recordType, value := range candidates {
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

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return &domain.LoggedSet{Set: set, NewRecords: newRecords}, nil
}
