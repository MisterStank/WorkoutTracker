package service_test

import (
	"strings"
	"testing"

	"workouttracker/internal/service"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestHashPasswordVerifies(t *testing.T) {
	hash, err := service.HashPassword("correct horse battery staple")
	require.NoError(t, err)
	assert.True(t, strings.HasPrefix(hash, "$argon2id$"))

	ok, err := service.VerifyPassword("correct horse battery staple", hash)
	require.NoError(t, err)
	assert.True(t, ok)
}

func TestVerifyPasswordRejectsWrongPassword(t *testing.T) {
	hash, err := service.HashPassword("the-real-password")
	require.NoError(t, err)

	ok, err := service.VerifyPassword("not-the-password", hash)
	require.NoError(t, err)
	assert.False(t, ok)
}

func TestHashPasswordUsesFreshSalt(t *testing.T) {
	a, err := service.HashPassword("same-input")
	require.NoError(t, err)
	b, err := service.HashPassword("same-input")
	require.NoError(t, err)
	assert.NotEqual(t, a, b, "identical passwords must hash differently (random salt)")
}

func TestVerifyPasswordRejectsMalformedHash(t *testing.T) {
	_, err := service.VerifyPassword("x", "not-an-argon2-hash")
	assert.Error(t, err)
}
