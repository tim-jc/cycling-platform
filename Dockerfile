FROM rocker/r-ver:4.4.3

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

CMD ["Rscript", "run_daily_platform.R", "scheduled"]
