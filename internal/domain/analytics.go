package domain

import (
	"context"
	"time"

	"github.com/google/uuid"
)

// ProgressPoint is one day's pre-aggregated rollup for a user+exercise —
// the read model behind progress/volume trend charts.
type ProgressPoint struct {
	Day         time.Time
	TotalVolume float64
	MaxWeight   float64
	SetCount    int
}

type BodyMetric struct {
	ID         uuid.UUID
	UserID     uuid.UUID
	MetricType string
	Value      float64
	RecordedAt time.Time
}

type ProgressRollupRepository interface {
	// RangeForExercise returns the daily rollup for one exercise, ordered by day.
	RangeForExercise(ctx context.Context, userID, exerciseID uuid.UUID, since time.Time) ([]*ProgressPoint, error)
	// RangeForUser returns the daily rollup across all exercises (summed per
	// day) — the read model behind an overall volume trend.
	RangeForUser(ctx context.Context, userID uuid.UUID, since time.Time) ([]*ProgressPoint, error)
	// RecomputeDay rebuilds the rollup row for one user+exercise+day from
	// the current workout_sets, or deletes it if no non-warmup sets remain
	// that day. Called after a set is edited or deleted, since the
	// incremental upsert LogSet does can't be un-done in place.
	RecomputeDay(ctx context.Context, userID, exerciseID uuid.UUID, day time.Time) error
}

type BodyMetricRepository interface {
	Create(ctx context.Context, m *BodyMetric) error
	ListForUser(ctx context.Context, userID uuid.UUID, metricType string, since time.Time) ([]*BodyMetric, error)
}

// WorkoutEventPublisher fans out a logged set to anyone subscribed to that
// workout, e.g. a GraphQL subscription backed by Redis pub/sub. Publishing
// is best-effort: a failure here must never fail the set-logging mutation
// itself, so WorkoutService treats it as fire-and-forget.
type WorkoutEventPublisher interface {
	PublishSetLogged(ctx context.Context, workoutID uuid.UUID, logged *LoggedSet) error
}
