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
│   │   ├── workout.go             Exercise, Workout, WorkoutSet, PersonalRecord, WorkoutTemplate + their repo interfaces
│   │   ├── analytics.go           ProgressPoint, BodyMetric, ProgressRollupRepository, WorkoutEventPublisher
│   │   └── errors.go              sentinel domain errors (ErrEmailTaken, ErrWorkoutNotOwned, ErrTemplateNotOwned, ...)
│   ├── service/                   business logic — depends only on domain interfaces
│   │   ├── auth_service.go        SignUp / Login / Refresh / Logout / LogoutAllDevices / UserByID
│   │   ├── auth_service_test.go   unit tests against in-memory fakes (no DB needed)
│   │   ├── workout_service.go     start/log/finish workout, warm-up sets, templates, cursor-paginated history
│   │   ├── workout_service_test.go  unit tests against in-memory fakes
│   │   ├── workout_cursor.go      opaque cursor encode/decode for workoutHistory pagination
│   │   ├── analytics_service.go   progress/volume trend queries with Redis write-through caching
│   │   ├── analytics_service_test.go
│   │   ├── password.go            argon2id hash + verify
│   │   └── token.go               JWT issue/parse, opaque refresh-token generation + hashing
│   ├── repository/                Postgres implementations of domain interfaces (pgx)
│   │   ├── user_repository.go / refresh_token_repository.go
│   │   ├── exercise_repository.go / workout_repository.go / workout_set_repository.go
│   │   ├── workout_template_repository.go / personal_record_repository.go
│   │   ├── progress_rollup_repository.go / body_metric_repository.go
│   │   └── workout_set_repository.go's LogSet — the one method worth reading closely: inserts a set and,
│   │       in the SAME transaction, atomically upserts personal_records (ON CONFLICT ... WHERE value <
│   │       EXCLUDED.value) and progress_daily_rollup — this is how PR/rollup correctness holds up under
│   │       concurrent writes without a separate lock
│   ├── graphql/                   gqlgen: schema, generated code, thin resolvers
│   │   ├── schema.graphql         source of truth — edit this, then regenerate
│   │   ├── generated.go           gqlgen output — do not hand-edit
│   │   ├── models_gen.go          gqlgen output — do not hand-edit
│   │   └── resolver.go            hand-written: translates GraphQL <-> services, no business logic.
│   │                               NOTE: gqlgen regenerate WIPES the Resolver struct's fields and any
│   │                               free-standing helper functions (toXModel etc.) on every run, keeping
│   │                               only recognized resolver methods — always re-paste those back in full
│   │                               after regenerating, don't try to preserve them via diffing.
│   ├── middleware/auth.go         parses Authorization: Bearer (HTTP) / connection_init payload (WS),
│   │                               injects user ID into context; WithUserID() for non-HTTP-middleware paths
│   ├── cache/redis_cache.go       generic Redis JSON cache (Get/Set/Delete) used by AnalyticsService
│   ├── realtime/redis_event_bus.go  Redis pub/sub fan-out for the workoutProgressUpdated GraphQL subscription
│   └── platform/                  cross-cutting infra
│       ├── config.go              env-driven Config struct
│       ├── db.go                  pgxpool constructor
│       └── redis.go               go-redis client constructor
│
├── cmd/seed/main.go               `go run ./cmd/seed` — wipes/recreates a demo account
│                                    (demo@workouttracker.app / demo12345) with 6 weeks of realistic
│                                    progressive-overload history, so every screen has real data to look at
│
├── migrations/                    0001 users/auth · 0002 exercises/workouts/sets/PRs (seeded exercise
│                                    catalog) · 0003 body_metrics/progress_daily_rollup · 0004 is_warmup
│                                    flag on workout_sets · 0005 workout_templates + workouts.template_id
│
├── mobile/                        Flutter app (package name: mobile)
│   ├── lib/
│   │   ├── main.dart              ProviderScope root, AuthGate (routes login vs. authenticated home)
│   │   ├── core/
│   │   │   ├── graphql/graphql_client.dart   HttpLink+AuthLink for queries/mutations, split to a
│   │   │   │                                  WebSocketLink for subscriptions (auth via connection_init,
│   │   │   │                                  not a header — WS handshakes can't carry one)
│   │   │   ├── storage/                       token_storage.dart (JWTs), recent_exercises_storage.dart
│   │   │   ├── units/                          WeightUnit (kg/lb) + persisted preference provider —
│   │   │   │                                    backend always stores/transmits kg, conversion is client-only
│   │   │   └── offline/                        Drift-backed outbox for logSet specifically (the one write
│   │   │       ├── app_database.dart            that actually happens at the gym with bad signal), not a
│   │   │       ├── connection/                  general offline-first rewrite. `offlineQueueSupported` is
│   │   │       │   ├── connection_native.dart    false on web (conditional-imported: native.dart needs
│   │   │       │   └── connection_stub.dart      dart:io, unavailable there) — app_database.g.dart is
│   │   │       ├── offline_provider.dart         gitignored, regenerate via build_runner (see Run below)
│   │   │       └── sync_service.dart            drains the outbox on connectivity_plus reconnect events
│   │   └── features/
│   │       ├── auth/               signup/login screens, sealed AuthState, AuthNotifier (session restore
│   │       │                        on launch: try `me`, fall back to one refresh attempt)
│   │       ├── workout/            WorkoutHomeScreen (active workout: grouped-by-exercise sets, rest timer,
│   │       │                        PR banner, planned-exercise chips when started from a template),
│   │       │                        ExercisePickerScreen (search + locally-persisted recents),
│   │       │                        log_set_sheet.dart (reps/weight/RPE/warm-up, pre-filled from last set),
│   │       │                        workout_history_screen.dart (cursor-paginated), ActiveWorkoutNotifier
│   │       │                        (owns the offline-enqueue/reconcile logic + the live-subscription watch)
│   │       ├── templates/          TemplatesScreen (list/start/delete), CreateTemplateScreen — a workout
│   │       │                        started from a template carries workout.templateId
│   │       └── analytics/          AnalyticsScreen tabs: volume trend, per-exercise progress, body weight
│   │                                (fl_chart), all unit-aware
│   ├── test/widget_test.dart      widget tests for Login/Signup screens
│   └── pubspec.yaml                riverpod, graphql_flutter, flutter_secure_storage, drift, drift_dev,
│                                    connectivity_plus, fl_chart, gql
│
└── .github/workflows/
    ├── api.yml                    lint → unit test → integration test (Postgres service container) →
    │                               docker build → push GHCR → deploy staging (Fly.io)
    └── mobile.yml                 flutter pub get → dart run build_runner build (Drift codegen, required —
                                     app_database.g.dart is gitignored) → flutter analyze → flutter test →
                                     flutter build apk --debug
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
dart run build_runner build --delete-conflicting-outputs   # regenerates lib/core/offline/app_database.g.dart (Drift, gitignored)
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

Phases 1–3 from `PLAN.md` are built and verified end-to-end (including on a
real Android build, not just web): auth; workout tracking with atomic PR
detection and warm-up-set exclusion; analytics (Redis-cached progress/volume
trends, live GraphQL subscriptions over Redis pub/sub, body-weight
tracking). Beyond the original plan, a "make it actually usable" pass added:
last-weight memory, a rest timer, a kg/lb toggle, workout templates
(start a workout pre-populated with a planned exercise list), and an
offline-logging outbox for the log-set write path specifically.

Not yet done:
- **True offline-first beyond logSet** — starting/finishing a workout,
  templates, and login still require connectivity; only mid-workout set
  logging survives a dropped connection.
- **Differentiator ideas** (not started, discussed but deferred): RPE-based
  autoregulated progression suggestions, plateau detection, live shared
  training sessions (the pub/sub infra already exists for this).
- Verify the offline outbox against a *real* dropped connection (airplane
  mode on a device) — so far only reasoned through, not device-tested,
  since simulating true network loss isn't practical from this environment.
