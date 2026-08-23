// Package cache provides a small Redis-backed JSON cache used by
// AnalyticsService to avoid re-scanning progress_daily_rollup on every
// dashboard read. It's intentionally generic (Get/Set/Delete by key) rather
// than analytics-specific, so the service layer owns cache-key shape and
// invalidation policy (write-through: deleted immediately after the write
// that would make a cached read stale) while this package only owns
// talking to Redis.
package cache

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/redis/go-redis/v9"
)

type RedisCache struct {
	client *redis.Client
}

func NewRedisCache(client *redis.Client) *RedisCache {
	return &RedisCache{client: client}
}

// Get reports whether key was present and, if so, unmarshals its value into
// dest. A cache miss or Redis error is treated the same way by callers
// (fall through to the source of truth), so both return (false, nil) — only
// a malformed cached payload is a real error.
func (c *RedisCache) Get(ctx context.Context, key string, dest any) (bool, error) {
	raw, err := c.client.Get(ctx, key).Bytes()
	if errors.Is(err, redis.Nil) {
		return false, nil
	}
	if err != nil {
		return false, nil
	}
	if err := json.Unmarshal(raw, dest); err != nil {
		return false, err
	}
	return true, nil
}

func (c *RedisCache) Set(ctx context.Context, key string, value any, ttl time.Duration) error {
	raw, err := json.Marshal(value)
	if err != nil {
		return err
	}
	return c.client.Set(ctx, key, raw, ttl).Err()
}

func (c *RedisCache) Delete(ctx context.Context, keys ...string) error {
	if len(keys) == 0 {
		return nil
	}
	return c.client.Del(ctx, keys...).Err()
}
