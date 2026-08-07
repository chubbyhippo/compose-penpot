#!/usr/bin/env bash
#
# export.sh - Back up a Penpot instance (database + assets) managed by this
# compose-penpot stack, for migration to another host/instance.
#
# Usage:
#   ./export.sh [compose-file] [output-dir]
#
# Examples:
#   ./export.sh                              # compose.yaml -> ./backups
#   ./export.sh compose-local.yaml ./backups
#
# Copyright (C) 2026 compose-penpot contributors
# Licensed under the GNU General Public License v3.0 (see LICENSE).

set -euo pipefail

COMPOSE_FILE="${1:-compose.yaml}"
OUTPUT_DIR="${2:-./backups}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "Compose file not found: $COMPOSE_FILE" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "==> Using compose file: $COMPOSE_FILE"

DB_CONTAINER="$(docker compose -f "$COMPOSE_FILE" ps -q penpot-postgres)"
if [[ -z "$DB_CONTAINER" ]]; then
  echo "penpot-postgres is not running. Start the stack first:" >&2
  echo "    docker compose -f $COMPOSE_FILE up -d" >&2
  exit 1
fi

DB_DUMP="$OUTPUT_DIR/penpot-db-$TIMESTAMP.dump.gz"
echo "==> Dumping database to $DB_DUMP"
docker exec "$DB_CONTAINER" pg_dump -U penpot -Fc penpot | gzip > "$DB_DUMP"

BACKEND_CONTAINER="$(docker compose -f "$COMPOSE_FILE" ps -a -q penpot-backend)"
if [[ -z "$BACKEND_CONTAINER" ]]; then
  echo "==> penpot-backend container not found, creating it (without starting) to locate the assets volume"
  docker compose -f "$COMPOSE_FILE" create penpot-backend >/dev/null
  BACKEND_CONTAINER="$(docker compose -f "$COMPOSE_FILE" ps -a -q penpot-backend)"
fi

ASSETS_VOLUME=""
if [[ -n "$BACKEND_CONTAINER" ]]; then
  ASSETS_VOLUME="$(docker inspect "$BACKEND_CONTAINER" --format '{{ range .Mounts }}{{ if eq .Destination "/opt/data/assets" }}{{ .Name }}{{ end }}{{ end }}')"
fi

if [[ -n "$ASSETS_VOLUME" ]]; then
  ASSETS_DUMP="$OUTPUT_DIR/penpot-assets-$TIMESTAMP.tar.gz"
  ABS_OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
  echo "==> Archiving assets volume ($ASSETS_VOLUME) to $ASSETS_DUMP"
  docker run --rm \
    -v "$ASSETS_VOLUME":/opt/data/assets:ro \
    -v "$ABS_OUTPUT_DIR":/backup \
    busybox tar czf "/backup/$(basename "$ASSETS_DUMP")" -C /opt/data/assets .
else
  echo "==> Could not determine assets volume, skipping assets backup" >&2
fi

echo "==> Export complete:"
echo "    $DB_DUMP"
[[ -n "${ASSETS_DUMP:-}" ]] && echo "    $ASSETS_DUMP"
