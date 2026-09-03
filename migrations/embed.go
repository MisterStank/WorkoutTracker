// Package migrations embeds the SQL migration files into the binary so the
// API can apply them on boot (see internal/platform.RunMigrations). The
// embed directive has to live in the same directory as the .sql files it
// references, which is why this one-line package sits here.
package migrations

import "embed"

// FS holds every *.up.sql / *.down.sql file in this directory.
//
//go:embed *.sql
var FS embed.FS
