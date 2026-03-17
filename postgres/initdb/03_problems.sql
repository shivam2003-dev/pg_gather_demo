-- =============================================================================
-- 03_problems.sql  —  Intentional performance problems for pg_gather labs
--
-- Every object here is created to make a specific pg_gather report section
-- light up.  Each problem is documented with:
--   PROBLEM    : what is wrong
--   SHOWS IN   : which pg_gather HTML section exposes it
--   LOOK FOR   : exactly what to find in the report
-- =============================================================================

\echo '>>> [03_problems.sql] Creating intentional performance problems...'

SET search_path = ecommerce, public;

-- =============================================================================
-- PROBLEM 1: Table with autovacuum DISABLED
-- =============================================================================
-- PROBLEM  : Dead tuples accumulate forever — table bloats without bound.
-- SHOWS IN : pg_gather → "Bloat Analysis" + "Autovacuum" sections.
-- LOOK FOR : bloat_ratio % much higher than similar tables; 0 autovacuum runs.
-- =============================================================================
CREATE TABLE bloat_demo (
    id         SERIAL PRIMARY KEY,
    payload    TEXT NOT NULL DEFAULT repeat('x', 200),
    created_at TIMESTAMPTZ DEFAULT now()
) WITH (autovacuum_enabled = false);    -- ← INTENTIONALLY disabled

\echo '    PROBLEM 1: bloat_demo table (autovacuum disabled) created'

-- =============================================================================
-- PROBLEM 2: Missing indexes on high-cardinality FK / filter columns
-- =============================================================================
-- PROBLEM  : Full sequential scans on large tables instead of index seeks.
-- SHOWS IN : pg_gather → "Tables without Primary Key / Missing Indexes" +
--            pg_stat_user_tables (seq_scan counter will be high).
-- LOOK FOR : seq_scan >> 0 on a big table; no matching index in pg_indexes.
-- =============================================================================
CREATE TABLE events (
    id          BIGSERIAL PRIMARY KEY,
    user_id     INT          NOT NULL,   -- FK but NO index ← intentional
    event_type  TEXT         NOT NULL,   -- filtered heavily but NO index ← intentional
    session_id  UUID         NOT NULL DEFAULT gen_random_uuid(),
    page_url    TEXT,
    referrer    TEXT,
    occurred_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Seed 200k rows so sequential scans are measurably slow
INSERT INTO events (user_id, event_type, page_url, occurred_at)
SELECT
    1 + (random() * 49999)::int,
    (ARRAY['page_view','click','purchase','signup','logout','search'])[1 + (i % 6)],
    '/page/' || (i % 500),
    now() - (random() * interval '90 days')
FROM generate_series(1, 200000) AS s(i);

\echo '    PROBLEM 2: events table (200k rows, missing indexes on user_id + event_type)'

-- =============================================================================
-- PROBLEM 3: Duplicate / redundant indexes on the same column
-- =============================================================================
-- PROBLEM  : Wasted memory in shared_buffers + extra WAL writes on every
--            INSERT/UPDATE/DELETE.  Postgres cannot use two identical indexes
--            simultaneously — one is always dead weight.
-- SHOWS IN : pg_gather → "Duplicate Indexes" section.
-- LOOK FOR : Two or more index entries with identical indkey columns.
-- =============================================================================
CREATE TABLE search_log (
    id         BIGSERIAL PRIMARY KEY,
    query_text TEXT         NOT NULL,
    user_id    INT          NOT NULL,
    hit_count  INT          NOT NULL DEFAULT 0,
    searched_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Three indexes that all index the same column — only one is useful
CREATE INDEX idx_search_log_user_id_1 ON search_log (user_id);
CREATE INDEX idx_search_log_user_id_2 ON search_log (user_id);   -- duplicate ← intentional
CREATE INDEX idx_search_log_user_id_3 ON search_log (user_id);   -- duplicate ← intentional

INSERT INTO search_log (query_text, user_id, hit_count)
SELECT
    'search term ' || (i % 1000),
    1 + (random() * 49999)::int,
    (random() * 500)::int
FROM generate_series(1, 50000) AS s(i);

\echo '    PROBLEM 3: search_log table (3 duplicate indexes on user_id)'

-- =============================================================================
-- PROBLEM 4: Very wide table (many columns) — a bloat and I/O candidate
-- =============================================================================
-- PROBLEM  : Wide rows mean fewer rows per 8 kB page → more I/O per scan.
--            Also inflates pg_attribute and causes large TOAST if text cols
--            are updated often.
-- SHOWS IN : pg_gather → "Table Bloat" section; avg_row_size will be large.
-- LOOK FOR : high avg_width in pg_stats; table size disproportionate to rowcount.
-- =============================================================================
CREATE TABLE wide_audit_log (
    id             BIGSERIAL PRIMARY KEY,
    event_time     TIMESTAMPTZ DEFAULT now(),
    actor_id       INT,
    action         TEXT,
    -- 30 arbitrary metadata columns simulating a poorly designed audit table
    meta_col_01 TEXT, meta_col_02 TEXT, meta_col_03 TEXT, meta_col_04 TEXT,
    meta_col_05 TEXT, meta_col_06 TEXT, meta_col_07 TEXT, meta_col_08 TEXT,
    meta_col_09 TEXT, meta_col_10 TEXT, meta_col_11 TEXT, meta_col_12 TEXT,
    meta_col_13 TEXT, meta_col_14 TEXT, meta_col_15 TEXT, meta_col_16 TEXT,
    meta_col_17 TEXT, meta_col_18 TEXT, meta_col_19 TEXT, meta_col_20 TEXT,
    meta_col_21 TEXT, meta_col_22 TEXT, meta_col_23 TEXT, meta_col_24 TEXT,
    meta_col_25 TEXT, meta_col_26 TEXT, meta_col_27 TEXT, meta_col_28 TEXT,
    meta_col_29 TEXT, meta_col_30 TEXT
);

INSERT INTO wide_audit_log
    (actor_id, action,
     meta_col_01, meta_col_02, meta_col_03, meta_col_04, meta_col_05,
     meta_col_06, meta_col_07, meta_col_08, meta_col_09, meta_col_10)
SELECT
    1 + (random() * 49999)::int,
    (ARRAY['INSERT','UPDATE','DELETE','LOGIN','LOGOUT'])[1 + (i % 5)],
    md5(i::text), md5((i+1)::text), md5((i+2)::text), md5((i+3)::text), md5((i+4)::text),
    md5((i+5)::text), md5((i+6)::text), md5((i+7)::text), md5((i+8)::text), md5((i+9)::text)
FROM generate_series(1, 100000) AS s(i);

\echo '    PROBLEM 4: wide_audit_log table (34 columns, 100k rows)'

-- =============================================================================
-- PROBLEM 5: Dead tuples — INSERT then DELETE without VACUUM
-- =============================================================================
-- PROBLEM  : Dead tuples bloat the table; sequential scans still visit them.
--            autovacuum is disabled on bloat_demo so tuples never reclaimed.
-- SHOWS IN : pg_gather → "Bloat Analysis"; pg_stat_user_tables.n_dead_tup.
-- LOOK FOR : n_dead_tup in the tens-of-thousands; bloat_ratio > 50%.
-- =============================================================================
\echo '    PROBLEM 5: Inserting then deleting 50k rows in bloat_demo (no vacuum)...'

INSERT INTO bloat_demo (payload)
SELECT repeat('dead_' || i::text, 40)
FROM generate_series(1, 50000) AS s(i);

-- Delete most rows — they become dead tuples, not freed space
DELETE FROM bloat_demo WHERE id % 10 != 0;   -- keeps only 10%, deletes 90%

-- Do NOT run VACUUM — leaving dead tuples visible to pg_gather
\echo '    PROBLEM 5: 50k inserts + ~45k deletes done, NO VACUUM run'

-- =============================================================================
-- PROBLEM 6: Slow-query simulation function
-- =============================================================================
-- PROBLEM  : Long-running queries hold locks, consume connection slots,
--            and appear at the top of pg_stat_statements by total time.
-- SHOWS IN : pg_gather → "Top SQL by Total Time" + "Long Running Queries".
-- LOOK FOR : mean_exec_time high; calls low but total_time dominates list.
-- =============================================================================
CREATE OR REPLACE FUNCTION ecommerce.simulate_slow_query(sleep_ms INT DEFAULT 500)
RETURNS TABLE (order_id INT, total NUMERIC, username TEXT, item_count BIGINT)
LANGUAGE plpgsql AS $$
BEGIN
    -- Simulate expensive computation / network wait
    PERFORM pg_sleep(sleep_ms / 1000.0);

    -- Also do a real multi-table join to produce realistic pg_stat_statements entries
    RETURN QUERY
    SELECT
        o.id,
        o.total,
        u.username,
        COUNT(oi.id)
    FROM ecommerce.orders o
    JOIN ecommerce.users      u  ON u.id  = o.user_id
    JOIN ecommerce.order_items oi ON oi.order_id = o.id
    WHERE o.status = 'delivered'
    GROUP BY o.id, o.total, u.username
    ORDER BY o.total DESC
    LIMIT 10;
END;
$$;

\echo '    PROBLEM 6: simulate_slow_query() function created'

-- =============================================================================
-- Summary verification
-- =============================================================================
\echo ''
\echo '>>> [03_problems.sql] Problem objects created. Verification:'

SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size
FROM pg_tables
WHERE schemaname = 'ecommerce'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Show indexes per table (manual check for duplicates)
SELECT tablename, indexname
FROM pg_indexes
WHERE schemaname = 'ecommerce'
  AND tablename = 'search_log'
ORDER BY tablename, indexname;

-- Show dead tuple count in bloat_demo
SELECT relname, n_dead_tup, n_live_tup
FROM pg_stat_user_tables
WHERE relname = 'bloat_demo';

\echo '>>> [03_problems.sql] complete.'
