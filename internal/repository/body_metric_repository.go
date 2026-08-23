package repository

import (
	"context"
	"time"

	"workouttracker/internal/domain"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

type BodyMetricRepository struct {
	db *pgxpool.Pool
}

func NewBodyMetricRepository(db *pgxpool.Pool) *BodyMetricRepository {
	return &BodyMetricRepository{db: db}
}

func (r *BodyMetricRepository) Create(ctx context.Context, m *domain.BodyMetric) error {
	_, err := r.db.Exec(ctx,
		`INSERT INTO body_metrics (id, user_id, metric_type, value, recorded_at)
		 VALUES ($1, $2, $3, $4, $5)`,
		m.ID, m.UserID, m.MetricType, m.Value, m.RecordedAt,
	)
	return err
}

func (r *BodyMetricRepository) ListForUser(ctx context.Context, userID uuid.UUID, metricType string, since time.Time) ([]*domain.BodyMetric, error) {
	rows, err := r.db.Query(ctx,
		`SELECT id, user_id, metric_type, value, recorded_at
		 FROM body_metrics
		 WHERE user_id = $1 AND metric_type = $2 AND recorded_at >= $3
		 ORDER BY recorded_at`,
		userID, metricType, since,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var metrics []*domain.BodyMetric
	for rows.Next() {
		var m domain.BodyMetric
		if err := rows.Scan(&m.ID, &m.UserID, &m.MetricType, &m.Value, &m.RecordedAt); err != nil {
			return nil, err
		}
		metrics = append(metrics, &m)
	}
	return metrics, rows.Err()
}
