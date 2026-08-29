package service_test

import (
	"context"
	"fmt"
	"testing"
	"time"

	"workouttracker/internal/domain"
	"workouttracker/internal/ratelimit"
	"workouttracker/internal/service"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func newAuthServiceWithLimiter(l domain.RateLimiter) *service.AuthService {
	return service.NewAuthService(newFakeUserRepo(), newFakeRefreshTokenRepo(), service.NewTokenIssuer([]byte("test-secret")), l)
}

func TestLoginLocksOutAfterRepeatedFailures(t *testing.T) {
	ctx := context.Background()
	auth := newAuthServiceWithLimiter(ratelimit.NewMemoryLimiter())

	_, err := auth.SignUp(ctx, "jane@example.com", "correct-password", "Jane", "1.2.3.4")
	require.NoError(t, err)

	// 8 wrong-password attempts are each rejected as bad credentials...
	for i := 0; i < 8; i++ {
		_, err := auth.Login(ctx, "jane@example.com", "wrong", "1.2.3.4")
		assert.ErrorIs(t, err, domain.ErrInvalidCredentials, "attempt %d", i+1)
	}

	// ...the 9th is refused outright, and now even the *correct* password
	// is refused while the lockout window holds.
	_, err = auth.Login(ctx, "jane@example.com", "wrong", "1.2.3.4")
	assert.ErrorIs(t, err, domain.ErrTooManyRequests)

	_, err = auth.Login(ctx, "jane@example.com", "correct-password", "1.2.3.4")
	assert.ErrorIs(t, err, domain.ErrTooManyRequests)
}

func TestLoginSuccessClearsFailureCount(t *testing.T) {
	ctx := context.Background()
	auth := newAuthServiceWithLimiter(ratelimit.NewMemoryLimiter())

	_, err := auth.SignUp(ctx, "jane@example.com", "correct-password", "Jane", "1.2.3.4")
	require.NoError(t, err)

	for i := 0; i < 5; i++ {
		_, _ = auth.Login(ctx, "jane@example.com", "wrong", "1.2.3.4")
	}
	// A success resets the counter...
	_, err = auth.Login(ctx, "jane@example.com", "correct-password", "1.2.3.4")
	require.NoError(t, err)

	// ...so the user gets a full fresh allowance of failures afterwards.
	for i := 0; i < 8; i++ {
		_, err := auth.Login(ctx, "jane@example.com", "wrong", "1.2.3.4")
		assert.ErrorIs(t, err, domain.ErrInvalidCredentials, "attempt %d", i+1)
	}
}

func TestLoginLockoutIsPerEmail(t *testing.T) {
	ctx := context.Background()
	auth := newAuthServiceWithLimiter(ratelimit.NewMemoryLimiter())

	_, err := auth.SignUp(ctx, "a@example.com", "correct-password", "A", "1.2.3.4")
	require.NoError(t, err)
	_, err = auth.SignUp(ctx, "b@example.com", "correct-password", "B", "1.2.3.4")
	require.NoError(t, err)

	for i := 0; i < 9; i++ {
		_, _ = auth.Login(ctx, "a@example.com", "wrong", "1.2.3.4")
	}
	// a@ is locked; b@ is untouched.
	_, err = auth.Login(ctx, "a@example.com", "correct-password", "1.2.3.4")
	assert.ErrorIs(t, err, domain.ErrTooManyRequests)
	_, err = auth.Login(ctx, "b@example.com", "correct-password", "1.2.3.4")
	assert.NoError(t, err)
}

func TestLoginUnknownEmailStillCountsTowardLockout(t *testing.T) {
	ctx := context.Background()
	auth := newAuthServiceWithLimiter(ratelimit.NewMemoryLimiter())

	for i := 0; i < 8; i++ {
		_, err := auth.Login(ctx, "ghost@example.com", "x", "1.2.3.4")
		assert.ErrorIs(t, err, domain.ErrInvalidCredentials)
	}
	_, err := auth.Login(ctx, "ghost@example.com", "x", "1.2.3.4")
	assert.ErrorIs(t, err, domain.ErrTooManyRequests)
}

func TestSignupRateLimitedPerIP(t *testing.T) {
	ctx := context.Background()
	auth := newAuthServiceWithLimiter(ratelimit.NewMemoryLimiter())

	for i := 0; i < 10; i++ {
		_, err := auth.SignUp(ctx, fmt.Sprintf("u%d@example.com", i), "correct-password", "U", "9.9.9.9")
		require.NoError(t, err, "signup %d", i+1)
	}
	_, err := auth.SignUp(ctx, "u10@example.com", "correct-password", "U", "9.9.9.9")
	assert.ErrorIs(t, err, domain.ErrTooManyRequests)

	// A different IP is unaffected.
	_, err = auth.SignUp(ctx, "other@example.com", "correct-password", "U", "8.8.8.8")
	assert.NoError(t, err)
}

func TestSignupWithoutClientIPIsNotIPLimited(t *testing.T) {
	ctx := context.Background()
	auth := newAuthServiceWithLimiter(ratelimit.NewMemoryLimiter())

	for i := 0; i < 25; i++ {
		_, err := auth.SignUp(ctx, fmt.Sprintf("n%d@example.com", i), "correct-password", "N", "")
		require.NoError(t, err, "signup %d", i+1)
	}
}

func TestRefreshRateLimitedPerIPOnFailure(t *testing.T) {
	ctx := context.Background()
	auth := newAuthServiceWithLimiter(ratelimit.NewMemoryLimiter())

	for i := 0; i < 30; i++ {
		_, err := auth.Refresh(ctx, "bogus-token", "5.5.5.5")
		assert.ErrorIs(t, err, domain.ErrRefreshTokenInvalid, "attempt %d", i+1)
	}
	_, err := auth.Refresh(ctx, "bogus-token", "5.5.5.5")
	assert.ErrorIs(t, err, domain.ErrTooManyRequests)
}

// brokenRateLimiter errors on every call. Auth must fail open (allow the
// request) rather than lock every user out when Redis is unavailable.
type brokenRateLimiter struct{}

func (brokenRateLimiter) Count(context.Context, string) (int, error) {
	return 0, fmt.Errorf("redis down")
}
func (brokenRateLimiter) Hit(context.Context, string, time.Duration) (int, error) {
	return 0, fmt.Errorf("redis down")
}
func (brokenRateLimiter) Reset(context.Context, string) error { return fmt.Errorf("redis down") }

func TestAuthFailsOpenWhenLimiterErrors(t *testing.T) {
	ctx := context.Background()
	auth := newAuthServiceWithLimiter(brokenRateLimiter{})

	_, err := auth.SignUp(ctx, "jane@example.com", "correct-password", "Jane", "1.2.3.4")
	require.NoError(t, err)
	_, err = auth.Login(ctx, "jane@example.com", "correct-password", "1.2.3.4")
	require.NoError(t, err)
}
