package service

import (
	"context"
	"fmt"
	"time"

	"workouttracker/internal/domain"

	"github.com/google/uuid"
)

// AnalyticsCache is a narrow interface AnalyticsService depends on (Dependency
// Inversion) so it can be tested with a no-op or in-memory fake without a
// real Redis. Get returning (false, nil) is a normal cache miss.
type AnalyticsCache interface {
	Get(ctx context.Context, key string, dest any) (bool, error)
	Set(ctx context.Context, key string, value any, ttl time.Duration) error
	Delete(ctx context.Context, keys ...string) error
}

const analyticsCacheTTL = 5 * time.Minute

type AnalyticsService struct {
	rollup      domain.ProgressRollupRepository
	bodyMetrics domain.BodyMetricRepository
	cache       AnalyticsCache // nil disables caching
}

func NewAnalyticsService(rollup domain.ProgressRollupRepository, bodyMetrics domain.BodyMetricRepository, cache AnalyticsCache) *AnalyticsService {
	return &AnalyticsService{rollup: rollup, bodyMetrics: bodyMetrics, cache: cache}
}

func progressCacheKey(userID, exerciseID uuid.UUID) string {
	return fmt.Sprintf("analytics:progress:%s:%s", userID, exerciseID)
}

func volumeCacheKey(userID uuid.UUID) string {
	return fmt.Sprintf("analytics:volume:%s", userID)
}

// ProgressOverTime returns the daily rollup for one exercise across the
// last `days` days. The cache holds each exercise's *full* rollup history
// (small: one row per day the exercise was trained) so a single write-through
// invalidation on log covers every possible days window without keying the
// cache per range.
func (s *AnalyticsService) ProgressOverTime(ctx context.Context, userID, exerciseID uuid.UUID, days int) ([]*domain.ProgressPoint, error) {
	points, err := s.getCachedOrLoad(ctx, progressCacheKey(userID, exerciseID), func() ([]*domain.ProgressPoint, error) {
		return s.rollup.RangeForExercise(ctx, userID, exerciseID, time.Time{})
	})
	if err != nil {
		return nil, err
	}
	return filterSince(points, days), nil
}

func (s *AnalyticsService) VolumeTrend(ctx context.Context, userID uuid.UUID, days int) ([]*domain.ProgressPoint, error) {
	points, err := s.getCachedOrLoad(ctx, volumeCacheKey(userID), func() ([]*domain.ProgressPoint, error) {
		return s.rollup.RangeForUser(ctx, userID, time.Time{})
	})
	if err != nil {
		return nil, err
	}
	return filterSince(points, days), nil
}

func (s *AnalyticsService) getCachedOrLoad(ctx context.Context, key string, load func() ([]*domain.ProgressPoint, error)) ([]*domain.ProgressPoint, error) {
	if s.cache != nil {
		var cached []*domain.ProgressPoint
		if hit, err := s.cache.Get(ctx, key, &cached); err == nil && hit {
			return cached, nil
		}
	}

	points, err := load()
	if err != nil {
		return nil, err
	}

	if s.cache != nil {
		_ = s.cache.Set(ctx, key, points, analyticsCacheTTL)
	}
	return points, nil
}

func filterSince(points []*domain.ProgressPoint, days int) []*domain.ProgressPoint {
	if days <= 0 {
		return points
	}
	cutoff := time.Now().AddDate(0, 0, -days)
	filtered := make([]*domain.ProgressPoint, 0, len(points))
	for _, p := range points {
		if p.Day.After(cutoff) || p.Day.Equal(cutoff) {
			filtered = append(filtered, p)
		}
	}
	return filtered
}

// RecomputeAfterSetChange rebuilds the rollup for one user+exercise+day and
// invalidates the analytics cache — called after a set is edited or
// deleted, since (unlike a fresh LogSet) there's no running total to
// incrementally adjust.
func (s *AnalyticsService) RecomputeAfterSetChange(ctx context.Context, userID, exerciseID uuid.UUID, day time.Time) error {
	if err := s.rollup.RecomputeDay(ctx, userID, exerciseID, day); err != nil {
		return err
	}
	s.InvalidateForSet(ctx, userID, exerciseID)
	return nil
}

// InvalidateForSet is called after a set is logged so the next read of
// either cache entry recomputes from progress_daily_rollup instead of
// serving a now-stale cached series.
func (s *AnalyticsService) InvalidateForSet(ctx context.Context, userID, exerciseID uuid.UUID) {
	if s.cache == nil {
		return
	}
	_ = s.cache.Delete(ctx, progressCacheKey(userID, exerciseID), volumeCacheKey(userID))
}

func (s *AnalyticsService) LogBodyMetric(ctx context.Context, userID uuid.UUID, metricType string, value float64) (*domain.BodyMetric, error) {
	if err := ValidateBodyMetric(metricType, value); err != nil {
		return nil, err
	}
	m := &domain.BodyMetric{
		ID:         uuid.New(),
		UserID:     userID,
		MetricType: metricType,
		Value:      value,
		RecordedAt: time.Now(),
	}
	if err := s.bodyMetrics.Create(ctx, m); err != nil {
		return nil, err
	}
	return m, nil
}

func (s *AnalyticsService) BodyMetrics(ctx context.Context, userID uuid.UUID, metricType string, days int) ([]*domain.BodyMetric, error) {
	since := time.Time{}
	if days > 0 {
		since = time.Now().AddDate(0, 0, -days)
	}
	return s.bodyMetrics.ListForUser(ctx, userID, metricType, since)
}

const plateauWindowDays = 21 // 3 weeks

type PlateauStatus struct {
	IsPlateaued   bool
	CurrentBestKg float64
	Message       string
}

// DetectPlateau compares the heaviest weight lifted in the last 3 weeks
// against the 3 weeks before that. A plateau is flagged only if the
// exercise was actually trained at least twice in the recent window and
// didn't beat the prior window — training too rarely to have a real
// comparison isn't the same thing as stalling.
func (s *AnalyticsService) DetectPlateau(ctx context.Context, userID, exerciseID uuid.UUID) (*PlateauStatus, error) {
	points, err := s.ProgressOverTime(ctx, userID, exerciseID, 2*plateauWindowDays)
	if err != nil {
		return nil, err
	}
	if len(points) == 0 {
		return &PlateauStatus{Message: "Not enough history yet to tell."}, nil
	}

	now := time.Now()
	recentCutoff := now.AddDate(0, 0, -plateauWindowDays)

	var recentBest, priorBest, overallBest float64
	var recentSets int
	for _, p := range points {
		if p.MaxWeight > overallBest {
			overallBest = p.MaxWeight
		}
		if p.Day.After(recentCutoff) {
			recentSets += p.SetCount
			if p.MaxWeight > recentBest {
				recentBest = p.MaxWeight
			}
		} else if p.MaxWeight > priorBest {
			priorBest = p.MaxWeight
		}
	}

	plateaued := recentSets >= 2 && priorBest > 0 && recentBest <= priorBest
	message := fmt.Sprintf("Still progressing — current best is %.1fkg.", overallBest)
	if plateaued {
		message = fmt.Sprintf("No new best in the last 3 weeks (still %.1fkg) — consider a deload or an exercise variation.", overallBest)
	} else if recentSets < 2 {
		message = "Not trained enough recently to tell."
	}

	return &PlateauStatus{IsPlateaued: plateaued, CurrentBestKg: overallBest, Message: message}, nil
}
