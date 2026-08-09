#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILE="$ROOT/Dockerfile"

grep -q 'RENV_CONFIG_CACHE_ENABLED=FALSE' "$DOCKERFILE"
grep -q 'HOME=/tmp' "$DOCKERFILE"
grep -q 'TMPDIR=/tmp' "$DOCKERFILE"
grep -q 'dir.create(project_library, recursive = TRUE' "$DOCKERFILE"
grep -q 'renv::lockfile_read("renv.lock")' "$DOCKERFILE"
grep -Fq "renv::install(paste0(\"renv@\", lock\$Packages\$renv\$Version)" "$DOCKERFILE"
grep -q 'renv::restore(library = project_library' "$DOCKERFILE"
grep -q 'find /opt/cycling-platform-library -type l' "$DOCKERFILE"
grep -q 'chmod -R a+rX /opt/cycling-platform-library' "$DOCKERFILE"
grep -q 'CYCLING_PLATFORM_FAILURE_NOTIFICATION_SENT' "$ROOT/run_daily_platform.R"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  image="cycling-platform-nonroot-test:local"
  docker build --tag "$image" "$ROOT"
  runtime_output="$(docker run --rm --network none --user 1000:1000 --entrypoint Rscript "$image" \
    -e 'stopifnot(requireNamespace("renv", quietly = TRUE)); stopifnot(all(vapply(c("DBI", "dplyr", "httr2", "jsonlite"), requireNamespace, logical(1), quietly = TRUE))); lock <- jsonlite::read_json("renv.lock"); stopifnot(identical(as.character(packageVersion("renv")), lock$Packages$renv$Version)); stopifnot(startsWith(find.package("renv"), "/opt/cycling-platform-library/")); stopifnot(file.access("/opt/cycling-platform", 2L) != 0L); stopifnot(identical(Sys.getenv("HOME"), "/tmp"), startsWith(normalizePath(tempdir(check = TRUE)), "/tmp/")); temporary <- tempfile(); writeLines("ok", temporary); stopifnot(file.exists(temporary)); cat(as.character(packageVersion("renv")), "\n")' 2>&1)"
  printf '%s\n' "$runtime_output"
  if grep -q 'Bootstrapping renv' <<<"$runtime_output"; then
    printf '%s\n' 'non-root runtime unexpectedly attempted to bootstrap renv' >&2
    exit 1
  fi

  docker run --rm --network none --user 1000:1000 \
    --tmpfs /run/cycling-platform:rw,uid=1000,gid=1000,mode=0700 \
    --entrypoint sh "$image" -c '
      credential=/run/cycling-platform/runtime.Renviron
      printf "%s\n" "STRAVA_REFRESH_TOKEN=before" "GOOGLE_HEALTH_REFRESH_TOKEN=preserve" > "$credential"
      chmod 0600 "$credential"
      export R_ENVIRON_USER="$credential"
      Rscript -e "source(\"bootstrap.R\"); update_renviron(STRAVA_REFRESH_TOKEN = \"after\")"
      test "$(stat -c "%u:%g" "$credential")" = "1000:1000"
      test "$(stat -c "%a" "$credential")" = "600"
      grep -q "^STRAVA_REFRESH_TOKEN=after$" "$credential"
      grep -q "^GOOGLE_HEALTH_REFRESH_TOKEN=preserve$" "$credential"
    '
else
  printf '%s\n' 'non-root image integration test: skipped (Docker daemon unavailable)'
fi

printf '%s\n' 'Dockerfile non-root runtime contract tests: passed'
