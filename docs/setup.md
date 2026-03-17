# Setup Guide

## Prerequisites

| Requirement | Minimum version | Check |
|---|---|---|
| Docker Desktop / Engine | 20.10+ | `docker --version` |
| Docker Compose plugin | 2.0+ | `docker compose version` |
| Free disk space | ~1 GB | for the named volume |

## Step-by-Step Installation

### 1. Clone the repository

```bash
git clone <repo-url>
cd pg_gather
```

### 2. Create your `.env` file

```bash
cp .env.example .env
```

Open `.env` and adjust as needed:

```dotenv
POSTGRES_USER=pgadmin
POSTGRES_PASSWORD=pgadmin123
POSTGRES_DB=labdb
POSTGRES_PORT=5432          # host port — change if 5432 is already in use
PG_CONTAINER=pg_gather_db
PG_DATA_VOLUME=pg_gather_data
```

> **Note:** `PGHOST` inside the runner container always uses the container name (`pg_gather_db`), not `localhost`. You do not need to change this.

### 3. Build the images

The first build pulls base images and clones pg_gather from GitHub — typically 2–3 minutes on a fast connection.

```bash
docker compose build
```

### 4. Start the database

```bash
docker compose up postgres -d
```

On **first boot**, Docker runs the `initdb/` scripts in order:

| Script | What it does | Approx. time |
|---|---|---|
| `00_config.sh` | Wires `conf.d/` into `postgresql.conf` | < 1 s |
| `01_extensions.sql` | Creates `pg_stat_statements`, `pg_buffercache`, `pg_prewarm` | < 1 s |
| `02_seed.sql` | Inserts ~300 k rows of e-commerce data | ~20–30 s |
| `03_problems.sql` | Creates intentional performance problems | ~10–15 s |

Wait until the container is healthy before running the report:

```bash
docker compose ps
# STATUS should show "healthy"
```

Or watch the logs:

```bash
docker compose logs -f postgres
# Look for: "database system is ready to accept connections"
```

### 5. Generate your first report

```bash
docker compose run --rm pg_gather
```

The runner prints progress and exits cleanly:

```
[pg_gather] Waiting for PostgreSQL ...
[pg_gather] STAGE 1 — Running gather.sql against labdb ...
[pg_gather] STAGE 1 done in 3s — TSV: 13K
[pg_gather] STAGE 2 — Creating work database ...
[pg_gather] STAGE 2 — Generating HTML report ...
[pg_gather] HTML report generated in 8s
[pg_gather] HTML : /reports/report_20260317_124646.html
```

### 6. Open the report

```bash
open reports/report_*.html          # macOS
xdg-open reports/report_*.html      # Linux
start reports/report_*.html         # Windows (PowerShell)
```

Or serve it over HTTP:

```bash
cd reports && python3 -m http.server 8080
# Open http://localhost:8080
```

---

## Stopping and Cleaning Up

```bash
# Stop containers (data volume preserved)
docker compose down

# Stop containers AND delete all data (full reset)
docker compose down -v

# Remove built images too
docker compose down -v --rmi all
```

## Troubleshooting

**Port 5432 already in use**

Change `POSTGRES_PORT` in `.env` to an unused port (e.g. `5433`), then restart:

```bash
docker compose down && docker compose up postgres -d
```

**"pg_stat_statements extension not found" error**

The extension is created in `01_extensions.sql` which only runs on first boot. If you started with an old volume that pre-dates the extension setup, reset the volume:

```bash
docker compose down -v
docker compose up postgres -d
```

**Report HTML file is very small (< 5 KB)**

The runner validates size and warns you. Check logs:

```bash
docker compose logs pg_gather
```

Common causes: database was not yet healthy, or `gather.sql` timed out. Re-run after confirming the postgres container is `healthy`.
