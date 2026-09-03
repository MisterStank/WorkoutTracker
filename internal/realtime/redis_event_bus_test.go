package realtime_test

import (
	"context"
	"testing"
	"time"

	"gymon/internal/domain"
	"gymon/internal/realtime"

	"github.com/alicebob/miniredis/v2"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func newBus(t *testing.T) *realtime.RedisEventBus {
	t.Helper()
	mr, err := miniredis.Run() // not RunT: needs to outlive nothing special, but pub/sub wants a real goroutine loop
	require.NoError(t, err)
	t.Cleanup(mr.Close)
	rc := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rc.Close() })
	return realtime.NewRedisEventBus(rc)
}

func TestPublishReachesSubscriber(t *testing.T) {
	bus := newBus(t)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	workoutID := uuid.New()
	events, cleanup, err := bus.Subscribe(ctx, workoutID)
	require.NoError(t, err)
	defer cleanup()

	setID := uuid.New()
	go func() {
		// small delay so the subscription's receive loop is running
		time.Sleep(50 * time.Millisecond)
		_ = bus.PublishSetLogged(ctx, workoutID, &domain.LoggedSet{Set: &domain.WorkoutSet{ID: setID, Reps: 5}})
	}()

	select {
	case got := <-events:
		require.NotNil(t, got)
		require.NotNil(t, got.Set)
		assert.Equal(t, setID, got.Set.ID)
		assert.Equal(t, 5, got.Set.Reps)
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for the published event")
	}
}

func TestSubscribersOnlyGetTheirWorkout(t *testing.T) {
	bus := newBus(t)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	mine := uuid.New()
	other := uuid.New()

	events, cleanup, err := bus.Subscribe(ctx, mine)
	require.NoError(t, err)
	defer cleanup()

	time.Sleep(50 * time.Millisecond)
	require.NoError(t, bus.PublishSetLogged(ctx, other, &domain.LoggedSet{Set: &domain.WorkoutSet{ID: uuid.New()}}))

	select {
	case <-events:
		t.Fatal("received an event for a different workout")
	case <-time.After(300 * time.Millisecond):
		// expected: nothing arrives
	}
}

func TestCleanupClosesChannel(t *testing.T) {
	bus := newBus(t)
	ctx := context.Background()

	events, cleanup, err := bus.Subscribe(ctx, uuid.New())
	require.NoError(t, err)

	cleanup()

	select {
	case _, open := <-events:
		assert.False(t, open, "channel should be closed after cleanup")
	case <-time.After(2 * time.Second):
		t.Fatal("channel was not closed after cleanup")
	}
}
