#!/usr/bin/env bash
# =============================================================================
# _common.sh — shared helpers sourced by every lab script
# Not meant to be run directly.
# =============================================================================

# Load .env from the project root (one level up from labs/)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "${PROJECT_ROOT}/.env" ] && source "${PROJECT_ROOT}/.env"

PG_CONTAINER="${PG_CONTAINER:-pg_gather_db}"
POSTGRES_USER="${POSTGRES_USER:-pgadmin}"
POSTGRES_DB="${POSTGRES_DB:-labdb}"

# Colours
BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

banner() { echo -e "\n${GREEN}${BOLD}╔══════════════════════════════════════════════╗${NC}"; \
           echo -e "${GREEN}${BOLD}  $*${NC}"; \
           echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════╝${NC}\n"; }

step()   { echo -e "\n${CYAN}${BOLD}▶ $*${NC}"; }

# Run SQL inside the postgres container
psql_exec() {
    docker exec "$PG_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
        --pset=border=2 -c "$1"
}

# Run SQL, return raw value (no formatting)
psql_val() {
    docker exec "$PG_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
        --no-align --tuples-only -c "$1"
}

# Generate a pg_gather report; returns the report filename
run_report() {
    cd "$PROJECT_ROOT"
    docker compose run --rm pg_gather 2>&1 | tee /tmp/pg_gather_last.log
    grep "HTML :" /tmp/pg_gather_last.log | awk '{print $NF}' || true
}
