// Package dbtest boots a real Postgres for the integration test suites in
// internal/repository and internal/graphql.
//
//   - In CI, DATABASE_URL points at the workflow's `postgres` service
//     container (.github/workflows/api.yml) — the harness reuses it and
//     applies migrations itself, so it also works against any empty DB.
//   - Locally, with no DATABASE_URL, it downloads and boots an ephemeral
//     embedded Postgres on a random port, so `go test ./...` just works with
//     no Docker. If that can't start (offline, unsupported platform) the
//     dependent tests skip rather than fail.
//
// A test package uses it from TestMain:
//
//	func TestMain(m *testing.M) {
//		reason := dbtest.Start()
//		code := m.Run()
//		dbtest.Stop()
//		if reason != "" { /* tests already skipped individually */ }
//		os.Exit(code)
//	}
package dbtest

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
	"time"

	embeddedpostgres "github.com/fergusstrange/embedded-postgres"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	pool       *pgxpool.Pool
	embedded   *embeddedpostgres.EmbeddedPostgres
	skipReason string
)

// Start brings up the database and applies migrations. It returns a non-empty
// reason if no database is available (in which case Pool skips callers).
func Start() string {
	ctx := context.Background()
	dbURL := os.Getenv("DATABASE_URL")

	if dbURL == "" {
		// A port unlikely to collide when `go test ./...` runs the repository
		// and graphql suites in parallel, each booting its own instance.
		port := uint32(20000 + (os.Getpid()*2749+int(time.Now().UnixNano()&0x3fff))%40000)
		runtimeDir, _ := os.MkdirTemp("", "wt-ep-*")
		embedded = embeddedpostgres.NewDatabase(
			embeddedpostgres.DefaultConfig().Port(port).RuntimePath(runtimeDir).Logger(nil),
		)
		if err := embedded.Start(); err != nil {
			embedded = nil
			skipReason = fmt.Sprintf("no DATABASE_URL and embedded Postgres won't start: %v", err)
			return skipReason
		}
		dbURL = fmt.Sprintf("postgres://postgres:postgres@localhost:%d/postgres?sslmode=disable", port)
	}

	p, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		skipReason = fmt.Sprintf("cannot connect to test database: %v", err)
		return skipReason
	}
	if err := applyMigrations(ctx, p); err != nil {
		skipReason = fmt.Sprintf("cannot apply migrations: %v", err)
		return skipReason
	}
	pool = p
	return ""
}

// Stop tears down anything Start created.
func Stop() {
	if pool != nil {
		pool.Close()
	}
	if embedded != nil {
		_ = embedded.Stop()
	}
}

// Pool returns the shared connection pool, skipping the test if no database
// is available.
func Pool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	if skipReason != "" {
		t.Skip(skipReason)
	}
	return pool
}

func applyMigrations(ctx context.Context, p *pgxpool.Pool) error {
	dir := migrationsDir()
	entries, err := os.ReadDir(dir)
	if err != nil {
		return err
	}
	var ups []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".up.sql") {
			ups = append(ups, e.Name())
		}
	}
	sort.Strings(ups)

	// Skip files already applied (a CI database migrated by the workflow),
	// so CREATE TYPE / CREATE TABLE don't error on the second run.
	_, _ = p.Exec(ctx, `CREATE TABLE IF NOT EXISTS _dbtest_migrations (name text PRIMARY KEY)`)
	applied := map[string]bool{}
	if rows, err := p.Query(ctx, `SELECT name FROM _dbtest_migrations`); err == nil {
		for rows.Next() {
			var n string
			_ = rows.Scan(&n)
			applied[n] = true
		}
		rows.Close()
	}
	// If the core schema already exists but nothing is tracked, assume the
	// database is fully migrated externally and only record that fact.
	var usersExists bool
	_ = p.QueryRow(ctx, `SELECT to_regclass('public.users') IS NOT NULL`).Scan(&usersExists)
	if usersExists && len(applied) == 0 {
		for _, name := range ups {
			_, _ = p.Exec(ctx, `INSERT INTO _dbtest_migrations (name) VALUES ($1) ON CONFLICT DO NOTHING`, name)
		}
		return nil
	}

	for _, name := range ups {
		if applied[name] {
			continue
		}
		b, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			return err
		}
		if _, err := p.Exec(ctx, string(b)); err != nil {
			return fmt.Errorf("%s: %w", name, err)
		}
		_, _ = p.Exec(ctx, `INSERT INTO _dbtest_migrations (name) VALUES ($1) ON CONFLICT DO NOTHING`, name)
	}
	return nil
}

// migrationsDir walks up from the test's working directory to the repo root
// (the dir containing go.mod) and returns its migrations/ path.
func migrationsDir() string {
	dir, _ := os.Getwd()
	for i := 0; i < 6; i++ {
		if _, err := os.Stat(filepath.Join(dir, "go.mod")); err == nil {
			return filepath.Join(dir, "migrations")
		}
		dir = filepath.Dir(dir)
	}
	return "migrations"
}
