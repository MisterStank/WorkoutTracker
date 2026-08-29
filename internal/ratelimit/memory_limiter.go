package ratelimit

import (
	"context"
	"sync"
	"time"
)

// MemoryLimiter is an in-process fixed-window limiter. It backs unit tests
// and is wired in as a fallback when the process has no Redis, so a
// single-instance deployment still gets rate limiting (just not shared
// across instances). Expired entries are cleared lazily on access.
type MemoryLimiter struct {
	mu      sync.Mutex
	entries map[string]*memoryEntry
	now     func() time.Time // overridable in tests
}

type memoryEntry struct {
	count     int
	expiresAt time.Time
}

func NewMemoryLimiter() *MemoryLimiter {
	return &MemoryLimiter{entries: map[string]*memoryEntry{}, now: time.Now}
}

func (l *MemoryLimiter) live(key string) *memoryEntry {
	e, ok := l.entries[key]
	if !ok || l.now().After(e.expiresAt) {
		delete(l.entries, key)
		return nil
	}
	return e
}

func (l *MemoryLimiter) Count(_ context.Context, key string) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if e := l.live(key); e != nil {
		return e.count, nil
	}
	return 0, nil
}

func (l *MemoryLimiter) Hit(_ context.Context, key string, window time.Duration) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	e := l.live(key)
	if e == nil {
		e = &memoryEntry{expiresAt: l.now().Add(window)}
		l.entries[key] = e
	}
	e.count++
	return e.count, nil
}

func (l *MemoryLimiter) Reset(_ context.Context, key string) error {
	l.mu.Lock()
	defer l.mu.Unlock()
	delete(l.entries, key)
	return nil
}
