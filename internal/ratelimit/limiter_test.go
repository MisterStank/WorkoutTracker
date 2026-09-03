package ratelimit_test

import (
	"context"
	"testing"
	"time"

	"gymon/internal/domain"
	"gymon/internal/ratelimit"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Both implementations must satisfy the same contract, so the behavioural
// tests run against each via this table.
func eachLimiter(t *testing.T) map[string]domain.RateLimiter {
	t.Helper()

	mr := miniredis.RunT(t)
	rc := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rc.Close() })

	return map[string]domain.RateLimiter{
		"memory": ratelimit.NewMemoryLimiter(),
		"redis":  ratelimit.NewRedisLimiter(rc),
	}
}

func TestLimiterCountsHits(t *testing.T) {
	ctx := context.Background()
	for name, l := range eachLimiter(t) {
		t.Run(name, func(t *testing.T) {
			n, err := l.Count(ctx, "k")
			require.NoError(t, err)
			assert.Equal(t, 0, n, "absent key counts as 0")

			for i := 1; i <= 3; i++ {
				got, err := l.Hit(ctx, "k", time.Minute)
				require.NoError(t, err)
				assert.Equal(t, i, got)
			}

			n, err = l.Count(ctx, "k")
			require.NoError(t, err)
			assert.Equal(t, 3, n)
		})
	}
}

func TestLimiterResetClearsCount(t *testing.T) {
	ctx := context.Background()
	for name, l := range eachLimiter(t) {
		t.Run(name, func(t *testing.T) {
			_, _ = l.Hit(ctx, "k", time.Minute)
			_, _ = l.Hit(ctx, "k", time.Minute)
			require.NoError(t, l.Reset(ctx, "k"))

			n, err := l.Count(ctx, "k")
			require.NoError(t, err)
			assert.Equal(t, 0, n)
		})
	}
}

func TestLimiterKeysAreIndependent(t *testing.T) {
	ctx := context.Background()
	for name, l := range eachLimiter(t) {
		t.Run(name, func(t *testing.T) {
			_, _ = l.Hit(ctx, "a", time.Minute)
			_, _ = l.Hit(ctx, "a", time.Minute)
			_, _ = l.Hit(ctx, "b", time.Minute)

			a, _ := l.Count(ctx, "a")
			b, _ := l.Count(ctx, "b")
			assert.Equal(t, 2, a)
			assert.Equal(t, 1, b)
		})
	}
}

func TestLimiterWindowExpires(t *testing.T) {
	ctx := context.Background()

	// memory limiter with a controllable clock
	ml := ratelimit.NewMemoryLimiter()
	now := time.Now()
	ratelimit.SetMemoryClock(ml, func() time.Time { return now })
	_, _ = ml.Hit(ctx, "k", time.Minute)
	_, _ = ml.Hit(ctx, "k", time.Minute)
	now = now.Add(61 * time.Second)
	n, err := ml.Count(ctx, "k")
	require.NoError(t, err)
	assert.Equal(t, 0, n, "count resets once the window passes")

	// redis limiter: only the first hit sets the TTL, so the window is
	// anchored to the first attempt and doesn't slide forward.
	mr := miniredis.RunT(t)
	rc := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rc.Close() })
	rl := ratelimit.NewRedisLimiter(rc)
	_, _ = rl.Hit(ctx, "k", time.Minute)
	mr.FastForward(30 * time.Second)
	_, _ = rl.Hit(ctx, "k", time.Minute)
	mr.FastForward(31 * time.Second) // 61s since the first hit
	n, err = rl.Count(ctx, "k")
	require.NoError(t, err)
	assert.Equal(t, 0, n)
}
