# Running pg_gather Against an External Database

You can point the pg_gather runner at **any** PostgreSQL database — your own dev server, staging, or (read-only) production — without touching your target database's configuration.

---

## Requirements on the Target Database

pg_gather only reads system catalog views and statistics. It needs:

1. **`pg_stat_statements` extension** loaded — this is the only hard requirement for full report data.
2. A superuser (or a role with `pg_monitor` membership in PostgreSQL 10+).

Check if `pg_stat_statements` is already loaded:

```sql
SELECT * FROM pg_extension WHERE extname = 'pg_stat_statements';
```

If it is missing, a superuser can install it:

```sql
-- Run as superuser
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
-- Restart PostgreSQL, then:
CREATE EXTENSION pg_stat_statements;
```

> Without `pg_stat_statements`, the report still generates but the "Top SQL" sections will be empty.

---

## Option 1 — Override Environment Variables at Runtime

Pass connection details directly to `docker compose run` without changing `.env`:

```bash
docker compose run --rm \
    -e PGHOST=your-db-host \
    -e PGPORT=5432 \
    -e PGUSER=your_superuser \
    -e PGPASSWORD=your_password \
    -e PGDATABASE=your_database_name \
    pg_gather
```

The HTML report is still written to your local `reports/` directory.

---

## Option 2 — Edit `.env` Temporarily

Update `.env` with your target database credentials, run the report, then restore your original values:

```dotenv
# Point at an external server
POSTGRES_USER=your_superuser
POSTGRES_PASSWORD=your_password
POSTGRES_DB=your_database_name
PG_CONTAINER=your-db-host     # host/IP reachable from inside Docker
```

Run the report:

```bash
docker compose run --rm pg_gather
```

> **Note:** `PG_CONTAINER` is used as `PGHOST` inside the runner. If your database is on the host machine, use `host.docker.internal` (macOS/Windows Docker Desktop) or the host's LAN IP.

---

## Option 3 — Run pg_gather Directly with psql (no Docker runner needed)

If you already have `psql` installed locally and the pg_gather scripts cloned, you can run both stages directly.

### Clone pg_gather

```bash
git clone https://github.com/jobinau/pg_gather.git /tmp/pg_gather
```

### Stage 1 — Collect data

```bash
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TSV_FILE="./reports/gather_${TIMESTAMP}.tsv"

psql \
    "postgresql://your_superuser:your_password@your-db-host:5432/your_database" \
    -X -q -A -t \
    -f /tmp/pg_gather/gather.sql \
    > "$TSV_FILE"
```

### Stage 2 — Generate report

Stage 2 needs a **separate** writable PostgreSQL instance to import the TSV and render HTML. This can be a local PostgreSQL, the lab postgres container, or any PostgreSQL 12+ instance.

```bash
WORK_DB="pg_gather_work_${TIMESTAMP}"
REPORT_FILE="./reports/report_${TIMESTAMP}.html"

# Create work DB on your writable instance
psql "postgresql://pgadmin:pgadmin123@localhost:5432/postgres" \
    -c "CREATE DATABASE ${WORK_DB};"

# Import TSV and generate report
{ cat /tmp/pg_gather/gather_schema.sql; cat "$TSV_FILE"; } \
    | psql "postgresql://pgadmin:pgadmin123@localhost:5432/${WORK_DB}" \
           -X -q -f -

psql "postgresql://pgadmin:pgadmin123@localhost:5432/${WORK_DB}" \
    -X -f /tmp/pg_gather/gather_report.sql \
    > "$REPORT_FILE"

# Clean up
psql "postgresql://pgadmin:pgadmin123@localhost:5432/postgres" \
    -c "DROP DATABASE ${WORK_DB};"

echo "Report: $REPORT_FILE"
```

---

## Connecting to a Database on Your Host Machine

When the pg_gather Docker container needs to reach a PostgreSQL running on your laptop (not in Docker):

| Platform | Use as PGHOST |
|---|---|
| macOS / Windows (Docker Desktop) | `host.docker.internal` |
| Linux | Host's LAN IP (e.g. `192.168.1.100`) or `172.17.0.1` (Docker bridge default) |

Example:

```bash
docker compose run --rm \
    -e PGHOST=host.docker.internal \
    -e PGPORT=5432 \
    -e PGUSER=postgres \
    -e PGPASSWORD=postgres \
    -e PGDATABASE=myapp_production \
    pg_gather
```

---

## pg_hba.conf Considerations

The target database must allow connections from the pg_gather runner's IP. If you see `FATAL: pg_hba.conf rejects connection`, add an entry:

```
# Allow pg_gather runner (Docker bridge network)
host    all    your_superuser    172.16.0.0/12    scram-sha-256
```

This lab's `postgres/pg_hba.conf` already includes this rule for the bundled postgres container.
