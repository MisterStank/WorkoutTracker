package service

import (
	"context"
	"time"

	"workouttracker/internal/domain"

	"github.com/google/uuid"
)

// AuthService depends only on domain interfaces (Dependency Inversion), so it
// can be unit-tested with fakes and never needs to know Postgres exists.
type AuthService struct {
	users         domain.UserRepository
	refreshTokens domain.RefreshTokenRepository
	tokens        *TokenIssuer
}

func NewAuthService(users domain.UserRepository, refreshTokens domain.RefreshTokenRepository, tokens *TokenIssuer) *AuthService {
	return &AuthService{users: users, refreshTokens: refreshTokens, tokens: tokens}
}

type AuthResult struct {
	User         *domain.User
	AccessToken  string
	RefreshToken string
}

func (s *AuthService) SignUp(ctx context.Context, email, password, displayName string) (*AuthResult, error) {
	if _, err := s.users.FindByEmail(ctx, email); err == nil {
		return nil, domain.ErrEmailTaken
	}

	hash, err := HashPassword(password)
	if err != nil {
		return nil, err
	}

	user := &domain.User{
		ID:           uuid.New(),
		Email:        email,
		PasswordHash: hash,
		DisplayName:  displayName,
		Timezone:     "UTC",
		CreatedAt:    time.Now(),
	}
	if err := s.users.Create(ctx, user); err != nil {
		return nil, err
	}

	return s.issueSession(ctx, user, "")
}

func (s *AuthService) Login(ctx context.Context, email, password string) (*AuthResult, error) {
	user, err := s.users.FindByEmail(ctx, email)
	if err != nil {
		return nil, domain.ErrInvalidCredentials
	}

	ok, err := VerifyPassword(password, user.PasswordHash)
	if err != nil || !ok {
		return nil, domain.ErrInvalidCredentials
	}

	return s.issueSession(ctx, user, "")
}

// Refresh rotates the refresh token on every use: the old one is revoked and
// a new one issued, so a stolen-but-unused token becomes detectable (reuse
// of a revoked token is a signal of theft, even though we don't act on it yet).
func (s *AuthService) Refresh(ctx context.Context, refreshTokenPlain string) (*AuthResult, error) {
	hash := HashRefreshToken(refreshTokenPlain)
	stored, err := s.refreshTokens.FindByTokenHash(ctx, hash)
	if err != nil || stored.RevokedAt != nil || stored.ExpiresAt.Before(time.Now()) {
		return nil, domain.ErrRefreshTokenInvalid
	}

	user, err := s.users.FindByID(ctx, stored.UserID)
	if err != nil {
		return nil, domain.ErrUserNotFound
	}

	if err := s.refreshTokens.Revoke(ctx, stored.ID); err != nil {
		return nil, err
	}

	return s.issueSession(ctx, user, stored.DeviceInfo)
}

func (s *AuthService) Logout(ctx context.Context, refreshTokenPlain string) error {
	hash := HashRefreshToken(refreshTokenPlain)
	stored, err := s.refreshTokens.FindByTokenHash(ctx, hash)
	if err != nil {
		return nil // already gone; logout is idempotent
	}
	return s.refreshTokens.Revoke(ctx, stored.ID)
}

func (s *AuthService) LogoutAllDevices(ctx context.Context, userID uuid.UUID) error {
	return s.refreshTokens.RevokeAllForUser(ctx, userID)
}

func (s *AuthService) UserByID(ctx context.Context, userID uuid.UUID) (*domain.User, error) {
	return s.users.FindByID(ctx, userID)
}

func (s *AuthService) issueSession(ctx context.Context, user *domain.User, deviceInfo string) (*AuthResult, error) {
	accessToken, err := s.tokens.IssueAccessToken(user.ID)
	if err != nil {
		return nil, err
	}

	plainRefresh, hashedRefresh, err := NewRefreshToken()
	if err != nil {
		return nil, err
	}

	rt := &domain.RefreshToken{
		ID:         uuid.New(),
		UserID:     user.ID,
		TokenHash:  hashedRefresh,
		DeviceInfo: deviceInfo,
		ExpiresAt:  time.Now().Add(RefreshTokenTTL),
		CreatedAt:  time.Now(),
	}
	if err := s.refreshTokens.Create(ctx, rt); err != nil {
		return nil, err
	}

	return &AuthResult{User: user, AccessToken: accessToken, RefreshToken: plainRefresh}, nil
}
