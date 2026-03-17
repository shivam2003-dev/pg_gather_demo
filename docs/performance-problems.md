# Intentional Performance Problems Reference

`postgres/initdb/03_problems.sql` creates six intentional problems in the `ecommerce` schema. Each one is designed to light up a specific section of the pg_gather HTML report.

---

## Problem 1 — Table with autovacuum disabled (`bloat_demo`)

**What was done:** Created `bloat_demo` with `autovacuum_enabled = false` storage parameter.

**Why it matters:** Dead tuples from updates and deletes are never reclaimed. The table bloats indefinitely, wasting space and slowing sequential scans.

**Where to find it in the report:**
- **Bloat Analysis** section — `bloat_demo` shows a high bloat ratio
- **Autovacuum** section — 0 autovacuum runs recorded for this table

**SQL to inspect:**
```sql
SELECT relname, n_dead_tup, n_live_tup,
       round(n_dead_tup::numeric / nullif(n_live_tup + n_dead_tup, 0) * 100, 1) AS dead_pct
FROM pg_stat_user_tables
WHERE relname = 'bloat_demo';

SELECT reloptions FROM pg_class WHERE relname = 'bloat_demo';
-- Should show: {autovacuum_enabled=false}
```

**How to fix:**
```sql
ALTER TABLE ecommerce.bloat_demo RESET (autovacuum_enabled);
VACUUM ANALYZE ecommerce.bloat_demo;
```

---

## Problem 2 — Missing indexes on high-cardinality columns (`events`)

**What was done:** Created `events` (200 k rows) with no index on `user_id` or `event_type` — the two most commonly filtered columns.

**Why it matters:** Every query filtering on these columns causes a full sequential scan of 200 k rows. Under concurrent load this saturates I/O and locks shared buffers.

**Where to find it in the report:**
- **Tables without Primary Key / Missing Indexes** section
- **pg_stat_user_tables** — `seq_scan` counter on `events` will be high after queries run

**SQL to demonstrate the problem:**
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM ecommerce.events WHERE user_id = 1234;
-- Look for: Seq Scan on events  (cost=... rows=200000 ...)
```

**How to fix:**
```sql
CREATE INDEX ON ecommerce.events (user_id);
CREATE INDEX ON ecommerce.events (event_type);
-- or a composite:
CREATE INDEX ON ecommerce.events (user_id, event_type, occurred_at DESC);
```

---

## Problem 3 — Duplicate indexes (`search_log`)

**What was done:** Created three identical B-tree indexes on `search_log.user_id`.

**Why it matters:** Duplicate indexes consume shared_buffers memory and triple the WAL write overhead on every INSERT/UPDATE/DELETE. PostgreSQL can only use one at a time — the others are dead weight.

**Where to find it in the report:**
- **Duplicate Indexes** section — all three `idx_search_log_user_id_*` appear together

**SQL to inspect:**
```sql
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'search_log'
  AND schemaname = 'ecommerce';
```

**How to fix:**
```sql
-- Keep one, drop the other two
DROP INDEX ecommerce.idx_search_log_user_id_2;
DROP INDEX ecommerce.idx_search_log_user_id_3;
```

---

## Problem 4 — Very wide table (`wide_audit_log`)

**What was done:** Created `wide_audit_log` with 34 columns (including 30 `TEXT` columns), seeded with 100 k rows.

**Why it matters:** Wide rows mean fewer rows fit in each 8 kB page. Sequential scans read more pages for the same row count. Frequent updates to TEXT columns cause excessive TOAST activity and table bloat.

**Where to find it in the report:**
- **Table Bloat** section — high `avg_row_size` relative to row count
- `pg_stats.avg_width` will be unusually large for this table

**SQL to inspect:**
```sql
SELECT relname,
       pg_size_pretty(pg_total_relation_size('ecommerce.wide_audit_log')) AS total_size,
       n_live_tup
FROM pg_stat_user_tables
WHERE relname = 'wide_audit_log';

-- Check average row width
SELECT avg_width FROM pg_stats
WHERE tablename = 'wide_audit_log' AND attname = 'meta_col_01';
```

**How to fix (design-level):** Extract metadata into a key-value `audit_log_attributes(log_id, key, value)` child table, or use a `JSONB` column for sparse attributes.

---

## Problem 5 — Dead tuples without VACUUM (`bloat_demo`)

**What was done:** Inserted 50 k rows into `bloat_demo`, then deleted ~90% of them. Because `autovacuum_enabled = false`, the dead tuples are never cleaned up.

**Why it matters:** Sequential scans still visit dead tuple slots, wasting I/O. The table takes up far more disk space than its live row count justifies.

**Where to find it in the report:**
- **Bloat Analysis** — `bloat_demo` shows bloat ratio > 50%
- **pg_stat_user_tables** — `n_dead_tup` in the tens of thousands

**SQL to inspect:**
```sql
SELECT relname, n_live_tup, n_dead_tup,
       pg_size_pretty(pg_total_relation_size('ecommerce.bloat_demo')) AS size
FROM pg_stat_user_tables
WHERE relname = 'bloat_demo';
```

**How to fix:**
```sql
ALTER TABLE ecommerce.bloat_demo RESET (autovacuum_enabled);
VACUUM (VERBOSE) ecommerce.bloat_demo;
-- For space reclaim, VACUUM FULL (takes an exclusive lock):
VACUUM FULL ecommerce.bloat_demo;
```

---

## Problem 6 — Slow query simulation function (`simulate_slow_query`)

**What was done:** Created `ecommerce.simulate_slow_query(sleep_ms INT)` which calls `pg_sleep()` then runs a multi-table join.

**Why it matters:** Demonstrates what long-running queries look like in pg_gather. When called multiple times, it accumulates high `total_exec_time` in `pg_stat_statements`.

**Where to find it in the report:**
- **Top SQL by Total Time** — `simulate_slow_query` dominates after a few calls
- **Long Running Queries** — visible in `pg_stat_activity` if called during collection

**SQL to use it:**
```sql
-- Run a few times to populate pg_stat_statements
SELECT * FROM ecommerce.simulate_slow_query(1000);  -- 1 second sleep
SELECT * FROM ecommerce.simulate_slow_query(1000);
SELECT * FROM ecommerce.simulate_slow_query(1000);

-- Then generate a report to see it at the top
-- (exit psql, then: docker compose run --rm pg_gather)
```

**SQL to check pg_stat_statements directly:**
```sql
SELECT query, calls, round(total_exec_time::numeric, 0) AS total_ms,
       round(mean_exec_time::numeric, 0) AS mean_ms
FROM pg_stat_statements
WHERE query LIKE '%simulate_slow%'
ORDER BY total_exec_time DESC;
```

---

## Reset All Problems

To start fresh (e.g. before a demo), reset the database volume:

```bash
docker compose down -v
docker compose up postgres -d
# Wait for healthy, then re-run the report
docker compose run --rm pg_gather
```
