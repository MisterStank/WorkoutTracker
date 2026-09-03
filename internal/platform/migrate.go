package platform

import (
	"errors"
	"fmt"
	"strings"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/pgx/v5"
	"github.com/golang-migrate/migrate/v4/source/iofs"

	appmigrations "gymon/migrations"
)

// RunMigrations applies every pending migration embedded in the binary
// against databaseURL, and is a no-op once the schema is current. The API
// calls this at boot: Render deploys the Dockerfile with no separate release
// step, so the running binary has to carry its own schema changes.
func RunMigrations(databaseURL string) error {
	src, err := iofs.New(appmigrations.FS, ".")
	if err != nil {
		return fmt.Errorf("load embedded migrations: %w", err)
	}
	defer src.Close()

	m, err := migrate.NewWithSourceInstance("iofs", src, migrateURL(databaseURL))
	if err != nil {
		return fmt.Errorf("init migrator: %w", err)
	}
	// Only the source needs closing here; the database handle is opened from
	// a URL string and closed by m.Close().
	defer m.Close()

	if err := m.Up(); err != nil && !errors.Is(err, migrate.ErrNoChange) {
		return fmt.Errorf("apply migrations: %w", err)
	}
	return nil
}

// migrateURL rewrites a standard postgres:// connection string to the pgx5://
// scheme the golang-migrate pgx/v5 driver registers itself under, leaving any
// other scheme untouched.
func migrateURL(u string) string {
	for _, prefix := range []string{"postgres://", "postgresql://"} {
		if rest, ok := strings.CutPrefix(u, prefix); ok {
			return "pgx5://" + rest
		}
	}
	return u
}
