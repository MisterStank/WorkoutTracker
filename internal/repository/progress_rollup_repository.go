package repository

import (
	"context"
	"time"

	"gymon/internal/domain"

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
		`SELECT r.day, r.total_volume, r.max_weight,
		        COALESCE((SELECT MAX(ws.reps) FROM workout_sets ws
		                  JOIN workouts w ON w.id = ws.workout_id
		                  WHERE w.user_id = r.user_id AND ws.exercise_id = r.exercise_id
		                    AND ws.set_type != 'warmup'
		                    AND date_trunc('day', ws.performed_at) = r.day), 0) AS max_reps,
		        r.set_count
		 FROM progress_daily_rollup r
		 WHERE r.user_id = $1 AND r.exercise_id = $2 AND r.day >= $3
		 ORDER BY r.day`,
		userID, exerciseID, since,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanProgressPoints(rows)
}

// RecomputeDay rebuilds the rollup row for one user+exercise+day from the
// current workout_sets, or removes it if no non-warmup sets remain that
// day — called after a set is edited or deleted, since LogSet's
// incremental "add to the running total" upsert can't be run in reverse.
func (r *ProgressRollupRepository) RecomputeDay(ctx context.Context, userID, exerciseID uuid.UUID, day time.Time) error {
	var totalVolume, maxWeight float64
	var setCount int
	err := r.db.QueryRow(ctx,
		`SELECT COALESCE(SUM(weight_kg * reps), 0), COALESCE(MAX(weight_kg), 0), COUNT(*)
		 FROM workout_sets ws
		 JOIN workouts w ON w.id = ws.workout_id
		 WHERE w.user_id = $1 AND ws.exercise_id = $2 AND ws.set_type != 'warmup'
		   AND date_trunc('day', ws.performed_at) = date_trunc('day', $3::timestamptz)`,
		userID, exerciseID, day,
	).Scan(&totalVolume, &maxWeight, &setCount)
	if err != nil {
		return err
	}

	if setCount == 0 {
		_, err := r.db.Exec(ctx,
			`DELETE FROM progress_daily_rollup WHERE user_id = $1 AND exercise_id = $2 AND day = date_trunc('day', $3::timestamptz)`,
			userID, exerciseID, day,
		)
		return err
	}

	_, err = r.db.Exec(ctx,
		`INSERT INTO progress_daily_rollup (user_id, exercise_id, day, total_volume, max_weight, set_count)
		 VALUES ($1, $2, date_trunc('day', $3::timestamptz), $4, $5, $6)
		 ON CONFLICT (user_id, exercise_id, day) DO UPDATE
		   SET total_volume = EXCLUDED.total_volume, max_weight = EXCLUDED.max_weight, set_count = EXCLUDED.set_count`,
		userID, exerciseID, day, totalVolume, maxWeight, setCount,
	)
	return err
}

func (r *ProgressRollupRepository) RangeForUser(ctx context.Context, userID uuid.UUID, since time.Time) ([]*domain.ProgressPoint, error) {
	rows, err := r.db.Query(ctx,
		`SELECT day, SUM(total_volume), MAX(max_weight), 0, SUM(set_count)
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
		if err := rows.Scan(&p.Day, &p.TotalVolume, &p.MaxWeight, &p.MaxReps, &p.SetCount); err != nil {
			return nil, err
		}
		points = append(points, &p)
	}
	return points, rows.Err()
}
