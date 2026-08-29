package repository_test

// Integration tests for the Postgres repository layer — see package dbtest
// for how the database is provisioned (CI service container, or an ephemeral
// embedded Postgres locally). Each test creates its own user with a unique
// email and only touches its own rows, so tests are independent without
// truncating between them.

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"workouttracker/internal/dbtest"
	"workouttracker/internal/domain"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestMain(m *testing.M) {
	dbtest.Start()
	code := m.Run()
	dbtest.Stop()
	os.Exit(code)
}

// --- shared helpers --------------------------------------------------------

func requireDB(t *testing.T) *pgxpool.Pool { return dbtest.Pool(t) }

// makeUser inserts a throwaway user and returns it.
func makeUser(t *testing.T, pool *pgxpool.Pool) *domain.User {
	t.Helper()
	u := &domain.User{
		ID:           uuid.New(),
		Email:        fmt.Sprintf("u-%s@test.local", uuid.NewString()),
		PasswordHash: "$argon2id$v=19$m=65536,t=3,p=2$YWJjZGVmZ2hpamtsbW5vcA$c29tZS1oYXNoLXZhbHVlLXBhZGRlZC1vdXQtMzI",
		DisplayName:  "Test User",
		Timezone:     "UTC",
		CreatedAt:    time.Now(),
	}
	_, err := pool.Exec(context.Background(),
		`INSERT INTO users (id, email, password_hash, display_name, timezone, created_at) VALUES ($1,$2,$3,$4,$5,$6)`,
		u.ID, u.Email, u.PasswordHash, u.DisplayName, u.Timezone, u.CreatedAt)
	if err != nil {
		t.Fatalf("makeUser: %v", err)
	}
	return u
}

// anyExerciseID returns the id of a seeded catalog exercise by name.
func anyExerciseID(t *testing.T, pool *pgxpool.Pool, name string) uuid.UUID {
	t.Helper()
	var id uuid.UUID
	if err := pool.QueryRow(context.Background(),
		`SELECT id FROM exercises WHERE name = $1`, name).Scan(&id); err != nil {
		t.Fatalf("anyExerciseID(%q): %v", name, err)
	}
	return id
}

// makeActiveWorkout inserts an in-progress workout for the user.
func makeActiveWorkout(t *testing.T, pool *pgxpool.Pool, userID uuid.UUID) *domain.Workout {
	t.Helper()
	w := &domain.Workout{ID: uuid.New(), UserID: userID, StartedAt: time.Now(), Status: domain.WorkoutInProgress}
	_, err := pool.Exec(context.Background(),
		`INSERT INTO workouts (id, user_id, started_at, status) VALUES ($1,$2,$3,$4)`,
		w.ID, w.UserID, w.StartedAt, w.Status)
	if err != nil {
		t.Fatalf("makeActiveWorkout: %v", err)
	}
	return w
}
