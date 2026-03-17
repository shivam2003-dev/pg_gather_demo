# Generating Reports

pg_gather produces two output files per run, both saved to `reports/` on your host:

| File | Description |
|---|---|
| `gather_TIMESTAMP.tsv` | Raw diagnostic snapshot (tab-separated) — keep for archiving |
| `report_TIMESTAMP.html` | Interactive HTML report — open in any browser |

---

## Prerequisites

The `postgres` service must be running and healthy before you generate a report:

```bash
docker compose up postgres -d
docker compose ps        # STATUS column must show "healthy"
```

---

## Generate a Report (standard)

```bash
docker compose run --rm pg_gather
```

This executes `setup.sh` which runs two stages:

1. **Stage 1** — `gather.sql` queries `labdb` and writes a `.tsv` file
2. **Stage 2** — imports the TSV into a temp database, runs `gather_report.sql`, writes `.html`, drops the temp database

The runner exits automatically when done. Output files appear in `reports/`.

---

## View the HTML Report

**macOS**
```bash
open reports/report_*.html
```

**Linux**
```bash
xdg-open reports/report_*.html
```

**Windows (PowerShell)**
```powershell
Start-Process (Get-Item reports\report_*.html | Select-Object -Last 1).FullName
```

**Serve over HTTP (any OS)**
```bash
cd reports
python3 -m http.server 8080
# Open http://localhost:8080 in your browser
```

---

## Generate Multiple Reports (before/after comparison)

Run the report before and after a change (e.g. adding an index) to compare results side-by-side:

```bash
# Baseline
docker compose run --rm pg_gather

# Make your change — e.g. add an index
docker exec -it pg_gather_db psql -U pgadmin -d labdb \
    -c "CREATE INDEX ON ecommerce.events (user_id);"

# After
docker compose run --rm pg_gather

# Both reports are in reports/ with different timestamps
ls -lh reports/
```

Open both HTML files in separate browser tabs to compare findings.

---

## Run pg_gather Manually (advanced)

If you want to run individual stages yourself, open a shell in the runner container:

```bash
docker compose run --rm pg_gather bash
```

Inside the container, pg_gather scripts are at `/pg_gather/`:

```bash
# Stage 1 only — collect raw data
psql -h pg_gather_db -U pgadmin -d labdb \
    -X -q -A -t \
    -f /pg_gather/gather.sql \
    > /reports/manual_gather.tsv

# Stage 2 only — generate report from an existing TSV
# (create work DB first)
psql -h pg_gather_db -U pgadmin -d postgres \
    -c "CREATE DATABASE pg_gather_manual;"

{ cat /pg_gather/gather_schema.sql; cat /reports/manual_gather.tsv; } \
    | psql -h pg_gather_db -U pgadmin -d pg_gather_manual -X -q -f -

psql -h pg_gather_db -U pgadmin -d pg_gather_manual \
    -X -f /pg_gather/gather_report.sql \
    > /reports/manual_report.html

# Clean up
psql -h pg_gather_db -U pgadmin -d postgres \
    -c "DROP DATABASE pg_gather_manual;"
```

---

## Trigger Slow Queries Before Reporting

To populate the "Top SQL by Total Time" section in the report, run some queries first:

```bash
docker exec -it pg_gather_db psql -U pgadmin -d labdb -c "
-- Simulate slow queries (runs a 500 ms sleep + join)
SELECT * FROM ecommerce.simulate_slow_query(500);
SELECT * FROM ecommerce.simulate_slow_query(500);
SELECT * FROM ecommerce.simulate_slow_query(500);

-- Force sequential scans on the un-indexed events table
SELECT count(*) FROM ecommerce.events WHERE user_id = 1234;
SELECT count(*) FROM ecommerce.events WHERE event_type = 'purchase';
"
```

Then run the report:

```bash
docker compose run --rm pg_gather
```

---

## Schedule Recurring Reports (cron)

To collect a report every hour on the host (macOS/Linux):

```bash
crontab -e
# Add:
0 * * * * cd /path/to/pg_gather && docker compose run --rm pg_gather >> logs/cron.log 2>&1
```

Reports accumulate in `reports/` with unique timestamps. Clean up old ones with:

```bash
# Keep only the last 24 reports
ls -t reports/report_*.html | tail -n +25 | xargs rm -f
ls -t reports/gather_*.tsv  | tail -n +25 | xargs rm -f
```
