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

type PersonalRecordRepository struct {
	db *pgxpool.Pool
}

func NewPersonalRecordRepository(db *pgxpool.Pool) *PersonalRecordRepository {
	return &PersonalRecordRepository{db: db}
}

// recomputeOrderBy is the SQL expression ranking sets for each record type
// — kept in one place so it can't drift from LogSet's candidate values.
var recomputeOrderBy = map[string]string{
	domain.RecordTypeMaxWeight:    "weight_kg",
	domain.RecordTypeMaxVolume:    "weight_kg * reps",
	domain.RecordTypeEstimated1RM: "weight_kg * (1 + reps / 30.0)",
}

// Recompute rebuilds every record type for one user+exercise from the
// current workout_sets, rather than trusting LogSet's incremental "beat the
// existing value" upsert — the only correct way to recover the right
// personal best after the record-setting set itself was edited or deleted.
func (r *PersonalRecordRepository) Recompute(ctx context.Context, userID, exerciseID uuid.UUID) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(ctx,
		`DELETE FROM personal_records WHERE user_id = $1 AND exercise_id = $2`,
		userID, exerciseID,
	); err != nil {
		return err
	}

	for recordType, orderBy := range recomputeOrderBy {
		var setID uuid.UUID
		var value float64
		var achievedAt time.Time
		err := tx.QueryRow(ctx,
			`SELECT ws.id, `+orderBy+`, ws.performed_at
			 FROM workout_sets ws
			 JOIN workouts w ON w.id = ws.workout_id
			 WHERE w.user_id = $1 AND ws.exercise_id = $2 AND ws.set_type != 'warmup'
			 ORDER BY `+orderBy+` DESC
			 LIMIT 1`,
			userID, exerciseID,
		).Scan(&setID, &value, &achievedAt)
		if errors.Is(err, pgx.ErrNoRows) {
			continue // no working sets left for this exercise — nothing to hold this record
		}
		if err != nil {
			return err
		}
		if _, err := tx.Exec(ctx,
			`INSERT INTO personal_records (id, user_id, exercise_id, record_type, value, achieved_at, workout_set_id)
			 VALUES ($1, $2, $3, $4, $5, $6, $7)`,
			uuid.New(), userID, exerciseID, recordType, value, achievedAt, setID,
		); err != nil {
			return err
		}
	}

	return tx.Commit(ctx)
}

func (r *PersonalRecordRepository) ListForUser(ctx context.Context, userID uuid.UUID) ([]*domain.PersonalRecord, error) {
	rows, err := r.db.Query(ctx,
		`SELECT id, user_id, exercise_id, record_type, value, achieved_at, workout_set_id
		 FROM personal_records WHERE user_id = $1 ORDER BY achieved_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var records []*domain.PersonalRecord
	for rows.Next() {
		var pr domain.PersonalRecord
		if err := rows.Scan(&pr.ID, &pr.UserID, &pr.ExerciseID, &pr.RecordType, &pr.Value, &pr.AchievedAt, &pr.WorkoutSetID); err != nil {
			return nil, err
		}
		records = append(records, &pr)
	}
	return records, rows.Err()
}
