# Builds the Flutter web bundle and serves it via nginx. Build with
# --build-arg API_URL=https://<your-api-host>/graphql pointed at the deployed
# backend — the default below only works for a local docker-compose setup.
#
# Installs the Flutter SDK directly from Google's official archive rather
# than a third-party prebuilt image, so the version is pinned exactly and
# doesn't depend on some other image staying fresh. Keep FLUTTER_VERSION in
# sync with the version this project is developed against.
FROM debian:bookworm-slim AS build
ARG FLUTTER_VERSION=3.47.0
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl xz-utils git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    -o /tmp/flutter.tar.xz \
    && tar -xJf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz
ENV PATH="/opt/flutter/bin:${PATH}"
RUN git config --global --add safe.directory /opt/flutter \
    && flutter config --no-analytics && flutter precache --web

WORKDIR /app
COPY . .
ARG API_URL=http://localhost:8080/graphql
RUN flutter pub get
# Generate Drift/build_runner code (app_database.g.dart etc.) — these files are
# not committed, so without this step the web compile fails with
# "Error reading 'lib/core/offline/app_database.g.dart'". Mirrors CI (.github/workflows/mobile.yml).
RUN dart run build_runner build --delete-conflicting-outputs
RUN flutter build web --release --dart-define=API_URL=${API_URL} --base-href /

FROM nginx:alpine
ENV PORT=80
COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
EXPOSE 80
