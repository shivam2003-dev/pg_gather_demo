# pg_gather Learning Lab

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791?style=flat-square&logo=postgresql&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Compose_v2-2496ED?style=flat-square&logo=docker&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)
![Labs](https://img.shields.io/badge/Labs-7-orange?style=flat-square)

A hands-on Docker lab for learning [pg_gather](https://github.com/jobinau/pg_gather) — the open-source PostgreSQL diagnostic tool that captures a full health snapshot of any PostgreSQL instance in a single HTML report. This project ships a realistic ecommerce schema, seven intentional performance problems, and seven guided lab scripts that teach you to read and act on pg_gather output.

## What is pg_gather?

pg_gather is a SQL-only diagnostic tool: you run one script against any PostgreSQL database and get a self-contained HTML report covering slow queries, lock chains, table bloat, autovacuum health, replication lag, and more. It requires no agent, no extension beyond `pg_stat_statements`, and no elevated OS access — making it safe to run on production systems.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Your Mac                                                   │
│                                                             │
│  make lab2          make serve                              │
│       │                  │                                  │
│       ▼                  ▼                                  │
│  ┌──────────┐    ┌───────────────┐    ┌──────────────────┐  │
│  │  lab     │    │serve_reports  │    │   Browser        │  │
│  │  script  │    │  .py :8080    │◄───│localhost:8080    │  │
│  └────┬─────┘    └───────┬───────┘    └──────────────────┘  │
│       │                  │                                  │
│       │ docker exec       │ reads                           │
│       ▼                  ▼                                  │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Docker Network                                      │   │
│  │                                                      │   │
│  │  ┌─────────────────┐      ┌────────────────────────┐ │   │
│  │  │  pg_gather_db   │◄─────│   pg_gather runner     │ │   │
│  │  │  PostgreSQL 16  │ SQL  │   (one-shot container) │ │   │
│  │  │  :5432          │      └────────────┬───────────┘ │   │
│  │  │                 │                   │ writes      │   │
│  │  │  ecommerce      │      ┌────────────▼───────────┐ │   │
│  │  │  schema +       │      │  ./reports/            │ │   │
│  │  │  7 problems     │      │  report_*.html         │◄┼───┘
│  │  └────────┬────────┘      └────────────────────────┘ │
│  │           │ WAL stream (lab5)                        │
│  │  ┌────────▼────────┐                                 │
│  │  │  pg_gather_     │                                 │
│  │  │  replica :5433  │                                 │
│  │  │  (profile:      │                                 │
│  │  │  replication)   │                                 │
│  │  └─────────────────┘                                 │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

| Tool | Version | Check |
|---|---|---|
| Docker Desktop | 4.x+ | `docker --version` |
| Docker Compose v2 | 2.x+ | `docker compose version` |
| Git | any | `git --version` |
| Make | any | `make --version` |
| Python 3 | 3.8+ (report viewer only) | `python3 --version` |

---

## Quick Start

```bash
git clone https://github.com/shivam2003-dev/pg_gather_demo.git
cd pg_gather_demo
cp .env.example .env
make up
make report
```

Open `./reports/report_*.html` in your browser, or run `make serve` → [http://localhost:8080](http://localhost:8080).

---

## Lab Guide

Each lab builds on a real performance problem planted in the database. Run them in order for the best learning experience.

### Lab 1 — Baseline Report
```bash
make lab1
```
**What you simulate:** A fresh pg_gather capture on an unknown instance.
**What to look for:**
- **Instance Information** → PostgreSQL version, uptime, `max_connections`, `shared_buffers`
- **Configuration** → `shared_preload_libraries = pg_stat_statements`
- **Table Statistics** → `seq_scan` count on the `events` table (no indexes)
- **Bloat** → `bloat_demo` shows high bloat ratio with `autovacuum_enabled = false`

**Key learning:** A pg_gather report gives you a complete picture of an instance in 30 seconds without SSH access. Read order: Instance → Config → Tables → Indexes → Bloat → Top SQL.

---

### Lab 2 — Slow Queries
```bash
make lab2
```
**What you simulate:** Three calls to a slow function + five full-table scans on a 200k-row unindexed table.
**What to look for:**
- **Top SQL by Total Time** → `simulate_slow_query()` dominates (~2400ms total, ~800ms mean)
- **Top SQL by Calls** → table-scan queries show high call counts
- **Table Statistics** → `events.seq_scan` jumps with each unindexed query

**Key learning:** `total_exec_time` vs `mean_exec_time` tell different stories. A function called 3× at 800ms mean is a different problem than a fast query called 10,000× per minute.

---

### Lab 3 — Lock Contention
```bash
make lab3
```
**What you simulate:** Session A holds a row lock via `BEGIN + UPDATE + pg_sleep(45)`. Session B tries to update the same row and blocks. pg_gather runs while the chain is live.
**What to look for:**
- **Blocking / Lock Waits section** → blocker PID and blocked PID with `wait_event = Lock`
- **Active Sessions** → `wait_event_type = Lock`, `wait_event = relation` or `tuple`

**Key learning:** A single long-running transaction is enough to cascade into an outage. pg_gather's lock section shows you the root cause (the blocker) and all downstream victims immediately.

---

### Lab 4 — Bloat Analysis
```bash
make lab4
```
**What you simulate:** 100k INSERT + 80k DELETE on `bloat_demo` (autovacuum disabled) → BEFORE report → `VACUUM ANALYZE` → AFTER report.
**What to look for:**
- **BEFORE** → `n_dead_tup` ~80k, `dead_pct` ~64–83%, table size ~91 MB
- **AFTER** → `n_dead_tup` ≈ 0, `last_vacuum` timestamp now visible
- **Autovacuum section** → `autovacuum_enabled = false` explains the bloat

**Key learning:** `VACUUM` marks dead pages reusable but doesn't shrink the file. `VACUUM FULL` rewrites and reclaims disk. Never disable autovacuum on a write-heavy table.

---

### Lab 5 — Streaming Replication
```bash
make lab5
```
**What you simulate:** pg_basebackup creates a hot-standby replica. Lab pauses the replica to create lag, generates a report during lag, then resumes.
**What to look for:**
- **Replication section (healthy)** → `state = streaming`, all lag columns ≈ 0
- **Replication section (lagging)** → `replay_lag` shows elapsed time, `lag_bytes` shows WAL backlog

**Key learning:** `replay_lag` is your RPO risk window — if the primary crashes while the replica is lagged, that's how much data you could lose.

---

### Lab 6 — Production-Safe Capture
```bash
make lab6
```
**What you simulate:** pg_gather run with `nice -n 10` (low OS priority) + full audit log to `logs/pg_gather_audit.log`.
**What to look for:**
- `logs/pg_gather_audit.log` → who ran it, when, how long, which report was saved

**Key learning:** Always `nice` the process, write an audit log, and use timestamped filenames so you can compare DURING vs AFTER reports side-by-side during an incident.

---

### Lab 7 — Before/After Tuning
```bash
make lab7
```
**What you simulate:** Missing indexes on `events(event_type)` and `events(user_id)` are added with `CREATE INDEX CONCURRENTLY`. pg_gather reports before and after.
**What to look for:**
- **Table Statistics BEFORE** → `seq_scan` high, `idx_scan = 0`
- **Table Statistics AFTER** → `seq_scan ≈ 0`, `idx_scan` high
- **Top SQL BEFORE** → event queries in top-5 by total time
- **Top SQL AFTER** → event queries drop off the list entirely

**Key learning:** `CREATE INDEX CONCURRENTLY` is safe on a live system. Always run `ANALYZE` after to give the planner fresh statistics.

---

## Report Sections Explained

| Section | What It Shows | When To Use It |
|---|---|---|
| **Instance Information** | PG version, uptime, connections, shared_buffers | First thing to read on any new instance |
| **Configuration Report** | Non-default GUC parameters | Spot misconfiguration, verify your changes loaded |
| **Database Sizes** | Per-database and per-schema size | Find which schema/DB is consuming disk |
| **Table Statistics** | seq_scan, idx_scan, n_dead_tup, n_live_tup | Find tables with missing indexes or bloat |
| **Index Information** | All indexes, size, unused indexes | Find duplicate, unused, or missing indexes |
| **Bloat Analysis** | Estimated wasted bytes per table/index | Identify tables that need VACUUM FULL |
| **Autovacuum** | Last vacuum time, tables overdue | Find tables autovacuum can't keep up with |
| **Top SQL** | Queries by total time, mean time, calls | Find the slowest and most-called queries |
| **Blocking / Locks** | Lock chains, blocked sessions, wait events | Diagnose contention during incidents |
| **Active Sessions** | Current backends, state, wait events | Snapshot of what the server is doing right now |
| **Replication** | WAL sender state, lag bytes and time | Monitor replica health and RPO risk |
| **Checkpoint** | Checkpoint frequency and write spread | Tune `checkpoint_completion_target` |
| **Cache Hit Ratio** | Buffer hits vs disk reads per relation | Size `shared_buffers` correctly |

---

## Interpreting Key Findings

### How to spot a slow query
1. Open **Top SQL** → sort by **Total Time** descending
2. High `total_exec_time` + low `calls` = slow function or complex query
3. High `calls` + low `mean_exec_time` = high-frequency query; small gains matter
4. Check `shared_blks_read` vs `shared_blks_hit` — a low cache hit ratio means the query is doing disk I/O

### How to read a lock chain
1. Open **Blocking** section
2. The **blocker** row shows the session holding the lock (`state = idle in transaction`)
3. The **blocked** rows show sessions waiting — in production there can be dozens
4. Fix: find the blocker's query in **Top SQL**, reduce transaction duration, or add `statement_timeout`

### How to measure bloat severity

| `dead_pct` | Action |
|---|---|
| < 10% | Normal — autovacuum is keeping up |
| 10–30% | Watch it; autovacuum may be under-resourced |
| 30–60% | Run manual `VACUUM ANALYZE` |
| > 60% | Schedule `VACUUM FULL` in a maintenance window (locks the table) |

### What bad autovacuum looks like
- `last_autovacuum = never` on a table that receives writes → autovacuum is disabled or blocked
- `n_dead_tup` grows between two reports → autovacuum is running but can't keep up
- Fix: lower `autovacuum_vacuum_scale_factor`, raise `autovacuum_vacuum_cost_delay`

---

## Production Usage Tips

1. **Run at the right moment** — Capture immediately when an incident starts. The snapshot at T+0 is your most valuable evidence.

2. **Use `nice -n 10`** — Reduces OS scheduler priority for the psql process. Your application keeps CPU preference. `make lab6` demonstrates this pattern.

3. **Write an audit log** — Log who ran pg_gather, when, and which report was saved. During post-incident review you need to know which capture corresponds to which event.

4. **Compare two reports** — One capture during the problem + one after the fix. The diff tells the full story. `make lab7` shows this workflow.

5. **Minimum permissions** — pg_gather needs `pg_read_all_stats`, `pg_monitor`, and `pg_read_all_settings`. Create a dedicated role — never run as the application user.

6. **Hot standby is safe** — Run pg_gather against the replica without touching the primary. The replica report captures its own buffer stats, wait events, and replication lag independently.

---

## Troubleshooting

**Postgres container not starting**
```bash
docker compose logs postgres | tail -30
# Common cause: port 5432 already in use
# Fix: change POSTGRES_PORT in .env then: make clean && make up
```

**Empty Top SQL section**
```bash
# pg_stat_statements starts empty — run some queries first
make lab2   # generates load, then captures report
```

**pg_stat_statements not loading**
```bash
docker exec pg_gather_db psql -U pgadmin -d labdb \
  -c "SHOW shared_preload_libraries;"
# Should show: pg_stat_statements
# If not: docker compose build --no-cache && make clean && make up
```

**Replica not connecting (lab5)**
```bash
docker logs pg_gather_replica | tail -20
# "started streaming WAL" = healthy (the FATAL db messages are harmless noise)
# Container restarting = primary not healthy yet, wait 30s and retry
```

**Address already in use (make serve)**
```bash
pkill -f "python3 serve_reports.py" && make serve
```

---

## Repository Structure

```
pg_gather_demo/
│
├── docker-compose.yml          # Primary + replica services + pg_gather runner
├── Makefile                    # All lab commands (make help for full list)
├── .env.example                # Environment variable template
├── serve_reports.py            # Local report viewer at http://localhost:8080
│
├── postgres/                   # Custom PostgreSQL 16 image
│   ├── Dockerfile              # Extends postgres:16-bookworm, adds tools
│   ├── pg_hba.conf             # Auth: trust local, scram-sha-256 for Docker network
│   ├── replica_entrypoint.sh   # Standby setup: pg_basebackup on first boot
│   ├── conf.d/
│   │   └── custom.conf         # All custom GUCs (pg_stat_statements, work_mem, etc.)
│   └── initdb/                 # Scripts run once on first boot (alphabetical order)
│       ├── 00_config.sh        # Appends include_dir to postgresql.conf
│       ├── 01_extensions.sql   # CREATE EXTENSION pg_stat_statements/pg_buffercache
│       ├── 02_seed.sql         # Ecommerce schema: users, products, orders (~300k rows)
│       └── 03_problems.sql     # 6 intentional performance problems
│
├── pg_gather/                  # pg_gather runner container
│   ├── Dockerfile              # Clones pg_gather repo, adds setup.sh
│   └── setup.sh                # Two-stage report: gather.sql → TSV → HTML
│
├── labs/                       # Lab scripts (run via make lab1 … make lab7)
│   ├── _common.sh              # Shared helpers: banner, psql_exec, run_report
│   ├── lab1_baseline_report.sh # First report — reading order guide
│   ├── lab2_slow_queries.sh    # pg_stat_statements — slow function + table scans
│   ├── lab3_lock_contention.sh # Live lock chain captured in report
│   ├── lab4_bloat_analysis.sh  # Dead tuples before/after VACUUM
│   ├── lab5_replication.sh     # Streaming replica + lag simulation
│   ├── lab6_production_safe.sh # nice + audit log production pattern
│   └── lab7_before_after_tuning.sh # Missing index → CREATE INDEX → compare reports
│
├── reports/                    # Generated HTML reports
│   └── .gitkeep
│
└── logs/                       # Audit log from lab6
    └── pg_gather_audit.log
```

---

## License

MIT — see [LICENSE](LICENSE).

Built for learning. The intentional performance problems are features, not bugs.
