# Gymon

Raise a virtual companion by training. Your pet hatches on your first workout, evolves through stages, and unlocks gear as you keep a streak — a Tamagotchi-style layer over a real workout tracker (adaptive progression, offline logging, live analytics). Flutter mobile client, Go/GraphQL backend, Postgres, Redis.

For what the app does and how to use it, see [docs/USER_GUIDE.md](docs/USER_GUIDE.md).

## Stack

- **Mobile**: Flutter, Riverpod, Drift (offline-first local storage)
- **Backend**: Go, gqlgen (GraphQL), pgx
- **Database**: Postgres
- **Cache / pub-sub**: Redis
- **CI/CD**: GitHub Actions (lint/test) → Render (auto-deploy on push to `main`)
- **Hosting**: Render (API + Postgres + Redis + web bundle)

## Quick Start: Launch Everything

### Prerequisites

- **Go** 1.25+
- **Flutter** (stable channel)
- **Docker** & **Docker Compose**
- **golang-migrate** ([install here](https://github.com/golang-migrate/migrate))

### Option 1: Everything via Docker Compose (Recommended for first-time setup)

Runs Postgres, Redis, and the API backend in containers. Mobile runs locally on your machine.

```bash
# 1. Clone and setup
git clone <repo> && cd gymon
cp .env.example .env
export $(grep -v '^#' .env | xargs)

# 2. Start database + Redis + API backend (all containerized)
docker compose up --build -d --wait

# 3. Run migrations
migrate -database "$DATABASE_URL" -path migrations up

# 4. Seed demo data
go run ./cmd/seed

# ✓ API is live at http://localhost:8080
# ✓ GraphQL playground: http://localhost:8080/playground
# ✓ Postgres: localhost:5432 (seeded with demo account)
# ✓ Redis: localhost:6379
```

In a **second terminal**, run the Flutter mobile app:

```bash
cd mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run --dart-define=API_URL=http://localhost:8080/graphql

```

Stop everything:
```bash
docker compose down
```

---

### Option 2: Full Local Development (Backend & services on your machine)

For more control and faster iteration when modifying the backend.

```bash
# 1. Clone and setup
git clone <repo> && cd gymon
cp .env.example .env
export $(grep -v '^#' .env | xargs)

# 2. Start Postgres + Redis (Docker only, no API)
docker compose up -d postgres redis

# 3. Run migrations
migrate -database "$DATABASE_URL" -path migrations up

# 4. Seed demo data (optional, but recommended)
go run ./cmd/seed
```

In **Terminal 1**, start the backend:

```bash
go run ./cmd/api

# ✓ GraphQL playground: http://localhost:8080/playground
# ✓ Health check:       http://localhost:8080/healthz
```

In **Terminal 2**, run the mobile app:

```bash
cd mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run --dart-define=API_URL=http://localhost:8080/graphql
```

---

## Development: Backend Only

If you're only working on the API:

```bash
cp .env.example .env
export $(grep -v '^#' .env | xargs)
docker compose up -d postgres redis
migrate -database "$DATABASE_URL" -path migrations up

go run ./cmd/api
# API: http://localhost:8080
# Playground: http://localhost:8080/playground
```

Test:
```bash
go test ./...
go vet ./...
gofmt -l .   # should print nothing
```

Regenerate GraphQL after editing `internal/graphql/schema.graphql`:
```bash
go run github.com/99designs/gqlgen generate
```

---

## Development: Mobile Only

If you're only working on the Flutter app, use the production API:

```bash
cd mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run --dart-define=API_URL=https://gymon-api.onrender.com/graphql
```

Test:
```bash
flutter analyze
flutter test
```

---

## Production Build

**Backend:**
```bash
docker build -t gymon-api .
```

**Mobile (Android APK):**
```bash
cd mobile && flutter build apk --release
```

**Mobile (iOS):**
```bash
cd mobile && flutter build ios
```

**Mobile (Web):**
```bash
cd mobile && flutter build web
```

---

## Working with the API

### Edit GraphQL schema
1. Edit `internal/graphql/schema.graphql`
2. Regenerate:
   ```bash
   go run github.com/99designs/gqlgen generate
   ```

### Add a database migration
1. Create a new numbered pair under `migrations/`:
   - `NNNN_description.up.sql`
   - `NNNN_description.down.sql`
2. Run migrations:
   ```bash
   migrate -database "$DATABASE_URL" -path migrations up
   ```

---

## Architecture

**Layering convention** (preserved to stay maintainable):
- `domain/` — entities and repository interfaces (no framework deps)
- `service/` — business logic, depends only on domain interfaces
- `repository/` — Postgres implementations via pgx
- `graphql/` — thin resolvers (parse input → call service → map output)

**Storage**:
- **Postgres** — primary data store (users, workouts, sets, PRs, templates)
- **Redis** — analytics cache (write-through), refresh-token cache, subscription fan-out
- **Drift (SQLite)** — mobile local store for offline workout logging

---

## Troubleshooting

**API won't start**: Check that Postgres and Redis are running.
```bash
docker compose ps   # should show postgres and redis as "Up"
```

**Migrations failed**: Verify `DATABASE_URL` in `.env` matches the running Postgres.
```bash
echo $DATABASE_URL   # should be something like: postgres://user:pass@localhost:5432/gymon
```

**Mobile can't connect to API**: Ensure the `API_URL` passed to `flutter run` matches your backend's GraphQL endpoint.

**Flutter build_runner fails**: Ensure you run `dart run build_runner build` (generates `lib/core/offline/app_database.g.dart`).

