#!/usr/bin/env bash
# =============================================================================
# Lab 7 — Before/After Tuning
# Goal : Show a complete tuning cycle using pg_gather as the measurement
#         tool.  We fix the missing indexes on the events table and compare
#         two reports to quantify the improvement.
#
# The problem : events (200k rows) has no index on user_id or event_type.
#               Every query that filters on those columns does a full seqscan.
# The fix     : CREATE INDEX on both columns + ANALYZE.
# The proof   : pg_gather report BEFORE shows high seq_scan, AFTER shows
#               idx_scan replacing seqscans and planner chooses index.
# =============================================================================
set -euo pipefail

source "$(dirname "$0")/_common.sh"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

banner "LAB 7 — Before/After Index Tuning"

# ── Step 1: reset stats and generate baseline load ───────────────────────────
step "Step 1/6 — Reset stats + drop any existing lab indexes (makes lab re-runnable)"
psql_exec "SELECT pg_stat_statements_reset();"
psql_exec "SELECT pg_stat_reset();"   # resets pg_stat_user_tables counters

# Drop the indexes if they already exist so BEFORE state is clean
psql_exec "
DROP INDEX IF EXISTS ecommerce.idx_events_event_type;
DROP INDEX IF EXISTS ecommerce.idx_events_user_id;
DROP INDEX IF EXISTS ecommerce.idx_events_user_event;"
echo "  Any previous lab7 indexes dropped"

echo "  Running 5 full-table-scan queries on events (no indexes) ..."
for i in $(seq 1 5); do
    docker exec "$PG_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -q -c "
        SELECT user_id, count(*) FROM ecommerce.events
        WHERE event_type = 'purchase' GROUP BY user_id ORDER BY 2 DESC LIMIT 5;" \
        &>/dev/null
done
for i in $(seq 1 5); do
    docker exec "$PG_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -q -c "
        SELECT event_type, count(*) FROM ecommerce.events
        WHERE user_id = $((RANDOM % 50000 + 1)) GROUP BY event_type;" \
        &>/dev/null
done
echo "  10 full-scan queries run"

step "Step 2/6 — Capture BEFORE metrics"
psql_exec "
SELECT relname,
       seq_scan,
       idx_scan,
       n_live_tup,
       pg_size_pretty(pg_total_relation_size('ecommerce.'||relname)) AS size
FROM   pg_stat_user_tables
WHERE  relname = 'events';"

psql_exec "
SELECT left(query, 70) AS query,
       calls,
       round(total_exec_time::numeric,0) AS total_ms,
       round(mean_exec_time::numeric,0)  AS mean_ms
FROM   pg_stat_statements
WHERE  query LIKE '%ecommerce.events%'
ORDER  BY total_exec_time DESC
LIMIT  5;"

echo ""
echo "  Existing indexes on events table:"
psql_exec "
SELECT indexname, indexdef
FROM   pg_indexes
WHERE  schemaname = 'ecommerce' AND tablename = 'events';"

# ── Step 3: generate BEFORE report ───────────────────────────────────────────
step "Step 3/6 — Generating BEFORE report"
cd "$PROJECT_ROOT"
BEFORE_LOG=$(docker compose run --rm pg_gather 2>&1 | tee /tmp/pg_gather_before.log)
BEFORE_REPORT=$(grep "HTML :" /tmp/pg_gather_before.log | awk '{print $NF}' | tail -1)
echo "  BEFORE report: ${BEFORE_REPORT}"

# ── Step 4: add the missing indexes ──────────────────────────────────────────
step "Step 4/6 — Adding missing indexes + ANALYZE"
echo "  Creating index on events(event_type) ..."
psql_exec "CREATE INDEX CONCURRENTLY idx_events_event_type ON ecommerce.events (event_type);"

echo "  Creating index on events(user_id) ..."
psql_exec "CREATE INDEX CONCURRENTLY idx_events_user_id ON ecommerce.events (user_id);"

echo "  Creating composite index on events(user_id, event_type) ..."
psql_exec "CREATE INDEX CONCURRENTLY idx_events_user_event ON ecommerce.events (user_id, event_type);"

echo "  Running ANALYZE to update planner statistics ..."
psql_exec "ANALYZE ecommerce.events;"

echo "  New indexes:"
psql_exec "
SELECT indexname,
       pg_size_pretty(pg_relation_size((schemaname||'.'||indexname)::regclass)) AS index_size
FROM   pg_indexes
WHERE  schemaname = 'ecommerce' AND tablename = 'events'
ORDER  BY indexname;"

# ── Step 5: re-run the same queries (should use indexes now) ─────────────────
step "Step 5/6 — Re-running same queries (now with indexes)"
psql_exec "SELECT pg_stat_statements_reset();"

for i in $(seq 1 5); do
    docker exec "$PG_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -q -c "
        SELECT user_id, count(*) FROM ecommerce.events
        WHERE event_type = 'purchase' GROUP BY user_id ORDER BY 2 DESC LIMIT 5;" \
        &>/dev/null
done
for i in $(seq 1 5); do
    docker exec "$PG_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -q -c "
        SELECT event_type, count(*) FROM ecommerce.events
        WHERE user_id = $((RANDOM % 50000 + 1)) GROUP BY event_type;" \
        &>/dev/null
done

echo "  AFTER metrics — seq_scan should now be 0 for these queries:"
psql_exec "
SELECT relname, seq_scan, idx_scan, n_live_tup
FROM   pg_stat_user_tables
WHERE  relname = 'events';"

echo "  AFTER pg_stat_statements — mean_ms should be much lower:"
psql_exec "
SELECT left(query, 70) AS query,
       calls,
       round(total_exec_time::numeric,0) AS total_ms,
       round(mean_exec_time::numeric,0)  AS mean_ms
FROM   pg_stat_statements
WHERE  query LIKE '%ecommerce.events%'
ORDER  BY total_exec_time DESC
LIMIT  5;"

# ── Step 6: generate AFTER report ────────────────────────────────────────────
step "Step 6/6 — Generating AFTER report"
cd "$PROJECT_ROOT"
AFTER_LOG=$(docker compose run --rm pg_gather 2>&1 | tee /tmp/pg_gather_after.log)
AFTER_REPORT=$(grep "HTML :" /tmp/pg_gather_after.log | awk '{print $NF}' | tail -1)
echo "  AFTER report: ${AFTER_REPORT}"

# ── Summary ───────────────────────────────────────────────────────────────────
cat <<GUIDE

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 LAB 7 — BEFORE/AFTER COMPARISON GUIDE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

 BEFORE → ${BEFORE_REPORT:-./reports/report_BEFORE.html}
 AFTER  → ${AFTER_REPORT:-./reports/report_AFTER.html}

 WHAT CHANGED
 ─────────────
 TABLE STATISTICS section:
   BEFORE: events → seq_scan HIGH, idx_scan = 0
   AFTER:  events → seq_scan ≈ 0,  idx_scan HIGH
   Why: the planner now uses the indexes instead of full scans

 TOP SQL section:
   BEFORE: event queries appear in top-5 by total_time
   AFTER:  event queries drop out of top-5 (fast now)
   Why: index lookup = O(log n) vs full scan = O(n)

 INDEX INFORMATION section:
   AFTER: three new indexes appear for the events table
   Note: each index adds ~3-5 MB and slightly slows INSERTs

 BLOAT section:
   No change — indexes don't affect dead tuple counts

 WHICH REPORT SECTIONS SHOW IMPROVEMENT
 ────────────────────────────────────────
   ✓  Table Statistics   → seq_scan drops to 0
   ✓  Top SQL by Time    → event queries disappear from top
   ✓  Index Information  → 3 new indexes on events table
   ✗  Bloat Analysis     → unchanged (different problem)
   ✗  Autovacuum         → unchanged

 PRODUCTION LESSON
 ──────────────────
 CONCURRENTLY keyword means the index builds without locking
 the table for writes — safe to run on a live production system.
 Without CONCURRENTLY, CREATE INDEX locks the table until done.

 Open both reports: make serve → http://localhost:8080
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
GUIDE
