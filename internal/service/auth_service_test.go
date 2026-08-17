package service_test

import (
	"context"
	"sync"
	"testing"

	"workouttracker/internal/domain"
	"workouttracker/internal/service"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// fakeUserRepo and fakeRefreshTokenRepo are in-memory domain.*Repository
// implementations, letting AuthService be tested without a real Postgres —
// this is possible only because AuthService depends on interfaces, not
// concrete repositories (Dependency Inversion).

type fakeUserRepo struct {
	mu    sync.Mutex
	byID  map[uuid.UUID]*domain.User
	byEml map[string]*domain.User
}

func newFakeUserRepo() *fakeUserRepo {
	return &fakeUserRepo{byID: map[uuid.UUID]*domain.User{}, byEml: map[string]*domain.User{}}
}

func (f *fakeUserRepo) Create(ctx context.Context, u *domain.User) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.byID[u.ID] = u
	f.byEml[u.Email] = u
	return nil
}

func (f *fakeUserRepo) FindByEmail(ctx context.Context, email string) (*domain.User, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	u, ok := f.byEml[email]
	if !ok {
		return nil, domain.ErrUserNotFound
	}
	return u, nil
}

func (f *fakeUserRepo) FindByID(ctx context.Context, id uuid.UUID) (*domain.User, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	u, ok := f.byID[id]
	if !ok {
		return nil, domain.ErrUserNotFound
	}
	return u, nil
}

type fakeRefreshTokenRepo struct {
	mu     sync.Mutex
	tokens map[uuid.UUID]*domain.RefreshToken
	byHash map[string]uuid.UUID
}

func newFakeRefreshTokenRepo() *fakeRefreshTokenRepo {
	return &fakeRefreshTokenRepo{tokens: map[uuid.UUID]*domain.RefreshToken{}, byHash: map[string]uuid.UUID{}}
}

func (f *fakeRefreshTokenRepo) Create(ctx context.Context, t *domain.RefreshToken) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.tokens[t.ID] = t
	f.byHash[t.TokenHash] = t.ID
	return nil
}

func (f *fakeRefreshTokenRepo) FindByTokenHash(ctx context.Context, hash string) (*domain.RefreshToken, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	id, ok := f.byHash[hash]
	if !ok {
		return nil, domain.ErrRefreshTokenInvalid
	}
	return f.tokens[id], nil
}

func (f *fakeRefreshTokenRepo) Revoke(ctx context.Context, id uuid.UUID) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if t, ok := f.tokens[id]; ok {
		now := t.ExpiresAt
		t.RevokedAt = &now
	}
	return nil
}

func (f *fakeRefreshTokenRepo) RevokeAllForUser(ctx context.Context, userID uuid.UUID) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, t := range f.tokens {
		if t.UserID == userID {
			now := t.ExpiresAt
			t.RevokedAt = &now
		}
	}
	return nil
}

func newTestAuthService() *service.AuthService {
	return service.NewAuthService(newFakeUserRepo(), newFakeRefreshTokenRepo(), service.NewTokenIssuer([]byte("test-secret")))
}

func TestSignUpThenLogin(t *testing.T) {
	ctx := context.Background()
	auth := newTestAuthService()

	signupRes, err := auth.SignUp(ctx, "jane@example.com", "correct-horse-battery-staple", "Jane")
	require.NoError(t, err)
	assert.NotEmpty(t, signupRes.AccessToken)
	assert.NotEmpty(t, signupRes.RefreshToken)

	loginRes, err := auth.Login(ctx, "jane@example.com", "correct-horse-battery-staple")
	require.NoError(t, err)
	assert.Equal(t, signupRes.User.ID, loginRes.User.ID)
}

func TestSignUpDuplicateEmailRejected(t *testing.T) {
	ctx := context.Background()
	auth := newTestAuthService()

	_, err := auth.SignUp(ctx, "jane@example.com", "password123", "Jane")
	require.NoError(t, err)

	_, err = auth.SignUp(ctx, "jane@example.com", "different-password", "Jane 2")
	assert.ErrorIs(t, err, domain.ErrEmailTaken)
}

func TestLoginWrongPasswordRejected(t *testing.T) {
	ctx := context.Background()
	auth := newTestAuthService()

	_, err := auth.SignUp(ctx, "jane@example.com", "correct-password", "Jane")
	require.NoError(t, err)

	_, err = auth.Login(ctx, "jane@example.com", "wrong-password")
	assert.ErrorIs(t, err, domain.ErrInvalidCredentials)
}

func TestRefreshRotatesToken(t *testing.T) {
	ctx := context.Background()
	auth := newTestAuthService()

	signupRes, err := auth.SignUp(ctx, "jane@example.com", "correct-password", "Jane")
	require.NoError(t, err)

	refreshRes, err := auth.Refresh(ctx, signupRes.RefreshToken)
	require.NoError(t, err)
	assert.NotEqual(t, signupRes.RefreshToken, refreshRes.RefreshToken, "refresh token should rotate on use")

	// the old (now-revoked) refresh token must no longer work
	_, err = auth.Refresh(ctx, signupRes.RefreshToken)
	assert.ErrorIs(t, err, domain.ErrRefreshTokenInvalid)
}

func TestLogoutRevokesToken(t *testing.T) {
	ctx := context.Background()
	auth := newTestAuthService()

	signupRes, err := auth.SignUp(ctx, "jane@example.com", "correct-password", "Jane")
	require.NoError(t, err)

	require.NoError(t, auth.Logout(ctx, signupRes.RefreshToken))

	_, err = auth.Refresh(ctx, signupRes.RefreshToken)
	assert.ErrorIs(t, err, domain.ErrRefreshTokenInvalid)
}
