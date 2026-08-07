#!/usr/bin/env bash
#
# import.sh - Restore a Penpot instance (database + assets) previously
# backed up with export.sh, for migration to another host/instance.
#
# Usage:
#   ./import.sh <db-dump.dump.gz> [assets-backup.tar.gz] [compose-file]
#
# Examples:
#   ./import.sh backups/penpot-db-20260101-120000.dump.gz
#   ./import.sh backups/penpot-db-20260101-120000.dump.gz \
#               backups/penpot-assets-20260101-120000.tar.gz \
#               compose-local.yaml
#
# WARNING: this overwrites the target database and assets volume.
#
# Copyright (C) 2026 compose-penpot contributors
# Licensed under the GNU General Public License v3.0 (see LICENSE).

set -euo pipefail

usage() {
  echo "Usage: $0 <db-dump.dump.gz> [assets-backup.tar.gz] [compose-file]" >&2
  exit 1
}

[[ $# -lt 1 ]] && usage

DB_DUMP="$1"
ASSETS_DUMP="${2:-}"
COMPOSE_FILE="${3:-compose.yaml}"

[[ -f "$DB_DUMP" ]] || { echo "Database dump not found: $DB_DUMP" >&2; exit 1; }
if [[ -n "$ASSETS_DUMP" ]]; then
  [[ -f "$ASSETS_DUMP" ]] || { echo "Assets archive not found: $ASSETS_DUMP" >&2; exit 1; }
fi
[[ -f "$COMPOSE_FILE" ]] || { echo "Compose file not found: $COMPOSE_FILE" >&2; exit 1; }

echo "==> Using compose file: $COMPOSE_FILE"
echo "==> Stopping services that use the database/assets"
docker compose -f "$COMPOSE_FILE" stop penpot-frontend penpot-backend penpot-exporter penpot-mcp 2>/dev/null || true

echo "==> Ensuring database is up"
docker compose -f "$COMPOSE_FILE" up -d penpot-postgres

DB_CONTAINER=""
for _ in $(seq 1 30); do
  DB_CONTAINER="$(docker compose -f "$COMPOSE_FILE" ps -q penpot-postgres)"
  if [[ -n "$DB_CONTAINER" ]] && docker exec "$DB_CONTAINER" pg_isready -U penpot >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if [[ -z "$DB_CONTAINER" ]]; then
  echo "penpot-postgres container did not become ready" >&2
  exit 1
fi

echo "==> Recreating database penpot"
# Penpot's schema uses partitioned tables (e.g. file_data_00..15), and
# pg_restore --clean fails on those with "cannot drop inherited constraint"
# since a constraint can't be dropped from a partition directly. Dropping
# and recreating the database instead avoids that entirely.
docker exec "$DB_CONTAINER" psql -U penpot -d postgres -v ON_ERROR_STOP=1 \
  -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'penpot' AND pid <> pg_backend_pid();" \
  -c "DROP DATABASE IF EXISTS penpot;" \
  -c "CREATE DATABASE penpot OWNER penpot;"

echo "==> Restoring database from $DB_DUMP"
gunzip -c "$DB_DUMP" | docker exec -i "$DB_CONTAINER" pg_restore -U penpot -d penpot --no-owner --no-privileges

if [[ -n "$ASSETS_DUMP" ]]; then
  BACKEND_CONTAINER="$(docker compose -f "$COMPOSE_FILE" ps -a -q penpot-backend)"
  if [[ -z "$BACKEND_CONTAINER" ]]; then
    echo "==> penpot-backend container not found, creating it (without starting) to locate the assets volume"
    docker compose -f "$COMPOSE_FILE" create penpot-backend >/dev/null
    BACKEND_CONTAINER="$(docker compose -f "$COMPOSE_FILE" ps -a -q penpot-backend)"
  fi

  ASSETS_VOLUME="$(docker inspect "$BACKEND_CONTAINER" --format '{{ range .Mounts }}{{ if eq .Destination "/opt/data/assets" }}{{ .Name }}{{ end }}{{ end }}')"
  if [[ -z "$ASSETS_VOLUME" ]]; then
    echo "Could not determine assets volume name" >&2
    exit 1
  fi

  ABS_DUMP_DIR="$(cd "$(dirname "$ASSETS_DUMP")" && pwd)"
  echo "==> Restoring assets volume ($ASSETS_VOLUME) from $ASSETS_DUMP"
  docker run --rm \
    -v "$ASSETS_VOLUME":/opt/data/assets \
    -v "$ABS_DUMP_DIR":/backup \
    busybox sh -c "rm -rf /opt/data/assets/* /opt/data/assets/.[!.]* 2>/dev/null; tar xzf /backup/$(basename "$ASSETS_DUMP") -C /opt/data/assets"
fi

echo "==> Starting full stack"
docker compose -f "$COMPOSE_FILE" up -d

echo "==> Import complete"
