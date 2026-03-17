#!/usr/bin/env bash
# =============================================================================
# Lab 1 — Baseline Report
# Goal : Generate a clean first pg_gather report and learn which sections
#         to read first when diagnosing an unfamiliar PostgreSQL instance.
# =============================================================================
set -euo pipefail

source "$(dirname "$0")/_common.sh"

banner "LAB 1 — Baseline Report"

# ── Step 1: confirm postgres version ─────────────────────────────────────────
step "Step 1/4 — PostgreSQL version"
psql_exec "SELECT version();"

# ── Step 2: confirm pg_stat_statements is active ──────────────────────────────
step "Step 2/4 — pg_stat_statements status"
psql_exec "
SELECT name, setting
FROM   pg_settings
WHERE  name IN ('shared_preload_libraries','pg_stat_statements.track')
ORDER  BY name;"

psql_exec "
SELECT count(*) AS queries_tracked
FROM   pg_stat_statements;"

# ── Step 3: show the intentional problems we planted ─────────────────────────
step "Step 3/4 — Planted problems visible in this instance"
psql_exec "
SELECT schemaname, tablename,
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
       CASE WHEN reloptions::text LIKE '%autovacuum_enabled=false%'
            THEN '⚠ autovacuum OFF' ELSE 'ok' END AS autovacuum
FROM   pg_tables t
JOIN   pg_class  c ON c.relname = t.tablename
                   AND c.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = t.schemaname)
WHERE  schemaname = 'ecommerce'
ORDER  BY pg_total_relation_size(schemaname||'.'||tablename) DESC;"

# ── Step 4: generate the baseline pg_gather report ───────────────────────────
step "Step 4/4 — Generating baseline pg_gather report"
docker compose run --rm pg_gather

# ── What to look for ─────────────────────────────────────────────────────────
cat <<'GUIDE'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 LAB 1 — WHAT TO LOOK FOR IN THE REPORT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

 Recommended reading order for ANY new pg_gather report:

 1. INSTANCE INFORMATION  (top of report)
    → PostgreSQL version, uptime, max_connections, shared_buffers
    → Confirms the config from conf.d/custom.conf loaded correctly

 2. CONFIGURATION REPORT
    → Look for parameters flagged as non-default
    → shared_preload_libraries should show pg_stat_statements

 3. DATABASE SIZES
    → labdb should appear with tables in the ecommerce schema
    → wide_audit_log will be disproportionately large (~41 MB / 100k rows)

 4. TABLE STATISTICS
    → seq_scan column: events table will have high seq_scan (no indexes)
    → n_dead_tup: bloat_demo will show dead tuples

 5. INDEX INFORMATION
    → Look for duplicate entries on search_log.user_id
    → events table: no index on user_id or event_type

 6. BLOAT ANALYSIS
    → bloat_demo: expect high bloat_ratio (autovacuum disabled)

 Open: make serve → http://localhost:8080
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
GUIDE
