package repository

import (
	"context"

	"workouttracker/internal/domain"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

type PersonalRecordRepository struct {
	db *pgxpool.Pool
}

func NewPersonalRecordRepository(db *pgxpool.Pool) *PersonalRecordRepository {
	return &PersonalRecordRepository{db: db}
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
