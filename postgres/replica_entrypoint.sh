#!/usr/bin/env bash
# =============================================================================
# replica_entrypoint.sh — custom entrypoint for the standby container
# Runs pg_basebackup from the primary on first boot, then starts postgres
# in standby mode.  -R flag tells pg_basebackup to create standby.signal
# and write primary_conninfo into postgresql.auto.conf automatically.
# =============================================================================
set -eo pipefail

PGDATA="${PGDATA:-/var/lib/postgresql/data}"
PRIMARY_HOST="${PRIMARY_HOST:-pg_gather_db}"
PRIMARY_PORT="${PRIMARY_PORT:-5432}"

# ── First boot: data directory is empty ──────────────────────────────────────
if [ ! -f "$PGDATA/PG_VERSION" ]; then
    echo ">>> REPLICA: Data directory empty — setting up from primary (${PRIMARY_HOST})"

    mkdir -p "$PGDATA"
    chown postgres:postgres "$PGDATA"
    chmod 700 "$PGDATA"

    # Wait for primary to be ready
    until pg_isready -h "$PRIMARY_HOST" -p "$PRIMARY_PORT" -U "$POSTGRES_USER" -q; do
        echo ">>> REPLICA: Waiting for primary at ${PRIMARY_HOST}:${PRIMARY_PORT} ..."
        sleep 2
    done

    echo ">>> REPLICA: Primary is ready, running pg_basebackup ..."

    # -R : write standby.signal + primary_conninfo → replica starts in standby mode
    # --wal-method=stream : stream WAL during backup (avoids gap)
    gosu postgres env PGPASSWORD="$POSTGRES_PASSWORD" pg_basebackup \
        -h "$PRIMARY_HOST" \
        -p "$PRIMARY_PORT" \
        -U "$POSTGRES_USER" \
        -D "$PGDATA" \
        -R \
        --wal-method=stream \
        -P

    echo ">>> REPLICA: pg_basebackup complete — standby.signal written"
fi

# The replica's postgresql.conf was copied from the primary which has
# include_dir = '/etc/postgresql/conf.d'.  The plain postgres image doesn't
# have that directory, so we create an empty one to satisfy the directive.
mkdir -p /etc/postgresql/conf.d

echo ">>> REPLICA: Starting postgres in hot standby mode"
exec gosu postgres postgres -D "$PGDATA"
