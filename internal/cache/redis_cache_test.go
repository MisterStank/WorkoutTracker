package cache_test

import (
	"context"
	"testing"
	"time"

	"workouttracker/internal/cache"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func newCache(t *testing.T) (*cache.RedisCache, *miniredis.Miniredis) {
	t.Helper()
	mr := miniredis.RunT(t)
	rc := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rc.Close() })
	return cache.NewRedisCache(rc), mr
}

type sample struct {
	Name  string `json:"name"`
	Count int    `json:"count"`
}

func TestCacheSetThenGet(t *testing.T) {
	c, _ := newCache(t)
	ctx := context.Background()

	require.NoError(t, c.Set(ctx, "k", sample{Name: "squat", Count: 3}, time.Minute))

	var got sample
	found, err := c.Get(ctx, "k", &got)
	require.NoError(t, err)
	assert.True(t, found)
	assert.Equal(t, sample{Name: "squat", Count: 3}, got)
}

func TestCacheMissReturnsFalseNotError(t *testing.T) {
	c, _ := newCache(t)

	var got sample
	found, err := c.Get(context.Background(), "absent", &got)
	require.NoError(t, err)
	assert.False(t, found)
}

func TestCacheGetOnMalformedPayloadIsError(t *testing.T) {
	c, mr := newCache(t)
	require.NoError(t, mr.Set("k", "{not-valid-json"))

	var got sample
	_, err := c.Get(context.Background(), "k", &got)
	assert.Error(t, err)
}

func TestCacheDelete(t *testing.T) {
	c, _ := newCache(t)
	ctx := context.Background()
	require.NoError(t, c.Set(ctx, "a", sample{Name: "x"}, time.Minute))
	require.NoError(t, c.Set(ctx, "b", sample{Name: "y"}, time.Minute))

	require.NoError(t, c.Delete(ctx, "a", "b"))
	require.NoError(t, c.Delete(ctx)) // no-op, no error

	var got sample
	found, _ := c.Get(ctx, "a", &got)
	assert.False(t, found)
}

func TestCacheRespectsTTL(t *testing.T) {
	c, mr := newCache(t)
	ctx := context.Background()
	require.NoError(t, c.Set(ctx, "k", sample{Name: "z"}, time.Minute))

	mr.FastForward(61 * time.Second)

	var got sample
	found, err := c.Get(ctx, "k", &got)
	require.NoError(t, err)
	assert.False(t, found)
}
