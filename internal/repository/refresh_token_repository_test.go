package repository_test

import (
	"context"
	"testing"
	"time"

	"gymon/internal/domain"
	"gymon/internal/repository"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestRefreshTokenRepository_CreateFindRevoke(t *testing.T) {
	pool := requireDB(t)
	user := makeUser(t, pool)
	repo := repository.NewRefreshTokenRepository(pool)
	ctx := context.Background()

	tok := &domain.RefreshToken{
		ID:         uuid.New(),
		UserID:     user.ID,
		TokenHash:  "hash-" + uuid.NewString(),
		DeviceInfo: "pixel-8",
		ExpiresAt:  time.Now().Add(24 * time.Hour),
		CreatedAt:  time.Now(),
	}
	require.NoError(t, repo.Create(ctx, tok))

	found, err := repo.FindByTokenHash(ctx, tok.TokenHash)
	require.NoError(t, err)
	assert.Equal(t, tok.ID, found.ID)
	assert.Nil(t, found.RevokedAt)

	require.NoError(t, repo.Revoke(ctx, tok.ID))
	found, err = repo.FindByTokenHash(ctx, tok.TokenHash)
	require.NoError(t, err)
	require.NotNil(t, found.RevokedAt, "Revoke must stamp revoked_at")
}

func TestRefreshTokenRepository_FindMissing(t *testing.T) {
	pool := requireDB(t)
	repo := repository.NewRefreshTokenRepository(pool)

	_, err := repo.FindByTokenHash(context.Background(), "no-such-hash-"+uuid.NewString())
	assert.ErrorIs(t, err, domain.ErrRefreshTokenInvalid)
}

func TestRefreshTokenRepository_RevokeAllForUser(t *testing.T) {
	pool := requireDB(t)
	user := makeUser(t, pool)
	repo := repository.NewRefreshTokenRepository(pool)
	ctx := context.Background()

	var hashes []string
	for i := 0; i < 3; i++ {
		h := "multi-" + uuid.NewString()
		hashes = append(hashes, h)
		require.NoError(t, repo.Create(ctx, &domain.RefreshToken{
			ID: uuid.New(), UserID: user.ID, TokenHash: h,
			ExpiresAt: time.Now().Add(time.Hour), CreatedAt: time.Now(),
		}))
	}

	require.NoError(t, repo.RevokeAllForUser(ctx, user.ID))

	for _, h := range hashes {
		found, err := repo.FindByTokenHash(ctx, h)
		require.NoError(t, err)
		assert.NotNil(t, found.RevokedAt, "every token for the user should be revoked")
	}
}
