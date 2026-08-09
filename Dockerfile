FROM rocker/r-ver:4.4.3

# Authoritative Linux runtime for local ARM64 portability tests and ephemeral
# production jobs on cycling-prod. Keep every system and shell dependency used
# by runtime code here; rsync is required by the native compatibility wrappers.
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Europe/London \
    LANG=en_GB.UTF-8 \
    LC_ALL=en_GB.UTF-8 \
    HOME=/tmp \
    TMPDIR=/tmp \
    RENV_PATHS_LIBRARY=/opt/cycling-platform-library \
    RENV_CONFIG_CACHE_ENABLED=FALSE

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        libcurl4-openssl-dev \
        libmariadb-dev \
        libssl-dev \
        libuv1-dev \
        locales \
        rsync \
        tzdata \
    && sed -i '/en_GB.UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/cycling-platform

# Restore dependencies before copying the application.
# This layer will be reused until renv.lock changes.
COPY renv.lock ./
COPY .Rprofile ./
COPY renv/ ./renv/

RUN Rscript --vanilla -e \
    'install.packages("renv", repos = "https://cloud.r-project.org"); lock <- renv::lockfile_read("renv.lock"); project_library <- renv::paths$library(); dir.create(project_library, recursive = TRUE, showWarnings = FALSE); renv::install(paste0("renv@", lock$Packages$renv$Version), library = project_library); renv::restore(library = project_library, prompt = FALSE); description <- read.dcf(file.path(project_library, "renv", "DESCRIPTION")); stopifnot(identical(unname(description[1, "Version"]), lock$Packages$renv$Version))' \
    && test -z "$(find /opt/cycling-platform-library -type l -print -quit)" \
    && chmod -R a+rX /opt/cycling-platform-library

# renv's sandbox activation takes a filesystem lock in the R system library.
# That library is intentionally read-only for the production UID, so disable
# only the sandbox layer. Project activation and the immutable renv library
# remain enabled. R_LIBS_USER also exposes the same library to --vanilla checks.
ENV RENV_CONFIG_SANDBOX_ENABLED=FALSE \
    R_LIBS_USER=/opt/cycling-platform-library/linux-ubuntu-noble/R-4.4/aarch64-unknown-linux-gnu

COPY . .

RUN mkdir -p logs backups

# Run through the normal project startup so .Rprofile activates the locked renv
# library, matching production commands.
RUN Rscript tests/smoke_check.R

# docker compose run --rm cycling-platform uses this scheduled incremental
# command. Bootstrap, backfill, repair, and deep validation override CMD.
CMD ["Rscript", "run_daily_platform.R", "scheduled"]
