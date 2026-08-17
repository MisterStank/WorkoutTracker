---
name: workouttracker
description: Project context for WorkoutTracker — what it is, its stack, how to set up/run/build/test the backend and mobile app, and the repo's directory structure. Use when working on this repo (backend, mobile, migrations, CI/CD, or architecture questions).
---

# WorkoutTracker

A workout tracker that adapts to user progress. Built as a deep, portfolio-grade
full-stack project — not a shallow CRUD app — deliberately demonstrating SOLID
design, caching, scalability, query optimization, real-time analytics, and a
proper CI/CD pipeline.

Build order (do not skip ahead): **auth → workout tracking → analytics**.
Full architecture rationale and phased roadmap: `PLAN.md` at repo root.

## What it does

- Users sign up / log in (JWT + rotating refresh tokens).
- Users log workouts: exercises, sets, reps, weight, RPE.
- The app tracks personal records automatically as sets are logged.
- Analytics show progress over time (volume trends, PRs) with real-time updates
  when a new workout is logged.
- Mobile-first, offline-capable: an active workout session works without
  connectivity and syncs when back online.

## Tech stack

| Layer | Choice | Why (see PLAN.md for full rationale) |
|---|---|---|
| Mobile | Flutter | Cross-platform client |
| Mobile state | Riverpod | Compile-time safety, native async, testable |
| Mobile offline store | Drift (SQLite) | Local-first workout logging in a gym with poor signal |
| Mobile GraphQL client | graphql_flutter | Talks to the Go API |
| Backend language | Go | |
| API | GraphQL via gqlgen (schema-first codegen) | |
| DB access | sqlc-style raw SQL via pgx (hand-written repos) | Keeps SQL visible/tunable for query optimization |
| Database | PostgreSQL | Window functions, JSONB, TimescaleDB upgrade path |
| Cache / pub-sub | Redis | Analytics cache, refresh-token cache, rate limiting, subscription fan-out |
| Migrations | golang-migrate | `migrations/*.up.sql` / `*.down.sql` |
| Containerization | Docker / docker-compose | |
| CI/CD | GitHub Actions → GHCR → Fly.io | `.github/workflows/api.yml`, `.github/workflows/mobile.yml` |
| Auth | JWT access tokens (15m) + hashed, rotating refresh tokens (30d), argon2id password hashing | |

## Repo structure

```
WorkoutTracker/
├── PLAN.md                       full architecture + phased roadmap (source of truth)
├── README.md                     quick-start instructions
├── go.mod / go.sum                Go module (module path: workouttracker)
├── gqlgen.yml                     gqlgen codegen config
├── docker-compose.yml             local Postgres + Redis + api
├── Dockerfile                     backend container build
├── fly.toml                       Fly.io deploy config (release_command runs migrations)
├── .env.example                   env vars the backend reads
│
├── cmd/api/main.go                composition root: wires config, DB pool, services, GraphQL handler, chi router
│
├── internal/
│   ├── domain/                    entities + repository interfaces (no framework deps)
│   │   ├── user.go                User, RefreshToken, UserRepository, RefreshTokenRepository interfaces
│   │   └── errors.go              sentinel domain errors (ErrEmailTaken, ErrInvalidCredentials, ...)
│   ├── service/                   business logic — depends only on domain interfaces
│   │   ├── auth_service.go        SignUp / Login / Refresh / Logout / LogoutAllDevices / UserByID
│   │   ├── auth_service_test.go   unit tests against in-memory fakes (no DB needed)
│   │   ├── password.go            argon2id hash + verify
│   │   └── token.go               JWT issue/parse, opaque refresh-token generation + hashing
│   ├── repository/                Postgres implementations of domain interfaces (pgx)
│   │   ├── user_repository.go
│   │   └── refresh_token_repository.go
│   ├── graphql/                   gqlgen: schema, generated code, thin resolvers
│   │   ├── schema.graphql         source of truth — edit this, then regenerate
│   │   ├── generated.go           gqlgen output — do not hand-edit
│   │   ├── models_gen.go          gqlgen output — do not hand-edit
│   │   └── resolver.go            hand-written: translates GraphQL <-> AuthService, no business logic
│   ├── middleware/
│   │   └── auth.go                parses Authorization: Bearer, injects user ID into context
│   └── platform/                  cross-cutting infra
│       ├── config.go              env-driven Config struct
│       └── db.go                  pgxpool constructor
│
├── migrations/
│   ├── 0001_init_users_and_auth.up.sql     users, refresh_tokens tables + indexes
│   └── 0001_init_users_and_auth.down.sql
│
├── mobile/                        Flutter app (package name: mobile)
│   ├── lib/
│   │   ├── main.dart              ProviderScope root, AuthGate (routes login vs. authenticated home)
│   │   ├── core/
│   │   │   ├── graphql/graphql_client.dart   builds GraphQLClient, attaches access token per-request
│   │   │   └── storage/token_storage.dart    flutter_secure_storage wrapper for JWT tokens
│   │   └── features/auth/
│   │       ├── auth_state.dart               sealed AuthState (Unauthenticated/Authenticating/Authenticated/Error)
│   │       ├── auth_repository.dart          raw GraphQL mutations (signup/login/refresh/logout)
│   │       ├── auth_provider.dart            Riverpod providers + AuthNotifier (StateNotifier)
│   │       └── login_screen.dart             login UI
│   ├── test/widget_test.dart      widget test for LoginScreen
│   └── pubspec.yaml                riverpod, graphql_flutter, flutter_secure_storage, drift, connectivity_plus
│
└── .github/workflows/
    ├── api.yml                    lint → unit test → integration test (Postgres service container) →
    │                               docker build → push GHCR → deploy staging (Fly.io)
    └── mobile.yml                 flutter analyze → flutter test → flutter build apk --debug
```

## Setup

Prereqs: Go 1.25+, Docker, Flutter (stable channel).

```bash
git clone <repo> && cd WorkoutTracker
cp .env.example .env
docker compose up -d postgres redis

# install golang-migrate if you don't have it:
# https://github.com/golang-migrate/migrate
migrate -database "$DATABASE_URL" -path migrations up
```

## Run

Backend:
```bash
go run ./cmd/api
# GraphQL playground: http://localhost:8080/playground
# health check:       http://localhost:8080/healthz
```

Mobile (from `mobile/`):
```bash
flutter pub get
flutter run --dart-define=API_URL=http://localhost:8080/graphql
```

Or run everything (Postgres + Redis + api) via Docker:
```bash
docker compose up --build
```

## Build

Backend production image:
```bash
docker build -t workouttracker-api .
```

Mobile release build:
```bash
cd mobile && flutter build apk --release   # or: flutter build ios / flutter build web
```

## Test

Backend:
```bash
go test ./...                 # unit + integration (integration tests need a real Postgres — see .github/workflows/api.yml)
go vet ./...
gofmt -l .                    # should print nothing
```

Mobile (from `mobile/`):
```bash
flutter analyze
flutter test
```

## Working on the GraphQL API

Edit `internal/graphql/schema.graphql`, then regenerate:
```bash
go run github.com/99designs/gqlgen generate
```
This rewrites `generated.go` and `models_gen.go` and adds stub methods to
`resolver.go` for new fields — implement those stubs by calling into
`internal/service`, never by putting SQL or business logic directly in the resolver.

## Working on the database

Add a new migration pair (`NNNN_description.up.sql` / `.down.sql`) under
`migrations/`, following the numbering already there. Never edit a migration
that's already been applied anywhere — add a new one instead.

## Conventions to preserve

- **Layering**: `domain` defines interfaces, `service` holds business logic
  and depends only on those interfaces, `repository` implements them against
  Postgres, `graphql` resolvers stay thin (parse input → call service → map
  output). Don't put SQL or business rules in resolvers.
- **Testing**: business logic gets unit tests against in-memory fakes
  (see `auth_service_test.go` for the pattern); DB-touching code gets
  integration tests. Don't chase coverage on gqlgen-generated files.
- **Auth**: refresh tokens are stored hashed and rotate on every use — never
  store a refresh token in plaintext or reuse one after it's been redeemed.
- **CI/CD**: both workflows must stay green; the API workflow only builds/pushes/
  deploys on `main`, PRs only run lint/unit/integration tests.

## Current status / what's next

Phase 1 (auth) is scaffolded and working end-to-end: signup, login, refresh
(with rotation), logout, `me`, backed by real Postgres repositories, covered
by unit tests, with both CI/CD pipelines wired up. Phase 2 (workout tracking:
exercises, workouts, sets, PR detection) is next — see `PLAN.md` section 11
for its scope before starting.
