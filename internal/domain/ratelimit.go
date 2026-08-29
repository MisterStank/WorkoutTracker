package domain

import (
	"context"
	"time"
)

// RateLimiter is a fixed-window counter keyed by an arbitrary string. The
// service layer decides what to count (failed logins per email, signups per
// IP) and the thresholds; implementations only own the storage. Redis backs
// it in production so the limit holds across multiple API instances; an
// in-memory implementation backs unit tests.
type RateLimiter interface {
	// Count returns the current hit count for key, or 0 if the key is absent
	// or expired.
	Count(ctx context.Context, key string) (int, error)
	// Hit increments the counter for key, setting its expiry to window the
	// first time the key is created within a window. Returns the new count.
	Hit(ctx context.Context, key string, window time.Duration) (int, error)
	// Reset clears the counter for key (e.g. after a successful login).
	Reset(ctx context.Context, key string) error
}
