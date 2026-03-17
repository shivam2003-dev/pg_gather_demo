#!/usr/bin/env bash
# =============================================================================
# setup.sh — pg_gather two-stage report runner
#
# How pg_gather works (important to understand):
#   STAGE 1 — gather.sql runs against the TARGET postgres and outputs a TSV
#             file containing raw diagnostic data (pg_stat_*, pg_class, etc.)
#   STAGE 2 — That TSV is imported into a SEPARATE postgres database where
#             gather_report.sql generates the final HTML report.
#
# We handle both stages using the same postgres container:
#   Stage 1 → runs against $PGDATABASE (the lab DB)
#   Stage 2 → uses a temp DB called pg_gather_work (auto-created & dropped)
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
banner() { echo -e "${GREEN}[pg_gather]${NC} $*"; }
warn()   { echo -e "${YELLOW}[pg_gather] WARN:${NC} $*"; }
die()    { echo -e "${RED}[pg_gather] ERROR:${NC} $*" >&2; exit 1; }

# ── Step 1: wait for Postgres ─────────────────────────────────────────────────
banner "Waiting for PostgreSQL at ${PGHOST}:${PGPORT} ..."
MAX_WAIT=60; WAITED=0
until pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -q; do
    [ "$WAITED" -ge "$MAX_WAIT" ] && die "PostgreSQL not ready after ${MAX_WAIT}s"
    sleep 2; WAITED=$((WAITED + 2))
done
banner "PostgreSQL is ready (waited ${WAITED}s)"

# ── Step 2: verify pg_stat_statements ────────────────────────────────────────
banner "Checking pg_stat_statements ..."
PG_SS=$(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" \
    --no-align --tuples-only \
    -c "SELECT count(*) FROM pg_extension WHERE extname = 'pg_stat_statements';")
[ "$PG_SS" = "1" ] || die "pg_stat_statements extension not found"
banner "pg_stat_statements: OK"

# ── Step 3: verify gather scripts exist ──────────────────────────────────────
GATHER_DIR="/pg_gather"
[ -f "${GATHER_DIR}/gather.sql" ]        || die "gather.sql not found"
[ -f "${GATHER_DIR}/gather_schema.sql" ] || die "gather_schema.sql not found"
[ -f "${GATHER_DIR}/gather_report.sql" ] || die "gather_report.sql not found"
banner "All pg_gather scripts found"

# ── Stage 1: collect diagnostic data from the lab postgres ───────────────────
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TSV_FILE="/reports/gather_${TIMESTAMP}.tsv"
REPORT_FILE="/reports/report_${TIMESTAMP}.html"
WORK_DB="pg_gather_work_${TIMESTAMP}"

banner "STAGE 1 — Running gather.sql against ${PGDATABASE} ..."
START_TS=$(date +%s)

psql \
    -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" \
    -X -q -A -t \
    -f "${GATHER_DIR}/gather.sql" \
    > "$TSV_FILE"

STAGE1_ELAPSED=$(( $(date +%s) - START_TS ))
TSV_SIZE=$(wc -c < "$TSV_FILE")
[ "$TSV_SIZE" -lt 100 ] && die "TSV output is only ${TSV_SIZE} bytes — gather.sql may have failed"
banner "STAGE 1 done in ${STAGE1_ELAPSED}s — TSV: $(du -sh "$TSV_FILE" | cut -f1)"

# ── Stage 2: import TSV + generate HTML report ────────────────────────────────
banner "STAGE 2 — Creating work database ${WORK_DB} ..."
psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres \
    -c "CREATE DATABASE ${WORK_DB};" -q

banner "STAGE 2 — Importing TSV data into ${WORK_DB} ..."
{ cat "${GATHER_DIR}/gather_schema.sql"; cat "$TSV_FILE"; } \
    | psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$WORK_DB" \
           -X -q -f - -c "ANALYZE" 2>/dev/null

banner "STAGE 2 — Generating HTML report ..."
START_TS=$(date +%s)

psql \
    -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$WORK_DB" \
    -X -f "${GATHER_DIR}/gather_report.sql" \
    > "$REPORT_FILE"

STAGE2_ELAPSED=$(( $(date +%s) - START_TS ))

# ── Clean up work database ────────────────────────────────────────────────────
psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres \
    -c "DROP DATABASE ${WORK_DB};" -q
banner "Work database ${WORK_DB} dropped"

# ── Final check ───────────────────────────────────────────────────────────────
REPORT_SIZE=$(wc -c < "$REPORT_FILE")
if [ "$REPORT_SIZE" -lt 5000 ]; then
    warn "Report is only ${REPORT_SIZE} bytes — check for errors above"
else
    banner "HTML report generated in ${STAGE2_ELAPSED}s"
    banner "TSV  : ${TSV_FILE}"
    banner "HTML : ${REPORT_FILE}"
    banner "Size : $(du -sh "$REPORT_FILE" | cut -f1)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Open:   open ${REPORT_FILE/\/reports/.\/reports}"
echo " Or run: make serve  →  http://localhost:8080"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
