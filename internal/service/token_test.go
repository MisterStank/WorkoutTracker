package service_test

import (
	"testing"
	"time"

	"gymon/internal/service"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestAccessTokenRoundTrip(t *testing.T) {
	issuer := service.NewTokenIssuer([]byte("test-secret"))
	userID := uuid.New()

	tokenString, err := issuer.IssueAccessToken(userID)
	require.NoError(t, err)

	claims, err := issuer.ParseAccessToken(tokenString)
	require.NoError(t, err)
	assert.Equal(t, userID, claims.UserID)
}

func TestParseAccessTokenRejectsWrongSecret(t *testing.T) {
	tokenString, err := service.NewTokenIssuer([]byte("real-secret")).IssueAccessToken(uuid.New())
	require.NoError(t, err)

	_, err = service.NewTokenIssuer([]byte("attacker-secret")).ParseAccessToken(tokenString)
	assert.Error(t, err)
}

func TestParseAccessTokenRejectsExpired(t *testing.T) {
	// Hand-craft an already-expired HS256 token signed with the right key.
	secret := []byte("test-secret")
	claims := service.Claims{
		UserID: uuid.New(),
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(-time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now().Add(-2 * time.Hour)),
		},
	}
	signed, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(secret)
	require.NoError(t, err)

	_, err = service.NewTokenIssuer(secret).ParseAccessToken(signed)
	assert.ErrorIs(t, err, jwt.ErrTokenExpired)
}

// TestParseAccessTokenRejectsAlgNone guards against the classic JWT
// algorithm-confusion attack: a token with "alg":"none" and no signature
// must never be accepted.
func TestParseAccessTokenRejectsAlgNone(t *testing.T) {
	claims := service.Claims{UserID: uuid.New()}
	unsigned := jwt.NewWithClaims(jwt.SigningMethodNone, claims)
	tokenString, err := unsigned.SignedString(jwt.UnsafeAllowNoneSignatureType)
	require.NoError(t, err)

	_, err = service.NewTokenIssuer([]byte("test-secret")).ParseAccessToken(tokenString)
	assert.Error(t, err)
}

func TestRefreshTokenHashingIsStableAndOpaque(t *testing.T) {
	plain, hash, err := service.NewRefreshToken()
	require.NoError(t, err)

	assert.NotEqual(t, plain, hash)
	assert.Equal(t, hash, service.HashRefreshToken(plain))
	assert.NotEqual(t, service.HashRefreshToken("something-else"), hash)

	// Two freshly generated tokens must not collide.
	plain2, _, err := service.NewRefreshToken()
	require.NoError(t, err)
	assert.NotEqual(t, plain, plain2)
}
