FROM rocker/r-ver:4.4.3

# Authoritative Linux runtime for local ARM64 portability tests and ephemeral
# production jobs on cycling-prod. Keep every system and shell dependency used
# by runtime code here; rsync is required by the native compatibility wrappers.
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Europe/London \
    LANG=en_GB.UTF-8 \
    LC_ALL=en_GB.UTF-8

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

RUN Rscript -e \
    'install.packages("renv", repos = "https://cloud.r-project.org"); renv::restore(prompt = FALSE)'

COPY . .

RUN mkdir -p logs backups

# docker compose run --rm cycling-platform uses this scheduled incremental
# command. Bootstrap, backfill, repair, and deep validation override CMD.
CMD ["Rscript", "run_daily_platform.R", "scheduled"]
