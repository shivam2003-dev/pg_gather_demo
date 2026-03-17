#!/usr/bin/env bash
# =============================================================================
# Lab 2 — Slow Queries
# Goal : Generate measurable slow-query data in pg_stat_statements so
#         pg_gather's "Top SQL" section has something interesting to show.
# =============================================================================
set -euo pipefail

source "$(dirname "$0")/_common.sh"

banner "LAB 2 — Slow Queries"

# Reset statement stats so this lab's queries stand out clearly
step "Step 1/4 — Resetting pg_stat_statements counters"
psql_exec "SELECT pg_stat_statements_reset();"
psql_exec "SELECT count(*) AS statements_after_reset FROM pg_stat_statements;"

# ── Run 5 slow queries ────────────────────────────────────────────────────────
step "Step 2/4 — Running 5 slow / expensive queries"

echo "  Query 1: simulate_slow_query() × 3 calls (pg_sleep + join)"
for i in 1 2 3; do
    docker exec "$PG_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
        -q -c "SELECT * FROM ecommerce.simulate_slow_query(800) LIMIT 1;" &>/dev/null
    echo "    call $i/3 done"
done

echo "  Query 2: full table scan on events (200k rows, NO index on event_type)"
docker exec "$PG_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -q -c "
SELECT user_id, count(*) AS cnt
FROM   ecommerce.events
WHERE  event_type = 'purchase'
GROUP  BY user_id
ORDER  BY cnt DESC
LIMIT  20;" &>/dev/null
echo "    query 2 done"

echo "  Query 3: full table scan on events — different filter"
docker exec "$PG_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -q -c "
SELECT user_id, count(*)
FROM   ecommerce.events
WHERE  event_type = 'signup' AND page_url LIKE '/page/1%'
GROUP  BY user_id LIMIT 10;" &>/dev/null

echo "  Query 4: multi-table join with aggregation (no filter indexes)"
docker exec "$PG_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -q -c "
SELECT u.country, o.status,
       count(o.id)          AS order_count,
       sum(o.total)         AS revenue,
       avg(oi.unit_price)   AS avg_price
FROM   ecommerce.orders     o
JOIN   ecommerce.users      u  ON u.id = o.user_id
JOIN   ecommerce.order_items oi ON oi.order_id = o.id
GROUP  BY u.country, o.status
ORDER  BY revenue DESC;" &>/dev/null
echo "    query 4 done"

echo "  Query 5: hash join across all 4 main tables"
docker exec "$PG_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -q -c "
SELECT p.category,
       count(DISTINCT o.user_id) AS unique_buyers,
       sum(oi.quantity)          AS units_sold,
       sum(oi.unit_price * oi.quantity) AS gross_revenue
FROM   ecommerce.order_items oi
JOIN   ecommerce.products    p  ON p.id = oi.product_id
JOIN   ecommerce.orders      o  ON o.id = oi.order_id
JOIN   ecommerce.users       u  ON u.id = o.user_id
WHERE  u.plan = 'enterprise'
GROUP  BY p.category;" &>/dev/null
echo "    query 5 done"

# ── Show what landed in pg_stat_statements ────────────────────────────────────
step "Step 3/4 — pg_stat_statements snapshot (top 5 by total time)"
psql_exec "
SELECT left(query, 60)                      AS query_snippet,
       calls,
       round(total_exec_time::numeric, 0)   AS total_ms,
       round(mean_exec_time::numeric, 0)    AS mean_ms,
       rows
FROM   pg_stat_statements
WHERE  query NOT LIKE '%pg_stat%'
ORDER  BY total_exec_time DESC
LIMIT  5;"

# ── Generate report ───────────────────────────────────────────────────────────
step "Step 4/4 — Generating pg_gather report with slow query data captured"
cd "$(dirname "$0")/.."
docker compose run --rm pg_gather

# ── What to look for ─────────────────────────────────────────────────────────
cat <<'GUIDE'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 LAB 2 — WHAT TO LOOK FOR IN THE REPORT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

 TOP SQL SECTION
 ───────────────
 → Sort by "Total Time" — simulate_slow_query() should be #1
   (3 calls × ~800ms each = ~2400ms total)
 → Sort by "Mean Time" — same function wins (800ms per call)
 → Sort by "Calls"     — the full-scan queries have 1 call each

 TABLE STATISTICS
 ────────────────
 → events table: seq_scan counter has jumped — every query
   that filtered on event_type did a full 200k-row scan
   because there is NO index on that column.
 → Compare seq_scan vs idx_scan ratio — a healthy table has
   idx_scan >> seq_scan for filtered queries.

 WHAT THE pg_stat_statements SECTION SHOWS
 ──────────────────────────────────────────
 → query fingerprint (normalized — literals replaced with $1, $2)
 → calls / total_exec_time / mean_exec_time / stddev_exec_time
 → rows returned per call
 → shared_blks_hit vs shared_blks_read (cache hit ratio per query)

 KEY INSIGHT
 ───────────
 simulate_slow_query() has HIGH mean time but LOW calls.
 The table-scan queries have LOW mean time but HIGH rows scanned.
 Both are problems — one is latency, the other is throughput.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
GUIDE
