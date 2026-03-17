# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A self-contained PostgreSQL diagnostic learning lab that uses [pg_gather](https://github.com/jobinau/pg_gather) to generate interactive HTML performance reports. It seeds a realistic e-commerce database with intentional performance problems for hands-on PostgreSQL diagnostics training.

## Commands

```bash
# Start the PostgreSQL database (first boot seeds ~300k rows, takes ~30–45s)
docker compose up postgres -d

# Generate a pg_gather report (one-shot; exits after completion)
docker compose run --rm pg_gather

# Open the latest HTML report
open reports/report_*.html                    # macOS
cd reports && python3 -m http.server 8080     # any OS → http://localhost:8080

# Open an interactive psql session against the lab database
docker exec -it pg_gather_db psql -U pgadmin -d labdb

# Open a shell inside the pg_gather runner container
docker compose run --rm pg_gather bash

# Rebuild images after any Dockerfile change
docker compose build

# Tear down (preserves named volume / data)
docker compose down

# Full reset — delete all data, re-seeds on next up
docker compose down -v
```

Reports are written to `reports/` as both `.tsv` (raw diagnostics) and `.html` (interactive browser report).

## Architecture

Two Docker services orchestrated by `docker-compose.yml`:

**postgres** — PostgreSQL 16 database (persistent named volume)
- `postgres/initdb/` scripts run once on first boot:
  - `00_config.sh` — appends `include_dir` for conf.d to `postgresql.conf`
  - `01_extensions.sql` — creates `pg_stat_statements`, `pg_buffercache`, `pg_prewarm`
  - `02_seed.sql` — e-commerce schema with ~300 k rows (users, products, orders, order_items, inventory)
  - `03_problems.sql` — intentional performance problems: table bloat, missing indexes, duplicate indexes, wide table, dead tuples, slow-query simulation function
- `postgres/conf.d/custom.conf` — tuning for the lab (shared_buffers, logging, autovacuum, WAL)
- `postgres/pg_hba.conf` — allows trust locally, scram-sha-256 over Docker bridge networks

**pg_gather** (one-shot runner)
- `pg_gather/Dockerfile` — clones pg_gather from GitHub at image build time
- `pg_gather/setup.sh` — entry point; two-stage pipeline:
  1. Runs `gather.sql` against `labdb` → produces a timestamped `.tsv` file
  2. Creates a temporary work DB, imports the TSV, runs `gather_report.sql` → produces a timestamped `.html` report, then drops the work DB

## Environment Configuration

Copy `.env.example` to `.env` and adjust as needed. Key variables:

| Variable | Purpose |
|---|---|
| `POSTGRES_USER` / `POSTGRES_PASSWORD` | Superuser credentials |
| `POSTGRES_DB` | Name of the lab database (`labdb`) |
| `POSTGRES_PORT` | Host port mapped to 5432 |
| `PG_CONTAINER` | Name given to the postgres container |
| `PG_DATA_VOLUME` | Named Docker volume for data persistence |

## Intentional Performance Problems

`03_problems.sql` creates these for diagnostic exercises:

1. **`bloat_demo`** — autovacuum disabled; dead tuples left behind
2. **`events`** — 200 k rows, no index on `user_id` or `event_type`
3. **`search_log`** — three duplicate indexes on the same column
4. **`wide_audit_log`** — 34-column table demonstrating I/O bloat
5. Dead tuples in `bloat_demo` (50 k inserts then deletes, no vacuum run)
6. **`simulate_slow_query()`** — PL/pgSQL function to generate trackable slow queries

## Further Reading

Full guides live in `docs/`:
- [`docs/setup.md`](docs/setup.md) — prerequisites, first-boot walkthrough, troubleshooting
- [`docs/generating-reports.md`](docs/generating-reports.md) — all commands to produce and view HTML reports
- [`docs/connect-external-db.md`](docs/connect-external-db.md) — run pg_gather against any PostgreSQL database
- [`docs/performance-problems.md`](docs/performance-problems.md) — what each intentional problem is and how to spot it in the report
- [`docs/postgres-config.md`](docs/postgres-config.md) — every tuning knob in `custom.conf` and which report section it affects
