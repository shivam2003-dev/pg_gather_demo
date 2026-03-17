# PostgreSQL Configuration Reference

The lab's PostgreSQL tuning lives in `postgres/conf.d/custom.conf`. This file is loaded via `include_dir` which `00_config.sh` appends to `postgresql.conf` on first boot.

Every setting below is annotated with which pg_gather report section it affects.

---

## Extensions

```conf
shared_preload_libraries = 'pg_stat_statements'
```

`pg_stat_statements` must be pre-loaded at server start. Without it the **Top SQL by Total Time**, **Top SQL by Calls**, and **I/O Time** sections of the pg_gather report are empty.

```conf
pg_stat_statements.max = 5000
pg_stat_statements.track = all
```

`max` controls how many distinct query fingerprints are retained. `track = all` captures queries from every user; `top` would only capture top-level statements.

---

## Memory

| Setting | Value | pg_gather section |
|---|---|---|
| `shared_buffers` | 256 MB | Cache Hit Ratio |
| `work_mem` | 8 MB | Sort / Hash Spills |
| `maintenance_work_mem` | 64 MB | Autovacuum performance |
| `effective_cache_size` | 512 MB | Query plan cost estimates |

**shared_buffers** is the most important memory knob. Standard guidance is 25% of RAM. Too small → low cache hit ratio in the report. Too large → OS page cache is starved.

**work_mem** is allocated *per sort/hash operation per query*, not per connection. With 100 connections each running a complex query, actual usage can be `100 × work_mem`. Sort spills to disk appear in the pg_gather "Spill" column.

**effective_cache_size** is not allocated — it only advises the query planner how much total cache (shared_buffers + OS cache) is available. Underestimating causes the planner to prefer sequential scans over index scans.

---

## Connections

```conf
max_connections = 100
```

Every connection reserves ~5–10 MB of shared memory. pg_gather's **Connection Slots** section shows used vs. reserved vs. available. A common production emergency is running out of connections — pg_gather makes this immediately visible.

For high-concurrency workloads, consider a connection pooler (PgBouncer) rather than raising `max_connections`.

---

## Logging

```conf
log_destination = 'stderr'
logging_collector = off
log_min_duration_statement = 1000    # ms
log_lock_waits = on
log_checkpoints = on
```

Docker captures `stderr` automatically — no separate log files are needed. `log_min_duration_statement = 1000` logs any query taking over 1 second; set to `0` to log everything (very verbose).

pg_gather reads `pg_stat_statements`, not log files. But log output lets you cross-reference report findings against actual query text and timing.

---

## Autovacuum

```conf
autovacuum = on
autovacuum_vacuum_scale_factor = 0.02
autovacuum_vacuum_cost_delay = 2ms
```

**Never disable autovacuum globally.** The lab disables it *per table* (`bloat_demo`) to demonstrate bloat — that is the only correct way to disable it for testing purposes.

`vacuum_scale_factor = 0.02` triggers a vacuum when dead tuples reach 2% of the table. Lowering this (e.g. `0.01`) causes more frequent vacuuming, which keeps bloat lower on large tables.

`vacuum_cost_delay = 2ms` controls how much autovacuum throttles itself. Lower value = faster vacuum but more I/O impact on foreground queries.

**pg_gather sections affected:** Bloat Analysis, Autovacuum Activity, Tables needing VACUUM.

---

## Checkpoints

```conf
checkpoint_completion_target = 0.9
min_wal_size = 80MB
max_wal_size = 1GB
```

`checkpoint_completion_target = 0.9` spreads dirty page writes over 90% of the checkpoint interval, smoothing I/O instead of causing a burst at checkpoint time.

`max_wal_size = 1GB` is the ceiling before a checkpoint is forced. Larger = less frequent forced checkpoints but more WAL to replay on crash recovery.

**pg_gather sections affected:** Checkpoint Frequency, WAL Generation Rate.

---

## Statistics

```conf
track_io_timing = on
track_counts = on
default_statistics_target = 100
```

`track_io_timing` enables I/O timing in `pg_stat_statements` and `EXPLAIN (BUFFERS)`. The small overhead (~1%) is worth it for the data it provides in pg_gather's I/O columns.

`track_counts` is required for autovacuum triggering and for `n_live_tup` / `n_dead_tup` in pg_gather's bloat sections.

`default_statistics_target = 100` (the default) controls the histogram resolution for `ANALYZE`. Higher values (up to 10000) improve planner estimates for skewed distributions but increase ANALYZE time.

---

## Applying Changes

Most settings in `custom.conf` require a **reload** (not a restart):

```bash
docker exec pg_gather_db psql -U pgadmin -d labdb \
    -c "SELECT pg_reload_conf();"
```

Settings that require a **restart** (cannot be reloaded):
- `shared_preload_libraries`
- `shared_buffers`
- `max_connections`

To restart the postgres container:

```bash
docker compose restart postgres
```
