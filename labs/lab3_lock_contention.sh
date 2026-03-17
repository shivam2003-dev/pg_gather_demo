#!/usr/bin/env bash
# =============================================================================
# Lab 3 — Lock Contention
# Goal : Create a live lock chain (one session blocking another) while
#         pg_gather is running so the lock section captures it.
#
# Technique:
#   Session A  — BEGIN + UPDATE row 1 + pg_sleep(45)   ← holds the lock
#   Session B  — UPDATE same row                        ← blocks waiting
#   pg_gather runs WHILE both sessions are active       ← captures the chain
#   pg_terminate_backend() releases everything cleanly
# =============================================================================
set -euo pipefail

source "$(dirname "$0")/_common.sh"

banner "LAB 3 — Lock Contention"

TARGET_ORDER_ID=1

step "Step 1/5 — Confirming target row exists (order id=${TARGET_ORDER_ID})"
psql_exec "SELECT id, status, total FROM ecommerce.orders WHERE id = ${TARGET_ORDER_ID};"

# ── Start Session A — holds an exclusive row lock ─────────────────────────────
step "Step 2/5 — Session A: BEGIN + UPDATE + pg_sleep(45)  [background]"
echo "  Session A will hold a row lock on orders.id=${TARGET_ORDER_ID} for 45 seconds"

docker exec -d "$PG_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
BEGIN;
UPDATE ecommerce.orders SET status = 'processing' WHERE id = ${TARGET_ORDER_ID};
SELECT pg_sleep(45);
ROLLBACK;"

sleep 2   # Give Session A time to acquire the lock

# ── Confirm Session A is running ──────────────────────────────────────────────
echo "  Session A backend PID:"
psql_exec "
SELECT pid, state, wait_event_type, wait_event,
       left(query, 60) AS query
FROM   pg_stat_activity
WHERE  query LIKE '%pg_sleep%'
  AND  state IN ('active','idle in transaction');"

# ── Start Session B — will block immediately ──────────────────────────────────
step "Step 3/5 — Session B: UPDATE same row  [will block on Session A's lock]"

docker exec -d "$PG_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
UPDATE ecommerce.orders SET status = 'shipped' WHERE id = ${TARGET_ORDER_ID};"

sleep 2   # Give Session B time to block

# ── Show the live lock chain ──────────────────────────────────────────────────
step "Step 4/5 — Live lock chain visible in pg_stat_activity"
psql_exec "
SELECT
    blocked.pid                       AS blocked_pid,
    blocked.state                     AS blocked_state,
    left(blocked.query, 50)           AS blocked_query,
    blocking.pid                      AS blocking_pid,
    blocking.state                    AS blocking_state,
    left(blocking.query, 50)          AS blocking_query
FROM   pg_stat_activity AS blocked
JOIN   pg_stat_activity AS blocking
       ON  blocking.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE  cardinality(pg_blocking_pids(blocked.pid)) > 0;"

# ── Generate pg_gather report WHILE lock is active ───────────────────────────
step "Step 5a/5 — Running pg_gather NOW (lock chain is live)"
echo "  ⚡ pg_gather will capture the active lock chain in its report"
cd "$(dirname "$0")/.."
docker compose run --rm pg_gather

# ── Release the lock ─────────────────────────────────────────────────────────
step "Step 5b/5 — Releasing lock via pg_terminate_backend()"
# The terminated session emits a FATAL to stderr — suppress it with 2>/dev/null
# and || true so set -e doesn't exit the script
docker exec "$PG_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
    --pset=border=2 -c "
SELECT pg_terminate_backend(pid),
       left(query, 50) AS terminated_query
FROM   pg_stat_activity
WHERE  query LIKE '%pg_sleep%'
  AND  state IN ('active','idle in transaction');" 2>/dev/null || true

sleep 2

psql_exec "
SELECT count(*) AS remaining_blocked_sessions
FROM   pg_stat_activity
WHERE  cardinality(pg_blocking_pids(pid)) > 0;"

# ── What to look for ─────────────────────────────────────────────────────────
cat <<'GUIDE'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 LAB 3 — WHAT TO LOOK FOR IN THE REPORT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

 LOCK / BLOCKING SECTION
 ────────────────────────
 → Look for "Lock Waits" or "Blocking Queries" section
 → You should see two rows:
     Blocker PID  → the session running pg_sleep(45)
     Blocked PID  → the session waiting for the UPDATE

 WHAT THE LOCK CHAIN MEANS IN PRODUCTION
 ────────────────────────────────────────
 → The blocker's query (pg_sleep) looks innocent — in prod it
   would be a long-running transaction holding a row lock
 → The blocked session cannot proceed until the blocker commits
   or is terminated — if 10 sessions are waiting, they all pile up
 → This is how a single slow transaction causes an "outage"
   without any single query being technically broken

 ACTIVE SESSIONS / WAIT EVENTS
 ──────────────────────────────
 → pg_gather's session snapshot shows wait_event = 'relation'
   or 'tuple' for the blocked session
 → wait_event_type = 'Lock' is the giveaway

 CROSS-REFERENCE
 ───────────────
 → Compare the two reports (Lab 1 baseline vs this one)
   The lock section should be empty in Lab 1 and populated here
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
GUIDE
