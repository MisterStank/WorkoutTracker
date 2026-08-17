package domain

import (
	"context"
	"time"

	"github.com/google/uuid"
)

type User struct {
	ID           uuid.UUID
	Email        string
	PasswordHash string
	DisplayName  string
	Timezone     string
	CreatedAt    time.Time
}

type RefreshToken struct {
	ID         uuid.UUID
	UserID     uuid.UUID
	TokenHash  string
	DeviceInfo string
	ExpiresAt  time.Time
	RevokedAt  *time.Time
	CreatedAt  time.Time
}

// UserRepository persists and retrieves users. Implemented by internal/repository
// against Postgres; kept narrow (ISP) so AuthService only depends on what it needs.
type UserRepository interface {
	Create(ctx context.Context, u *User) error
	FindByEmail(ctx context.Context, email string) (*User, error)
	FindByID(ctx context.Context, id uuid.UUID) (*User, error)
}

// RefreshTokenRepository persists refresh tokens (hashed) so sessions can be
// revoked server-side, which a stateless-only JWT cannot support.
type RefreshTokenRepository interface {
	Create(ctx context.Context, t *RefreshToken) error
	FindByTokenHash(ctx context.Context, tokenHash string) (*RefreshToken, error)
	Revoke(ctx context.Context, id uuid.UUID) error
	RevokeAllForUser(ctx context.Context, userID uuid.UUID) error
}
