package platform

import (
	"log"
	"os"
	"strings"
)

const devJWTSecret = "dev-secret-change-me"

type Config struct {
	Port           string
	DatabaseURL    string
	RedisURL       string
	JWTSecret      string
	AllowedOrigins []string
}

// LoadConfig reads all runtime config from the environment. Fatal-exits if
// JWT_SECRET is unset (or still the dev placeholder) outside local
// development, so a misconfigured production deploy fails loudly at boot
// rather than silently signing tokens with a well-known secret.
func LoadConfig() Config {
	jwtSecret := getEnv("JWT_SECRET", devJWTSecret)
	if jwtSecret == devJWTSecret && getEnv("APP_ENV", "development") != "development" {
		log.Fatal("JWT_SECRET must be set to a real secret when APP_ENV is not 'development'")
	}

	return Config{
		Port:           getEnv("PORT", "8080"),
		DatabaseURL:    getEnv("DATABASE_URL", "postgres://postgres:postgres@localhost:5432/workouttracker?sslmode=disable"),
		RedisURL:       getEnv("REDIS_URL", "redis://localhost:6379"),
		JWTSecret:      jwtSecret,
		AllowedOrigins: getEnvList("ALLOWED_ORIGINS", []string{"http://localhost:*", "http://127.0.0.1:*"}),
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// getEnvList parses a comma-separated env var into a trimmed slice, or
// returns fallback if the var is unset/empty.
func getEnvList(key string, fallback []string) []string {
	raw := os.Getenv(key)
	if raw == "" {
		return fallback
	}
	parts := strings.Split(raw, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if trimmed := strings.TrimSpace(p); trimmed != "" {
			out = append(out, trimmed)
		}
	}
	if len(out) == 0 {
		return fallback
	}
	return out
}
