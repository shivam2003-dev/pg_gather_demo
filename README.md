# pg_gather Learning Lab

A self-contained Docker environment for learning PostgreSQL performance diagnostics using [pg_gather](https://github.com/jobinau/pg_gather). It ships with a realistic e-commerce database (~300 k rows) pre-loaded with intentional performance problems, and generates interactive HTML diagnostic reports at the click of a command.

## What You Get

- PostgreSQL 16 with `pg_stat_statements`, `pg_buffercache`, and `pg_prewarm`
- Seed data: users (50 k), products (10 k), orders (100 k), order_items (~250 k), inventory (10 k)
- Six intentional performance problems to find and diagnose
- One-command HTML report generation via pg_gather
- All reports saved to `reports/` on your host machine

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (or Docker Engine + Compose plugin)
- ~1 GB free disk space for the database volume

## Quick Start

```bash
# 1. Clone and configure
git clone <repo-url>
cd pg_gather
cp .env.example .env          # edit .env if you want non-default credentials

# 2. Start the database (first boot seeds ~300k rows — takes ~30 s)
docker compose up postgres -d

# 3. Generate your first HTML report
docker compose run --rm pg_gather

# 4. Open the report
open reports/report_*.html    # macOS
# xdg-open reports/report_*.html   # Linux
```

## Documentation

| Guide | Description |
|---|---|
| [Setup Guide](docs/setup.md) | Full installation and first-boot walkthrough |
| [Generating Reports](docs/generating-reports.md) | Every command needed to produce and view HTML reports |
| [Connect External DB](docs/connect-external-db.md) | Run pg_gather against any existing PostgreSQL database |
| [Performance Problems Reference](docs/performance-problems.md) | What each intentional problem is and what to look for in the report |
| [PostgreSQL Config Reference](docs/postgres-config.md) | Explanation of every tuning knob in `custom.conf` |

## Project Layout

```
pg_gather/
├── docker-compose.yml          # Orchestrates postgres + pg_gather runner
├── .env.example                # Environment template → copy to .env
├── reports/                    # Generated TSV and HTML reports (gitignored)
├── logs/                       # PostgreSQL logs (gitignored)
├── postgres/
│   ├── Dockerfile
│   ├── pg_hba.conf
│   ├── conf.d/custom.conf      # PostgreSQL tuning
│   └── initdb/
│       ├── 00_config.sh        # Wires up conf.d on first boot
│       ├── 01_extensions.sql   # pg_stat_statements, pg_buffercache, pg_prewarm
│       ├── 02_seed.sql         # E-commerce schema + ~300k rows
│       └── 03_problems.sql     # Intentional performance problems
└── pg_gather/
    ├── Dockerfile              # Clones pg_gather from GitHub at build time
    └── setup.sh                # Two-stage report runner (gather → TSV → HTML)
```
