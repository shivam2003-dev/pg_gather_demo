# ── Base image: official PostgreSQL 16 on Debian Bookworm slim ──────────────
FROM postgres:16-bookworm

# Install extra tools available inside the container
# - curl           : download pg_gather SQL script on first run
# - procps         : ps, top — useful for process inspection labs
# - less / vim     : read logs / configs interactively
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        procps \
        less \
        vim \
    && rm -rf /var/lib/apt/lists/*

# ── Custom postgresql.conf snippets ─────────────────────────────────────────
# Postgres merges every *.conf file found via include_dir at startup.
# Putting overrides here keeps changes visible and version-controlled.
COPY conf.d/ /etc/postgresql/conf.d/

# ── Custom pg_hba.conf ───────────────────────────────────────────────────────
# We copy it to a stable path; docker-compose passes -c hba_file= to use it.
COPY pg_hba.conf /etc/postgresql/pg_hba.conf

# ── Initialization scripts ───────────────────────────────────────────────────
# Any *.sql or *.sh in docker-entrypoint-initdb.d/ runs once, in filename
# order, when the data directory is first created.
COPY initdb/ /docker-entrypoint-initdb.d/

# Default port (documentation only — docker-compose sets the real mapping)
EXPOSE 5432
