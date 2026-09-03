package platform_test

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	embeddedpostgres "github.com/fergusstrange/embedded-postgres"
	"github.com/jackc/pgx/v5/pgxpool"

	"gymon/internal/platform"
)

// TestRunMigrations boots a throwaway Postgres, applies the embedded
// migrations against an empty database, and asserts a second call is a
// clean no-op. It skips (rather than fails) where embedded Postgres can't
// start, matching internal/dbtest.
func TestRunMigrations(t *testing.T) {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		port := uint32(20000 + (os.Getpid()*2749+int(time.Now().UnixNano()&0x3fff))%40000)
		runtimeDir, _ := os.MkdirTemp("", "wt-mig-*")
		ep := embeddedpostgres.NewDatabase(
			embeddedpostgres.DefaultConfig().Port(port).RuntimePath(runtimeDir).Logger(nil),
		)
		if err := ep.Start(); err != nil {
			t.Skipf("embedded Postgres won't start: %v", err)
		}
		defer func() { _ = ep.Stop() }()
		dbURL = fmt.Sprintf("postgres://postgres:postgres@localhost:%d/postgres?sslmode=disable", port)
	}

	if err := platform.RunMigrations(dbURL); err != nil {
		t.Fatalf("first RunMigrations: %v", err)
	}
	if err := platform.RunMigrations(dbURL); err != nil {
		t.Fatalf("second RunMigrations (should be no-op): %v", err)
	}

	pool, err := pgxpool.New(context.Background(), dbURL)
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	defer pool.Close()

	var petsExists bool
	if err := pool.QueryRow(context.Background(),
		`SELECT to_regclass('public.pets') IS NOT NULL`).Scan(&petsExists); err != nil {
		t.Fatalf("check pets table: %v", err)
	}
	if !petsExists {
		t.Fatal("pets table missing after migrations")
	}
}
