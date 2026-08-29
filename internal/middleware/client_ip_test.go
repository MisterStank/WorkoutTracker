package middleware_test

import (
	"net/http"
	"net/http/httptest"
	"testing"

	appmiddleware "workouttracker/internal/middleware"

	"github.com/stretchr/testify/assert"
)

func capturedIP(t *testing.T, mutate func(*http.Request)) string {
	t.Helper()
	var got string
	h := appmiddleware.ClientIP(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		got = appmiddleware.ClientIPFromContext(r.Context())
	}))
	req := httptest.NewRequest(http.MethodPost, "/graphql", nil)
	req.RemoteAddr = "10.0.0.1:55555"
	if mutate != nil {
		mutate(req)
	}
	h.ServeHTTP(httptest.NewRecorder(), req)
	return got
}

func TestClientIPUsesRemoteAddrWithoutProxy(t *testing.T) {
	assert.Equal(t, "10.0.0.1", capturedIP(t, nil))
}

func TestClientIPTrustsRightmostForwardedForEntry(t *testing.T) {
	// A client spoofs "1.2.3.4"; the proxy appends the real peer "203.0.113.7".
	ip := capturedIP(t, func(r *http.Request) {
		r.Header.Set("X-Forwarded-For", "1.2.3.4, 203.0.113.7")
	})
	assert.Equal(t, "203.0.113.7", ip, "the rightmost entry is the one the proxy appended")
}

func TestClientIPSingleForwardedForEntry(t *testing.T) {
	ip := capturedIP(t, func(r *http.Request) {
		r.Header.Set("X-Forwarded-For", "198.51.100.23")
	})
	assert.Equal(t, "198.51.100.23", ip)
}

func TestClientIPFromContextEmptyWhenMiddlewareSkipped(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	assert.Equal(t, "", appmiddleware.ClientIPFromContext(req.Context()))
}
