package service

import (
	"context"
	"log"
	"time"

	"workouttracker/internal/domain"
)

// authThrottle holds the rate-limit policy for the auth endpoints. The
// thresholds are deliberately generous — they exist to blunt brute-force and
// credential-stuffing, not to inconvenience a person mistyping a password
// twice.
type authThrottle struct {
	limiter domain.RateLimiter
}

const (
	// Failed logins for one email address before that email is locked out.
	loginMaxFailures = 8
	loginWindow      = 15 * time.Minute

	// Signups from one client IP per window.
	signupMaxPerIP = 10
	signupWindow   = time.Hour

	// Failed token refreshes from one client IP per window. Lenient: a
	// healthy client refreshes roughly every 15 minutes and never fails.
	refreshMaxFailures = 30
	refreshWindow      = 15 * time.Minute
)

func newAuthThrottle(limiter domain.RateLimiter) *authThrottle {
	return &authThrottle{limiter: limiter}
}

// count returns the current hit count, treating a limiter error as "not
// limited" and logging it — a flaky Redis must not lock every user out.
func (t *authThrottle) count(ctx context.Context, key string) int {
	n, err := t.limiter.Count(ctx, key)
	if err != nil {
		log.Printf("ratelimit: Count(%q) failed, allowing request: %v", key, err)
		return 0
	}
	return n
}

func (t *authThrottle) hit(ctx context.Context, key string, window time.Duration) {
	if _, err := t.limiter.Hit(ctx, key, window); err != nil {
		log.Printf("ratelimit: Hit(%q) failed: %v", key, err)
	}
}

func (t *authThrottle) reset(ctx context.Context, key string) {
	if err := t.limiter.Reset(ctx, key); err != nil {
		log.Printf("ratelimit: Reset(%q) failed: %v", key, err)
	}
}

func loginKey(email string) string { return "login:" + email }

func (t *authThrottle) checkLogin(ctx context.Context, email, _ string) error {
	if t.count(ctx, loginKey(email)) >= loginMaxFailures {
		return domain.ErrTooManyRequests
	}
	return nil
}

func (t *authThrottle) recordLoginFailure(ctx context.Context, email, _ string) {
	t.hit(ctx, loginKey(email), loginWindow)
}

func (t *authThrottle) clearLogin(ctx context.Context, email, _ string) {
	t.reset(ctx, loginKey(email))
}

func (t *authThrottle) checkSignup(ctx context.Context, clientIP string) error {
	if clientIP == "" {
		return nil // no usable client identity (non-HTTP path); email uniqueness still applies
	}
	key := "signup:" + clientIP
	if t.count(ctx, key) >= signupMaxPerIP {
		return domain.ErrTooManyRequests
	}
	// Every signup attempt from this IP counts, successful or not — signup
	// abuse is about volume, not failures.
	t.hit(ctx, key, signupWindow)
	return nil
}

func (t *authThrottle) checkRefresh(ctx context.Context, clientIP string) error {
	if clientIP == "" {
		return nil
	}
	if t.count(ctx, "refresh:"+clientIP) >= refreshMaxFailures {
		return domain.ErrTooManyRequests
	}
	return nil
}

func (t *authThrottle) recordRefreshFailure(ctx context.Context, clientIP string) {
	if clientIP == "" {
		return
	}
	t.hit(ctx, "refresh:"+clientIP, refreshWindow)
}
