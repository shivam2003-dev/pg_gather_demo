#!/usr/bin/env bash
# =============================================================================
# Lab 5 — Streaming Replication
# Goal : Set up a hot-standby replica, verify WAL streaming, simulate
#        replication lag, and capture it all in pg_gather reports.
#
# How it works:
#   Primary  → pg_gather_db (already running)
#   Replica  → pg_gather_replica (started by this script via Docker profile)
#   The replica uses pg_basebackup on first boot, then streams WAL.
# =============================================================================
set -euo pipefail

source "$(dirname "$0")/_common.sh"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

banner "LAB 5 — Streaming Replication"

# ── Step 1: verify primary replication settings ───────────────────────────────
step "Step 1/7 — Checking primary replication readiness"
psql_exec "
SELECT name, setting, unit
FROM   pg_settings
WHERE  name IN ('wal_level','max_wal_senders','wal_keep_size','hot_standby')
ORDER  BY name;"

WAL_LEVEL=$(psql_val "SELECT setting FROM pg_settings WHERE name='wal_level';")
if [ "$WAL_LEVEL" != "replica" ] && [ "$WAL_LEVEL" != "logical" ]; then
    echo "ERROR: wal_level is '${WAL_LEVEL}', need 'replica' or higher"
    echo "       Add: wal_level = replica   to conf.d/custom.conf and restart"
    exit 1
fi
echo "  wal_level = ${WAL_LEVEL}  ✓"

# ── Step 2: create replication user on primary ────────────────────────────────
step "Step 2/7 — Creating replication user on primary"
psql_exec "
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'replicator') THEN
        CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replicator123';
        RAISE NOTICE 'Created role: replicator';
    ELSE
        RAISE NOTICE 'Role replicator already exists';
    END IF;
END\$\$;"

psql_exec "SELECT rolname, rolreplication, rolcanlogin FROM pg_roles WHERE rolname='replicator';"

# ── Step 3: start the replica container ──────────────────────────────────────
step "Step 3/7 — Starting replica container (pg_basebackup on first boot)"
echo "  This takes 30-60 seconds on first run (copying data from primary) ..."
cd "$PROJECT_ROOT"
docker compose --profile replication up -d postgres-replica

echo "  Waiting for replica to be healthy ..."
for i in $(seq 1 30); do
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' pg_gather_replica 2>/dev/null || echo "missing")
    echo "    attempt ${i}/30: ${STATUS}"
    if [ "$STATUS" = "healthy" ]; then break; fi
    sleep 5
done

# ── Step 4: verify replication is streaming ───────────────────────────────────
step "Step 4/7 — Verifying streaming replication on primary"
psql_exec "
SELECT client_addr,
       state,
       sent_lsn,
       write_lsn,
       flush_lsn,
       replay_lsn,
       write_lag,
       flush_lag,
       replay_lag,
       sync_state
FROM   pg_stat_replication;"

echo "  state should be 'streaming' — if empty, replica is still catching up"

step "Step 4b/7 — Verify replica is in hot-standby mode"
docker exec pg_gather_replica psql \
    -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
    --pset=border=2 \
    -c "SELECT pg_is_in_recovery() AS is_standby, pg_last_wal_receive_lsn() AS receive_lsn, pg_last_wal_replay_lsn() AS replay_lsn;"

# ── Step 5: run pg_gather on primary (captures replication stats) ─────────────
step "Step 5/7 — Generating pg_gather report with replication active"
cd "$PROJECT_ROOT"
docker compose run --rm pg_gather

# ── Step 6: simulate lag by pausing replica ───────────────────────────────────
step "Step 6/7 — Simulating replication lag"
echo "  Pausing replica container ..."
docker pause pg_gather_replica

echo "  Writing 10k rows to primary (will create WAL the replica can't consume) ..."
psql_exec "
INSERT INTO ecommerce.orders (user_id, status, total, created_at)
SELECT 1 + (random() * 49999)::int,
       'pending',
       round((random() * 100 + 10)::numeric, 2),
       now()
FROM generate_series(1, 10000);"

echo "  Checking replication lag while replica is paused ..."
psql_exec "
SELECT client_addr,
       state,
       replay_lag,
       pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS lag_bytes
FROM   pg_stat_replication;"

echo "  Generating pg_gather report DURING lag ..."
cd "$PROJECT_ROOT"
docker compose run --rm pg_gather

echo "  Resuming replica ..."
docker unpause pg_gather_replica
sleep 3

echo "  Lag after resume:"
psql_exec "
SELECT state, replay_lag,
       pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS remaining_lag_bytes
FROM   pg_stat_replication;"

# ── Step 7: clean up replica (optional) ──────────────────────────────────────
step "Step 7/7 — Replica is running. To stop it:"
echo "  docker compose --profile replication stop postgres-replica"
echo "  docker compose --profile replication down --volumes   ← removes replica volume too"

cat <<'GUIDE'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 LAB 5 — WHAT TO LOOK FOR IN THE REPORT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

 REPLICATION SECTION  (two reports: normal vs during-lag)
 ─────────────────────
 Report 1 (replication healthy):
   → state = streaming, all lag columns ≈ 0
   → sent_lsn ≈ flush_lsn ≈ replay_lsn  (all caught up)

 Report 2 (replica paused):
   → replay_lag column shows elapsed time since last apply
   → lag_bytes = how much WAL the replica needs to catch up
   → In production this is the "RPO risk window" — if primary
     crashes, replica is this many bytes/seconds behind

 WHAT pg_stat_replication COLUMNS MEAN
 ─────────────────────────────────────
   sent_lsn    → how much WAL primary has SENT
   write_lsn   → how much replica has WRITTEN to disk
   flush_lsn   → how much replica has FSYNCED
   replay_lsn  → how much replica has APPLIED (visible to queries)
   replay_lag  → time between primary commit and replica apply

 HOT STANDBY (pg_is_in_recovery = true)
 ──────────────────────────────────────
 → The replica accepts read-only queries
 → pg_gather can be run against the replica to capture its own
   wait events, connection counts, and buffer stats independently
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
GUIDE
