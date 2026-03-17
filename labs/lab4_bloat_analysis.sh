#!/usr/bin/env bash
# =============================================================================
# Lab 4 — Bloat Analysis
# Goal : Demonstrate how DELETE without VACUUM causes table bloat, then
#         show how VACUUM ANALYZE reclaims space — visible in two reports.
#
# The bloat_demo table already has autovacuum_enabled=false and ~45k dead
# tuples from 03_problems.sql.  This lab adds MORE bloat then compares
# two pg_gather reports: BEFORE and AFTER vacuum.
# =============================================================================
set -euo pipefail

source "$(dirname "$0")/_common.sh"

banner "LAB 4 — Bloat Analysis"

# ── Baseline state ────────────────────────────────────────────────────────────
step "Step 1/6 — Current state of bloat_demo"
psql_exec "
SELECT relname,
       n_live_tup,
       n_dead_tup,
       round(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 1) AS dead_pct,
       pg_size_pretty(pg_total_relation_size('ecommerce.bloat_demo')) AS total_size,
       last_autovacuum
FROM   pg_stat_user_tables
WHERE  relname = 'bloat_demo';"

# ── Add more data, then delete most of it ────────────────────────────────────
step "Step 2/6 — Inserting 100k rows into bloat_demo"
psql_exec "
INSERT INTO ecommerce.bloat_demo (payload)
SELECT repeat('bloat_lab4_' || i::text, 40)
FROM   generate_series(1, 100000) AS s(i);"

psql_exec "SELECT count(*) AS rows_after_insert FROM ecommerce.bloat_demo;"

step "Step 3/6 — Deleting 80k of those rows (creates ~80k dead tuples)"
psql_exec "
DELETE FROM ecommerce.bloat_demo
WHERE  id IN (
    SELECT id FROM ecommerce.bloat_demo
    ORDER  BY id DESC
    LIMIT  80000
);"

echo "  NOT running VACUUM — dead tuples will stay in the table"

# ── Measure bloat BEFORE vacuum ───────────────────────────────────────────────
step "Step 4/6 — Measuring bloat BEFORE vacuum"
psql_exec "
SELECT relname,
       n_live_tup,
       n_dead_tup,
       round(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 1) AS dead_pct,
       pg_size_pretty(pg_total_relation_size('ecommerce.bloat_demo')) AS total_size
FROM   pg_stat_user_tables
WHERE  relname = 'bloat_demo';"

echo "  Generating BEFORE report..."
cd "$(dirname "$0")/.."
BEFORE_LOG=$(docker compose run --rm pg_gather 2>&1 | tee /tmp/pg_gather_before.log)
BEFORE_REPORT=$(grep "HTML :" /tmp/pg_gather_before.log | awk '{print $NF}' | tail -1)
echo "  BEFORE report: ${BEFORE_REPORT}"

# ── Run VACUUM ANALYZE ────────────────────────────────────────────────────────
step "Step 5/6 — Running VACUUM ANALYZE on bloat_demo"
psql_exec "VACUUM ANALYZE ecommerce.bloat_demo;"

psql_exec "
SELECT relname,
       n_live_tup,
       n_dead_tup,
       round(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 1) AS dead_pct,
       pg_size_pretty(pg_total_relation_size('ecommerce.bloat_demo')) AS total_size,
       to_char(last_vacuum, 'YYYY-MM-DD HH24:MI:SS') AS last_vacuum
FROM   pg_stat_user_tables
WHERE  relname = 'bloat_demo';"

echo "  Note: VACUUM removes dead tuples from visibility but may not shrink"
echo "        the file size immediately — use VACUUM FULL to reclaim disk space."
echo "        pg_gather shows BOTH dead tuples AND estimated bloat bytes."

# ── Generate AFTER report ─────────────────────────────────────────────────────
step "Step 6/6 — Generating AFTER report"
AFTER_LOG=$(docker compose run --rm pg_gather 2>&1 | tee /tmp/pg_gather_after.log)
AFTER_REPORT=$(grep "HTML :" /tmp/pg_gather_after.log | awk '{print $NF}' | tail -1)
echo "  AFTER  report: ${AFTER_REPORT}"

# ── What to look for ─────────────────────────────────────────────────────────
cat <<GUIDE

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 LAB 4 — WHAT TO LOOK FOR IN THE TWO REPORTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

 BEFORE VACUUM report  →  ${BEFORE_REPORT:-./reports/report_BEFORE.html}
 AFTER  VACUUM report  →  ${AFTER_REPORT:-./reports/report_AFTER.html}

 BLOAT ANALYSIS SECTION
 ───────────────────────
 BEFORE: bloat_demo shows n_dead_tup ~80-125k, bloat_ratio high
 AFTER:  bloat_demo shows n_dead_tup ≈ 0,  dead_pct ≈ 0%

 TABLE STATISTICS SECTION
 ─────────────────────────
 → n_dead_tup drops from ~125k to ~0 after vacuum
 → last_manual_vacuum timestamp appears in AFTER report
 → Table size may not shrink (VACUUM ≠ VACUUM FULL)
   VACUUM marks pages reusable; VACUUM FULL physically rewrites

 AUTOVACUUM SECTION
 ───────────────────
 → bloat_demo shows autovacuum_enabled = false in both reports
 → This explains WHY it accumulated so much bloat:
   no background worker ever cleaned it
 → In production: never disable autovacuum on a write-heavy table

 OPEN BOTH REPORTS SIDE BY SIDE
 → make serve  →  http://localhost:8080
   Open the BEFORE and AFTER reports in two browser tabs
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
GUIDE
