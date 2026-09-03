# Gymon — mobile client

The Flutter client for Gymon (package name `gymon`). Talks to the Go/GraphQL
backend in the repo root.

- Project overview and backend setup: [`../README.md`](../README.md)
- What the app does, screen by screen: [`../docs/USER_GUIDE.md`](../docs/USER_GUIDE.md)

## Run

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # regenerates gitignored Drift code
flutter run --dart-define=API_URL=http://localhost:8080/graphql
```

## Test

```bash
flutter analyze
flutter test
```
