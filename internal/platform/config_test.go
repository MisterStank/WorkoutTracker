package platform_test

import (
	"testing"

	"gymon/internal/platform"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestLoadConfigDefaults(t *testing.T) {
	// t.Setenv arranges cleanup; an empty value falls back to the default.
	for _, k := range []string{"PORT", "DATABASE_URL", "REDIS_URL", "JWT_SECRET", "APP_ENV", "ALLOWED_ORIGINS"} {
		t.Setenv(k, "")
	}

	cfg, err := platform.LoadConfig()
	require.NoError(t, err)

	assert.Equal(t, "8080", cfg.Port)
	assert.Contains(t, cfg.DatabaseURL, "postgres://")
	assert.Equal(t, "redis://localhost:6379", cfg.RedisURL)
	assert.Equal(t, "dev-secret-change-me", cfg.JWTSecret)
	assert.Equal(t, []string{"http://localhost:*", "http://127.0.0.1:*"}, cfg.AllowedOrigins)
}

func TestLoadConfigReadsEnv(t *testing.T) {
	t.Setenv("PORT", "9000")
	t.Setenv("JWT_SECRET", "a-real-secret")
	t.Setenv("APP_ENV", "production")
	t.Setenv("ALLOWED_ORIGINS", "https://app.example.com, https://www.example.com ,")

	cfg, err := platform.LoadConfig()
	require.NoError(t, err)

	assert.Equal(t, "9000", cfg.Port)
	assert.Equal(t, "a-real-secret", cfg.JWTSecret)
	// trailing empty segment dropped, surrounding whitespace trimmed
	assert.Equal(t, []string{"https://app.example.com", "https://www.example.com"}, cfg.AllowedOrigins)
}

func TestLoadConfigAllowsDevSecretInDevelopment(t *testing.T) {
	t.Setenv("JWT_SECRET", "")
	t.Setenv("APP_ENV", "development")

	cfg, err := platform.LoadConfig()
	require.NoError(t, err)
	assert.Equal(t, "dev-secret-change-me", cfg.JWTSecret)
}

func TestLoadConfigRejectsDevSecretOutsideDevelopment(t *testing.T) {
	t.Setenv("JWT_SECRET", "")
	t.Setenv("APP_ENV", "production")

	_, err := platform.LoadConfig()
	assert.ErrorIs(t, err, platform.ErrInsecureJWTSecret)
}

func TestLoadConfigRejectsPlaceholderSecretOutsideDevelopment(t *testing.T) {
	t.Setenv("JWT_SECRET", "dev-secret-change-me")
	t.Setenv("APP_ENV", "staging")

	_, err := platform.LoadConfig()
	assert.ErrorIs(t, err, platform.ErrInsecureJWTSecret)
}
