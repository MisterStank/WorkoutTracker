// Package ratelimit provides fixed-window rate limiters implementing
// domain.RateLimiter. RedisLimiter is used in production (the window is
// shared across every API instance); MemoryLimiter backs tests and is a
// safe fallback when Redis is unavailable.
package ratelimit

import (
	"context"
	"time"

	"github.com/redis/go-redis/v9"
)

// RedisLimiter is a fixed-window counter backed by Redis INCR + a first-hit
// EXPIRE. "Fixed window" (not sliding) is deliberate: it's one round trip,
// needs no stored timestamps, and the small burst-at-window-edge weakness
// it has doesn't matter for abuse protection on auth endpoints.
type RedisLimiter struct {
	client *redis.Client
	prefix string
}

func NewRedisLimiter(client *redis.Client) *RedisLimiter {
	return &RedisLimiter{client: client, prefix: "rl:"}
}

func (l *RedisLimiter) key(k string) string { return l.prefix + k }

func (l *RedisLimiter) Count(ctx context.Context, key string) (int, error) {
	n, err := l.client.Get(ctx, l.key(key)).Int()
	if err == redis.Nil {
		return 0, nil
	}
	if err != nil {
		return 0, err
	}
	return n, nil
}

func (l *RedisLimiter) Hit(ctx context.Context, key string, window time.Duration) (int, error) {
	redisKey := l.key(key)
	n, err := l.client.Incr(ctx, redisKey).Result()
	if err != nil {
		return 0, err
	}
	// Only the hit that created the key sets the TTL, so the window is
	// anchored to the first attempt and doesn't slide forward on every hit.
	if n == 1 {
		if err := l.client.Expire(ctx, redisKey, window).Err(); err != nil {
			return int(n), err
		}
	}
	return int(n), nil
}

func (l *RedisLimiter) Reset(ctx context.Context, key string) error {
	return l.client.Del(ctx, l.key(key)).Err()
}
