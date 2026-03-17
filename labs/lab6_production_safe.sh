#!/usr/bin/env bash
# =============================================================================
# Lab 6 — Production-Safe pg_gather Capture
# Goal : Show the three safety practices you MUST follow when running
#        pg_gather on a live production server:
#          1. nice -n 10       → low OS CPU priority
#          2. Audit log        → record who ran it and when
#          3. Timestamped file → never overwrite a previous capture
#
# Key point: pg_gather runs 26 seconds of SQL against the server.
# On a busy production system those 26s can spike load if not throttled.
# =============================================================================
set -euo pipefail

source "$(dirname "$0")/_common.sh"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

banner "LAB 6 — Production-Safe pg_gather Capture"

AUDIT_LOG="${PROJECT_ROOT}/logs/pg_gather_audit.log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_NAME="report_prodsafe_${TIMESTAMP}.html"
TSV_NAME="gather_prodsafe_${TIMESTAMP}.tsv"

# ── Step 1: explain what we're about to do ────────────────────────────────────
step "Step 1/4 — Safety measures explanation"
cat <<'INFO'
  Three things that matter before running pg_gather in production:

  ① nice -n 10
    Runs the psql process at lower OS scheduler priority.
    Other processes (your app) get CPU preference over pg_gather.
    Does NOT reduce the SQL load on postgres itself — use pg_sleep
    between queries if you need that (pg_gather doesn't support it yet).

  ② Audit log (stdout + stderr to file)
    Every pg_gather run is logged with: who, when, how long, report name.
    Useful for post-incident review: "who captured this and when?"
    Also captures errors if pg_gather partially fails.

  ③ Timestamped filename
    report_YYYYMMDD_HHMMSS.html — never overwrites a previous report.
    Two reports taken during an incident can be compared side-by-side.
INFO

# ── Step 2: write the audit log header ────────────────────────────────────────
step "Step 2/4 — Writing audit log entry"
mkdir -p "$(dirname "$AUDIT_LOG")"

{
    echo "=========================================="
    echo "pg_gather capture"
    echo "Timestamp  : $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "Run by     : $(whoami)@$(hostname)"
    echo "Target DB  : ${POSTGRES_DB:-labdb}@${PG_CONTAINER:-pg_gather_db}"
    echo "Report     : ${REPORT_NAME}"
    echo "=========================================="
} | tee -a "$AUDIT_LOG"

echo "  Audit log: ${AUDIT_LOG}"

# ── Step 3: run pg_gather with nice ───────────────────────────────────────────
step "Step 3/4 — Running pg_gather with nice -n 10 (low OS priority)"
echo "  Starting at $(date '+%H:%M:%S') ..."

START_TS=$(date +%s)

# nice -n 10 lowers the priority of the docker compose run process.
# All child processes inherit the niceness, including psql inside the container.
# >> $AUDIT_LOG captures both stdout and stderr for auditing.
nice -n 10 docker compose run --rm \
    -e PGHOST="${PG_CONTAINER:-pg_gather_db}" \
    -e PGPORT=5432 \
    -e PGUSER="${POSTGRES_USER:-pgadmin}" \
    -e PGPASSWORD="${POSTGRES_PASSWORD:-pgadmin123}" \
    -e PGDATABASE="${POSTGRES_DB:-labdb}" \
    pg_gather \
    bash -c "
        GATHER_DIR=/pg_gather
        WORK_DB=\"pg_gather_prodsafe_\$(date +%s)\"
        TSV_FILE=\"/reports/${TSV_NAME}\"
        REPORT_FILE=\"/reports/${REPORT_NAME}\"

        psql -h \"\$PGHOST\" -p \"\$PGPORT\" -U \"\$PGUSER\" -d \"\$PGDATABASE\" \
            -X -q -A -t -f \"\${GATHER_DIR}/gather.sql\" > \"\$TSV_FILE\"

        psql -h \"\$PGHOST\" -p \"\$PGPORT\" -U \"\$PGUSER\" -d postgres \
            -c \"CREATE DATABASE \${WORK_DB};\" -q

        { cat \"\${GATHER_DIR}/gather_schema.sql\"; cat \"\$TSV_FILE\"; } \
            | psql -h \"\$PGHOST\" -p \"\$PGPORT\" -U \"\$PGUSER\" -d \"\$WORK_DB\" \
                   -X -q -f - -c 'ANALYZE' 2>/dev/null

        psql -h \"\$PGHOST\" -p \"\$PGPORT\" -U \"\$PGUSER\" -d \"\$WORK_DB\" \
            -X -f \"\${GATHER_DIR}/gather_report.sql\" > \"\$REPORT_FILE\"

        psql -h \"\$PGHOST\" -p \"\$PGPORT\" -U \"\$PGUSER\" -d postgres \
            -c \"DROP DATABASE \${WORK_DB};\" -q

        echo \"Report: \$REPORT_FILE\"
        echo \"Size  : \$(du -sh \$REPORT_FILE | cut -f1)\"
    " 2>&1 | tee -a "$AUDIT_LOG"

END_TS=$(date +%s)
ELAPSED=$((END_TS - START_TS))

# ── Step 4: write audit log footer ────────────────────────────────────────────
step "Step 4/4 — Audit log summary"
{
    echo "Completed  : $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "Duration   : ${ELAPSED}s"
    echo "Exit code  : $?"
    echo ""
} | tee -a "$AUDIT_LOG"

echo ""
echo "  Total elapsed: ${ELAPSED}s"
echo "  Report file  : ./reports/${REPORT_NAME}"

cat <<'GUIDE'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 LAB 6 — PRODUCTION SAFETY CHECKLIST
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

 ① TIMING
    Never run pg_gather during peak traffic — it holds queries
    open for ~26 seconds and may appear in lock wait analysis.
    Best: run at low-traffic hours OR immediately when an incident
    starts (to capture the live state before it resolves itself).

 ② PERMISSIONS
    pg_gather needs a superuser OR a role with:
      pg_read_all_stats, pg_monitor, pg_read_all_settings
    Never run as the application user — create a dedicated role.

 ③ AUDIT TRAIL
    The audit log at logs/pg_gather_audit.log shows:
    → Who ran it (user@host)
    → Exactly when (timestamp)
    → How long it took
    → Which report was generated
    This log is your evidence trail for incident reviews.

 ④ COMPARE REPORTS
    Run pg_gather immediately when incident starts (DURING)
    Run pg_gather after incident resolves (AFTER)
    The difference between the two reports shows what changed.

 AUDIT LOG CONTENTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
GUIDE

cat "$AUDIT_LOG"
