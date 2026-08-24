package service_test

import (
	"context"
	"encoding/json"
	"sync"
	"testing"
	"time"

	"workouttracker/internal/domain"
	"workouttracker/internal/service"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// fakeProgressRollupRepo counts calls so tests can assert the cache avoided
// a redundant "database" hit. fakeAnalyticsCache is a tiny in-memory
// implementation of service.AnalyticsCache (JSON round-tripped, like the
// real Redis cache, so a bug in either side's (de)serialization would show
// up here too).

type fakeProgressRollupRepo struct {
	mu             sync.Mutex
	exerciseCalls  int
	userCalls      int
	exercisePoints []*domain.ProgressPoint
	userPoints     []*domain.ProgressPoint
}

func (f *fakeProgressRollupRepo) RangeForExercise(ctx context.Context, userID, exerciseID uuid.UUID, since time.Time) ([]*domain.ProgressPoint, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.exerciseCalls++
	return f.exercisePoints, nil
}

func (f *fakeProgressRollupRepo) RangeForUser(ctx context.Context, userID uuid.UUID, since time.Time) ([]*domain.ProgressPoint, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.userCalls++
	return f.userPoints, nil
}

func (f *fakeProgressRollupRepo) RecomputeDay(ctx context.Context, userID, exerciseID uuid.UUID, day time.Time) error {
	return nil
}

type fakeBodyMetricRepo struct {
	mu      sync.Mutex
	metrics []*domain.BodyMetric
}

func (f *fakeBodyMetricRepo) Create(ctx context.Context, m *domain.BodyMetric) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.metrics = append(f.metrics, m)
	return nil
}

func (f *fakeBodyMetricRepo) ListForUser(ctx context.Context, userID uuid.UUID, metricType string, since time.Time) ([]*domain.BodyMetric, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []*domain.BodyMetric
	for _, m := range f.metrics {
		if m.UserID == userID && m.MetricType == metricType {
			out = append(out, m)
		}
	}
	return out, nil
}

type fakeAnalyticsCache struct {
	mu    sync.Mutex
	store map[string][]byte
}

func newFakeAnalyticsCache() *fakeAnalyticsCache {
	return &fakeAnalyticsCache{store: map[string][]byte{}}
}

func (c *fakeAnalyticsCache) Get(ctx context.Context, key string, dest any) (bool, error) {
	c.mu.Lock()
	raw, ok := c.store[key]
	c.mu.Unlock()
	if !ok {
		return false, nil
	}
	return true, json.Unmarshal(raw, dest)
}

func (c *fakeAnalyticsCache) Set(ctx context.Context, key string, value any, ttl time.Duration) error {
	raw, err := json.Marshal(value)
	if err != nil {
		return err
	}
	c.mu.Lock()
	c.store[key] = raw
	c.mu.Unlock()
	return nil
}

func (c *fakeAnalyticsCache) Delete(ctx context.Context, keys ...string) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	for _, k := range keys {
		delete(c.store, k)
	}
	return nil
}

func TestProgressOverTimeIsCached(t *testing.T) {
	ctx := context.Background()
	rollup := &fakeProgressRollupRepo{exercisePoints: []*domain.ProgressPoint{
		{Day: time.Now(), TotalVolume: 500, MaxWeight: 100, SetCount: 3},
	}}
	analytics := service.NewAnalyticsService(rollup, &fakeBodyMetricRepo{}, newFakeAnalyticsCache())
	userID, exerciseID := uuid.New(), uuid.New()

	_, err := analytics.ProgressOverTime(ctx, userID, exerciseID, 30)
	require.NoError(t, err)
	_, err = analytics.ProgressOverTime(ctx, userID, exerciseID, 30)
	require.NoError(t, err)

	assert.Equal(t, 1, rollup.exerciseCalls, "second call should be served from cache, not hit the repository again")
}

func TestInvalidateForSetClearsCache(t *testing.T) {
	ctx := context.Background()
	rollup := &fakeProgressRollupRepo{}
	analytics := service.NewAnalyticsService(rollup, &fakeBodyMetricRepo{}, newFakeAnalyticsCache())
	userID, exerciseID := uuid.New(), uuid.New()

	_, err := analytics.ProgressOverTime(ctx, userID, exerciseID, 30)
	require.NoError(t, err)

	analytics.InvalidateForSet(ctx, userID, exerciseID)

	_, err = analytics.ProgressOverTime(ctx, userID, exerciseID, 30)
	require.NoError(t, err)

	assert.Equal(t, 2, rollup.exerciseCalls, "invalidation should force a fresh read on the next call")
}

func TestVolumeTrendFiltersToRequestedWindow(t *testing.T) {
	ctx := context.Background()
	now := time.Now()
	rollup := &fakeProgressRollupRepo{userPoints: []*domain.ProgressPoint{
		{Day: now.AddDate(0, 0, -40), TotalVolume: 100},
		{Day: now.AddDate(0, 0, -10), TotalVolume: 200},
		{Day: now, TotalVolume: 300},
	}}
	analytics := service.NewAnalyticsService(rollup, &fakeBodyMetricRepo{}, newFakeAnalyticsCache())

	points, err := analytics.VolumeTrend(ctx, uuid.New(), 30)
	require.NoError(t, err)
	require.Len(t, points, 2, "the 40-day-old point should be excluded by a 30-day window")
	assert.Equal(t, 200.0, points[0].TotalVolume)
	assert.Equal(t, 300.0, points[1].TotalVolume)
}

func TestLogAndListBodyMetrics(t *testing.T) {
	ctx := context.Background()
	analytics := service.NewAnalyticsService(&fakeProgressRollupRepo{}, &fakeBodyMetricRepo{}, newFakeAnalyticsCache())
	userID := uuid.New()

	_, err := analytics.LogBodyMetric(ctx, userID, "bodyweight_kg", 82.5)
	require.NoError(t, err)

	metrics, err := analytics.BodyMetrics(ctx, userID, "bodyweight_kg", 30)
	require.NoError(t, err)
	require.Len(t, metrics, 1)
	assert.Equal(t, 82.5, metrics[0].Value)
}

func TestDetectPlateauWhenNoImprovement(t *testing.T) {
	ctx := context.Background()
	now := time.Now()
	rollup := &fakeProgressRollupRepo{exercisePoints: []*domain.ProgressPoint{
		// prior 3-week window: best 100kg
		{Day: now.AddDate(0, 0, -35), TotalVolume: 500, MaxWeight: 100, SetCount: 3},
		{Day: now.AddDate(0, 0, -28), TotalVolume: 500, MaxWeight: 95, SetCount: 3},
		// recent 3-week window: never beats 100kg, but still trained
		{Day: now.AddDate(0, 0, -14), TotalVolume: 480, MaxWeight: 97.5, SetCount: 3},
		{Day: now.AddDate(0, 0, -7), TotalVolume: 480, MaxWeight: 100, SetCount: 3},
	}}
	analytics := service.NewAnalyticsService(rollup, &fakeBodyMetricRepo{}, newFakeAnalyticsCache())

	status, err := analytics.DetectPlateau(ctx, uuid.New(), uuid.New())
	require.NoError(t, err)
	assert.True(t, status.IsPlateaued)
	assert.Equal(t, 100.0, status.CurrentBestKg)
}

func TestDetectPlateauWhenImproving(t *testing.T) {
	ctx := context.Background()
	now := time.Now()
	rollup := &fakeProgressRollupRepo{exercisePoints: []*domain.ProgressPoint{
		{Day: now.AddDate(0, 0, -35), TotalVolume: 500, MaxWeight: 100, SetCount: 3},
		{Day: now.AddDate(0, 0, -14), TotalVolume: 500, MaxWeight: 105, SetCount: 3},
		{Day: now.AddDate(0, 0, -7), TotalVolume: 500, MaxWeight: 110, SetCount: 3},
	}}
	analytics := service.NewAnalyticsService(rollup, &fakeBodyMetricRepo{}, newFakeAnalyticsCache())

	status, err := analytics.DetectPlateau(ctx, uuid.New(), uuid.New())
	require.NoError(t, err)
	assert.False(t, status.IsPlateaued)
	assert.Equal(t, 110.0, status.CurrentBestKg)
}

func TestDetectPlateauNotEnoughRecentData(t *testing.T) {
	ctx := context.Background()
	now := time.Now()
	rollup := &fakeProgressRollupRepo{exercisePoints: []*domain.ProgressPoint{
		{Day: now.AddDate(0, 0, -35), TotalVolume: 500, MaxWeight: 100, SetCount: 3},
		// Only one recent session — not enough to call it a plateau either way.
		{Day: now.AddDate(0, 0, -7), TotalVolume: 100, MaxWeight: 90, SetCount: 1},
	}}
	analytics := service.NewAnalyticsService(rollup, &fakeBodyMetricRepo{}, newFakeAnalyticsCache())

	status, err := analytics.DetectPlateau(ctx, uuid.New(), uuid.New())
	require.NoError(t, err)
	assert.False(t, status.IsPlateaued)
}
