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

func TestUserRepository_CreateAndFind(t *testing.T) {
	pool := requireDB(t)
	repo := repository.NewUserRepository(pool)
	ctx := context.Background()

	u := &domain.User{
		ID:           uuid.New(),
		Email:        "found-" + uuid.NewString() + "@test.local",
		PasswordHash: "hash",
		DisplayName:  "Dana",
		Timezone:     "UTC",
		CreatedAt:    time.Now().Truncate(time.Millisecond),
	}
	require.NoError(t, repo.Create(ctx, u))

	byEmail, err := repo.FindByEmail(ctx, u.Email)
	require.NoError(t, err)
	assert.Equal(t, u.ID, byEmail.ID)
	assert.Equal(t, "Dana", byEmail.DisplayName)

	byID, err := repo.FindByID(ctx, u.ID)
	require.NoError(t, err)
	assert.Equal(t, u.Email, byID.Email)
}

func TestUserRepository_FindMissingReturnsDomainError(t *testing.T) {
	pool := requireDB(t)
	repo := repository.NewUserRepository(pool)
	ctx := context.Background()

	_, err := repo.FindByEmail(ctx, "nobody-"+uuid.NewString()+"@test.local")
	assert.ErrorIs(t, err, domain.ErrUserNotFound)

	_, err = repo.FindByID(ctx, uuid.New())
	assert.ErrorIs(t, err, domain.ErrUserNotFound)
}

func TestUserRepository_DuplicateEmailRejectedByDB(t *testing.T) {
	pool := requireDB(t)
	repo := repository.NewUserRepository(pool)
	ctx := context.Background()

	email := "dup-" + uuid.NewString() + "@test.local"
	require.NoError(t, repo.Create(ctx, &domain.User{
		ID: uuid.New(), Email: email, PasswordHash: "h", DisplayName: "A", Timezone: "UTC", CreatedAt: time.Now(),
	}))

	err := repo.Create(ctx, &domain.User{
		ID: uuid.New(), Email: email, PasswordHash: "h", DisplayName: "B", Timezone: "UTC", CreatedAt: time.Now(),
	})
	assert.Error(t, err, "the unique index on users.email must reject a second row")
}
