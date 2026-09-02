package platform_test

import (
	"context"
	"testing"

	"gymon/internal/platform"

	"github.com/alicebob/miniredis/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewRedisClientConnects(t *testing.T) {
	mr := miniredis.RunT(t)

	client, err := platform.NewRedisClient(context.Background(), "redis://"+mr.Addr())
	require.NoError(t, err)
	defer client.Close()

	require.NoError(t, client.Set(context.Background(), "k", "v", 0).Err())
	got, err := client.Get(context.Background(), "k").Result()
	require.NoError(t, err)
	assert.Equal(t, "v", got)
}

func TestNewRedisClientRejectsBadURL(t *testing.T) {
	_, err := platform.NewRedisClient(context.Background(), "not-a-redis-url")
	assert.Error(t, err)
}

func TestNewRedisClientFailsWhenServerUnreachable(t *testing.T) {
	// Port 1 is reserved and never listening.
	_, err := platform.NewRedisClient(context.Background(), "redis://127.0.0.1:1")
	assert.Error(t, err, "the constructor pings on connect, so an unreachable server is an error")
}
