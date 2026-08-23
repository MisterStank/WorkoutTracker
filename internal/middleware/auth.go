package middleware

import (
	"context"
	"net/http"
	"strings"

	"workouttracker/internal/service"

	"github.com/google/uuid"
)

type contextKey string

const userIDContextKey contextKey = "userID"

// Auth injects the authenticated user ID into the request context when a
// valid access token is present. It never rejects the request itself —
// GraphQL resolvers/services decide what requires auth via FromContext,
// keeping "is this field public" a service-layer decision, not a transport one.
func Auth(tokens *service.TokenIssuer) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			header := r.Header.Get("Authorization")
			tokenString, ok := strings.CutPrefix(header, "Bearer ")
			if !ok {
				next.ServeHTTP(w, r)
				return
			}

			claims, err := tokens.ParseAccessToken(tokenString)
			if err != nil {
				next.ServeHTTP(w, r)
				return
			}

			ctx := context.WithValue(r.Context(), userIDContextKey, claims.UserID)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

func FromContext(ctx context.Context) (uuid.UUID, bool) {
	id, ok := ctx.Value(userIDContextKey).(uuid.UUID)
	return id, ok
}

// WithUserID injects an authenticated user ID into ctx directly, for
// transports (e.g. the GraphQL websocket subscription handshake) that
// authenticate outside the normal HTTP middleware chain.
func WithUserID(ctx context.Context, userID uuid.UUID) context.Context {
	return context.WithValue(ctx, userIDContextKey, userID)
}
