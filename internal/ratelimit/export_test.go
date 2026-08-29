package ratelimit

import "time"

// SetMemoryClock overrides a MemoryLimiter's clock so window-expiry can be
// tested without real sleeps. Test-only (export_test.go is compiled only
// under `go test`).
func SetMemoryClock(l *MemoryLimiter, now func() time.Time) { l.now = now }
