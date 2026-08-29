package middleware

import (
	"context"
	"net"
	"net/http"
	"strings"
)

type clientIPKey struct{}

// ClientIP stashes the caller's IP address in the request context so the
// GraphQL layer can pass it to rate limiting. It reads the *rightmost*
// X-Forwarded-For entry when present — behind exactly one reverse proxy
// (Render, Fly, an ingress) that entry is the one the proxy itself appended
// (the real TCP peer), whereas any earlier entries are attacker-controlled
// and must not be trusted. With no proxy, X-Forwarded-For is absent and the
// TCP peer from RemoteAddr is used directly.
func ClientIP(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ip := clientIPFromRequest(r)
		ctx := context.WithValue(r.Context(), clientIPKey{}, ip)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func clientIPFromRequest(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		parts := strings.Split(xff, ",")
		if last := strings.TrimSpace(parts[len(parts)-1]); last != "" {
			return last
		}
	}
	if host, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
		return host
	}
	return r.RemoteAddr
}

// ClientIPFromContext returns the IP recorded by the ClientIP middleware, or
// "" if the request didn't pass through it (e.g. a websocket handshake or a
// unit test).
func ClientIPFromContext(ctx context.Context) string {
	ip, _ := ctx.Value(clientIPKey{}).(string)
	return ip
}
