// Package realtime fans out workout events (new sets/PRs) to GraphQL
// subscribers over Redis pub/sub, so the fan-out works even with multiple
// API instances behind a load balancer — a subscriber connected to instance
// A still receives an event published by instance B, because both talk to
// the same Redis channel rather than an in-process channel.
package realtime

import (
	"context"
	"encoding/json"
	"fmt"

	"gymon/internal/domain"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
)

type RedisEventBus struct {
	client *redis.Client
}

func NewRedisEventBus(client *redis.Client) *RedisEventBus {
	return &RedisEventBus{client: client}
}

func channelName(workoutID uuid.UUID) string {
	return fmt.Sprintf("workout-events:%s", workoutID)
}

func (b *RedisEventBus) PublishSetLogged(ctx context.Context, workoutID uuid.UUID, logged *domain.LoggedSet) error {
	payload, err := json.Marshal(logged)
	if err != nil {
		return err
	}
	return b.client.Publish(ctx, channelName(workoutID), payload).Err()
}

// Subscribe returns a channel of LoggedSet events for one workout. The
// returned cleanup function must be called (typically via defer) to close
// the underlying Redis subscription when the GraphQL subscription ends.
func (b *RedisEventBus) Subscribe(ctx context.Context, workoutID uuid.UUID) (<-chan *domain.LoggedSet, func(), error) {
	pubsub := b.client.Subscribe(ctx, channelName(workoutID))
	if _, err := pubsub.Receive(ctx); err != nil {
		_ = pubsub.Close()
		return nil, nil, err
	}

	out := make(chan *domain.LoggedSet)
	go func() {
		defer close(out)
		for msg := range pubsub.Channel() {
			var logged domain.LoggedSet
			if err := json.Unmarshal([]byte(msg.Payload), &logged); err != nil {
				continue
			}
			select {
			case out <- &logged:
			case <-ctx.Done():
				return
			}
		}
	}()

	cleanup := func() { _ = pubsub.Close() }
	return out, cleanup, nil
}
