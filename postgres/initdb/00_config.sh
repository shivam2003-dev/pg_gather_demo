#!/usr/bin/env bash
# =============================================================================
# 00_config.sh
# Runs inside the temporary server that docker-entrypoint.sh starts during
# initdb.  After ALL initdb.d scripts complete, the entrypoint stops that
# temp server and exec's the real "postgres" process — so any changes we
# make to $PGDATA/postgresql.conf here ARE picked up by the real server.
#
# Why a script instead of -c include_dir= on the command line?
# include_dir is a postgresql.conf FILE DIRECTIVE, not a GUC parameter.
# Passing it with -c produces: FATAL: unrecognized configuration parameter.
# =============================================================================
set -e

echo ">>> [00_config.sh] Appending include_dir to postgresql.conf ..."

# Append include_dir so Postgres merges every *.conf in our conf.d folder.
# Using >> so we never overwrite the initdb-generated defaults.
echo "" >> "$PGDATA/postgresql.conf"
echo "# --- pg_gather lab custom settings (conf.d) ---" >> "$PGDATA/postgresql.conf"
echo "include_dir = '/etc/postgresql/conf.d'" >> "$PGDATA/postgresql.conf"

echo ">>> [00_config.sh] Done. conf.d will be loaded on real server startup."
