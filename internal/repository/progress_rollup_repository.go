package repository

import (
	"context"
	"time"

	"workouttracker/internal/domain"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

type ProgressRollupRepository struct {
	db *pgxpool.Pool
}

func NewProgressRollupRepository(db *pgxpool.Pool) *ProgressRollupRepository {
	return &ProgressRollupRepository{db: db}
}

func (r *ProgressRollupRepository) RangeForExercise(ctx context.Context, userID, exerciseID uuid.UUID, since time.Time) ([]*domain.ProgressPoint, error) {
	rows, err := r.db.Query(ctx,
		`SELECT day, total_volume, max_weight, set_count
		 FROM progress_daily_rollup
		 WHERE user_id = $1 AND exercise_id = $2 AND day >= $3
		 ORDER BY day`,
		userID, exerciseID, since,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanProgressPoints(rows)
}

func (r *ProgressRollupRepository) RangeForUser(ctx context.Context, userID uuid.UUID, since time.Time) ([]*domain.ProgressPoint, error) {
	rows, err := r.db.Query(ctx,
		`SELECT day, SUM(total_volume), MAX(max_weight), SUM(set_count)
		 FROM progress_daily_rollup
		 WHERE user_id = $1 AND day >= $2
		 GROUP BY day
		 ORDER BY day`,
		userID, since,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanProgressPoints(rows)
}

func scanProgressPoints(rows interface {
	Next() bool
	Scan(dest ...any) error
	Err() error
}) ([]*domain.ProgressPoint, error) {
	var points []*domain.ProgressPoint
	for rows.Next() {
		var p domain.ProgressPoint
		var setCount int
		if err := rows.Scan(&p.Day, &p.TotalVolume, &p.MaxWeight, &setCount); err != nil {
			return nil, err
		}
		p.SetCount = setCount
		points = append(points, &p)
	}
	return points, rows.Err()
}
