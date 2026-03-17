-- =============================================================================
-- 01_extensions.sql
-- Runs once when the data directory is first initialised.
-- Creates extensions needed for pg_gather and the labs.
-- =============================================================================

\echo '>>> Creating extensions...'

-- pg_stat_statements
-- Must already be in shared_preload_libraries (set in conf.d/custom.conf).
-- This CREATE EXTENSION makes the view visible in the current database.
-- pg_gather reads: pg_stat_statements, pg_stat_statements_info
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- pg_buffercache
-- Exposes one row per shared buffer. pg_gather uses it for the
-- "Buffer Cache Contents" section — showing which relations fill the cache.
CREATE EXTENSION IF NOT EXISTS pg_buffercache;

-- pg_prewarm (optional but educational)
-- Lets you manually load relation pages into shared_buffers.
-- Useful for before/after cache-hit ratio comparisons in the labs.
CREATE EXTENSION IF NOT EXISTS pg_prewarm;

-- ── Verify all three loaded correctly ────────────────────────────────────────
\echo '>>> Verifying extensions:'
SELECT name, default_version, installed_version, comment
FROM   pg_available_extensions
WHERE  name IN ('pg_stat_statements', 'pg_buffercache', 'pg_prewarm')
ORDER  BY name;

-- NOTE: We intentionally do NOT query pg_stat_statements here.
-- The view is only accessible after pg_stat_statements is loaded via
-- shared_preload_libraries.  00_config.sh patches postgresql.conf so that
-- shared_preload_libraries is active on the REAL server startup — but the
-- temp server running these init scripts started before that patch, so the
-- library is not yet loaded.  Querying the view here would abort the init
-- chain and prevent 02_seed.sql / 03_problems.sql from running.
-- Verification is done manually (or in lab scripts) after first boot.

\echo '>>> 01_extensions.sql complete.'
