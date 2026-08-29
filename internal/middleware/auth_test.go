package middleware_test

import (
	"net/http"
	"net/http/httptest"
	"testing"

	appmiddleware "workouttracker/internal/middleware"
	"workouttracker/internal/service"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// runAuth sends one request through the Auth middleware and reports the
// user ID the downstream handler saw (uuid.Nil + false if none).
func runAuth(t *testing.T, authHeader string, tokens *service.TokenIssuer) (uuid.UUID, bool) {
	t.Helper()
	var gotID uuid.UUID
	var gotOK bool
	h := appmiddleware.Auth(tokens)(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		gotID, gotOK = appmiddleware.FromContext(r.Context())
	}))
	req := httptest.NewRequest(http.MethodPost, "/graphql", nil)
	if authHeader != "" {
		req.Header.Set("Authorization", authHeader)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	assert.Equal(t, http.StatusOK, rec.Code, "Auth middleware must never reject the request itself")
	return gotID, gotOK
}

func TestAuthInjectsUserIDForValidToken(t *testing.T) {
	tokens := service.NewTokenIssuer([]byte("test-secret"))
	userID := uuid.New()
	token, err := tokens.IssueAccessToken(userID)
	require.NoError(t, err)

	gotID, ok := runAuth(t, "Bearer "+token, tokens)
	assert.True(t, ok)
	assert.Equal(t, userID, gotID)
}

func TestAuthNoHeaderIsAnonymous(t *testing.T) {
	_, ok := runAuth(t, "", service.NewTokenIssuer([]byte("test-secret")))
	assert.False(t, ok)
}

func TestAuthIgnoresNonBearerHeader(t *testing.T) {
	_, ok := runAuth(t, "Basic dXNlcjpwYXNz", service.NewTokenIssuer([]byte("test-secret")))
	assert.False(t, ok)
}

func TestAuthIgnoresTokenSignedWithAnotherSecret(t *testing.T) {
	foreign := service.NewTokenIssuer([]byte("attacker-secret"))
	token, err := foreign.IssueAccessToken(uuid.New())
	require.NoError(t, err)

	_, ok := runAuth(t, "Bearer "+token, service.NewTokenIssuer([]byte("real-secret")))
	assert.False(t, ok, "a token we didn't sign must not authenticate")
}

func TestAuthIgnoresGarbageToken(t *testing.T) {
	_, ok := runAuth(t, "Bearer not-a-jwt", service.NewTokenIssuer([]byte("test-secret")))
	assert.False(t, ok)
}

func TestWithUserIDRoundTrips(t *testing.T) {
	id := uuid.New()
	ctx := appmiddleware.WithUserID(t.Context(), id)
	got, ok := appmiddleware.FromContext(ctx)
	assert.True(t, ok)
	assert.Equal(t, id, got)
}
