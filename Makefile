# =============================================================================
# pg_gather Learning Lab — Makefile
# =============================================================================
.PHONY: up down clean seed setup report \
        lab1 lab2 lab3 lab4 lab5 lab6 lab7 \
        logs psql serve open help

# ── Colour helpers ────────────────────────────────────────────────────────────
BOLD  := \033[1m
GREEN := \033[0;32m
NC    := \033[0m

# Read variables from .env if it exists
-include .env
PG_CONTAINER ?= pg_gather_db
POSTGRES_USER ?= pgadmin
POSTGRES_DB   ?= labdb

# ── Lifecycle ─────────────────────────────────────────────────────────────────

## up: Build images and start postgres in the background; wait for healthy
up:
	@echo "$(GREEN)$(BOLD)▶ Starting pg_gather lab stack...$(NC)"
	docker compose up -d --build
	@echo "$(GREEN)Waiting for postgres to be healthy...$(NC)"
	@until [ "$$(docker inspect --format='{{.State.Health.Status}}' $(PG_CONTAINER) 2>/dev/null)" = "healthy" ]; do \
		printf '.'; sleep 2; \
	done
	@echo ""
	@echo "$(GREEN)✔ Postgres is healthy. Run: make psql$(NC)"

## down: Stop containers (keeps data volume)
down:
	@echo "$(GREEN)$(BOLD)▶ Stopping containers...$(NC)"
	docker compose down

## clean: Stop containers AND delete the data volume (full reset)
clean:
	@echo "$(GREEN)$(BOLD)▶ Full reset — removing containers and data volume...$(NC)"
	docker compose down -v
	@echo "$(GREEN)✔ Done. Run 'make up' to start fresh.$(NC)"

# ── Data ──────────────────────────────────────────────────────────────────────

## seed: Re-run seed + problems SQL against the running database
seed:
	@echo "$(GREEN)$(BOLD)▶ Running seed and problems SQL...$(NC)"
	docker exec -i $(PG_CONTAINER) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) \
		-f /docker-entrypoint-initdb.d/02_seed.sql
	docker exec -i $(PG_CONTAINER) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) \
		-f /docker-entrypoint-initdb.d/03_problems.sql
	@echo "$(GREEN)✔ Seed complete. Run: make psql → \\dt ecommerce.*$(NC)"

# ── pg_gather ─────────────────────────────────────────────────────────────────

## setup: Run setup.sh (full two-stage pg_gather report — same as 'make report')
setup: report

## report: Generate a timestamped pg_gather HTML report in ./reports/
report:
	@echo "$(GREEN)$(BOLD)▶ Generating pg_gather report...$(NC)"
	docker compose run --rm pg_gather
	@echo "$(GREEN)✔ Report saved to ./reports/ — run: make serve$(NC)"

# ── Labs ──────────────────────────────────────────────────────────────────────

## lab1: Baseline report — what to check first in a fresh pg_gather HTML
lab1:
	@echo "$(GREEN)$(BOLD)▶ Lab 1 — Baseline report$(NC)"
	bash labs/lab1_baseline_report.sh

## lab2: Slow queries — capture via pg_stat_statements
lab2:
	@echo "$(GREEN)$(BOLD)▶ Lab 2 — Slow queries$(NC)"
	bash labs/lab2_slow_queries.sh

## lab3: Lock contention — capture a live lock chain in the report
lab3:
	@echo "$(GREEN)$(BOLD)▶ Lab 3 — Lock contention$(NC)"
	bash labs/lab3_lock_contention.sh

## lab4: Bloat analysis — before and after VACUUM
lab4:
	@echo "$(GREEN)$(BOLD)▶ Lab 4 — Bloat analysis$(NC)"
	bash labs/lab4_bloat_analysis.sh

## lab5: Streaming replication — setup replica and observe lag
lab5:
	@echo "$(GREEN)$(BOLD)▶ Lab 5 — Streaming replication$(NC)"
	bash labs/lab5_replication.sh

## lab6: Production-safe capture — nice + audit trail
lab6:
	@echo "$(GREEN)$(BOLD)▶ Lab 6 — Production-safe capture$(NC)"
	bash labs/lab6_production_safe.sh

## lab7: Before/after tuning — add missing indexes, compare reports
lab7:
	@echo "$(GREEN)$(BOLD)▶ Lab 7 — Before/after tuning$(NC)"
	bash labs/lab7_before_after_tuning.sh

# ── Utilities ─────────────────────────────────────────────────────────────────

## logs: Follow postgres container logs
logs:
	docker compose logs -f postgres

## psql: Open an interactive psql shell in the postgres container
psql:
	docker exec -it $(PG_CONTAINER) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

## serve: Start the report viewer at http://localhost:8080
serve:
	@echo "$(GREEN)$(BOLD)▶ Serving reports at http://localhost:8080$(NC)"
	python3 serve_reports.py

## open: Open http://localhost:8080 in the default browser
open:
	open http://localhost:8080

# ── Help ──────────────────────────────────────────────────────────────────────

## help: Print this help message
help:
	@echo ""
	@echo "$(BOLD)pg_gather Learning Lab$(NC)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@grep -E '^## ' Makefile | sed 's/## //' | \
		awk -F': ' '{ printf "  $(GREEN)make %-22s$(NC) %s\n", $$1, $$2 }'
	@echo ""
