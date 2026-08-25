# WorkoutTracker

A workout tracker that adapts to user progress. Flutter mobile client, Go/GraphQL backend, Postgres, Redis.

For what the app does and how to use it, see [docs/USER_GUIDE.md](docs/USER_GUIDE.md).

## Stack

- **Mobile**: Flutter, Riverpod, Drift (offline-first local storage)
- **Backend**: Go, gqlgen (GraphQL), sqlc, pgx
- **Database**: Postgres
- **Cache / pub-sub**: Redis
- **CI/CD**: GitHub Actions (lint/test) → Render (auto-deploy on push to `main`)
- **Hosting**: Render (API + Postgres + Redis + web bundle)

## Backend — local development

Requires Go 1.25+ and Docker (for Postgres/Redis).

```bash
cp .env.example .env
docker compose up -d postgres redis

# run migrations (requires golang-migrate: https://github.com/golang-migrate/migrate)
migrate -database "$DATABASE_URL" -path migrations up

go run ./cmd/api
# GraphQL playground: http://localhost:8080/playground
```

Run tests:

```bash
go test ./...
```

Regenerate GraphQL resolvers/models after editing `internal/graphql/schema.graphql`:

```bash
go run github.com/99designs/gqlgen generate
```

## Mobile — local development

See `mobile/README.md` (added when the Flutter app is scaffolded in Phase 1 mobile work).

## Build order

1. **Auth** — signup/login/refresh/logout (this phase)
2. **Workout tracking** — log workouts, sets, exercises, PRs
3. **Analytics** — progress over time, real-time dashboard
