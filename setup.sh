#!/usr/bin/env bash
#
# setup.sh - Fully automate a local Penpot + MCP setup:
#   1. Generate a PENPOT_SECRET_KEY (persisted in .env) if missing.
#   2. Start every service (including the official penpot-mcp server).
#   3. Wait for the backend (reachable through penpot-frontend) to be ready.
#   4. Register an account (idempotent: reuses it if it already exists).
#
# The MCP server itself needs no access token: penpot-mcp runs in
# "multi-user"/plugin-bridge mode, and penpot-frontend's nginx proxies
# /mcp/* to it directly (no separate port). To use tools like
# `execute_code` against a real design, open it in the Penpot UI and
# install/connect the Penpot MCP Plugin from within the file.
#
# Usage:
#   ./setup.sh [compose-file] [email] [password] [fullname]
#
# Examples:
#   ./setup.sh
#   ./setup.sh compose-local.yaml me@example.com 'Sup3rSecret!' "My Name"
#
# Copyright (C) 2026 compose-penpot contributors
# Licensed under the GNU General Public License v3.0 (see LICENSE).

set -euo pipefail

COMPOSE_FILE="${1:-compose.yaml}"
EMAIL="${2:-admin@example.com}"
PASSWORD="${3:-ChangeMe123!}"
FULLNAME="${4:-Admin}"
ENV_FILE=".env"
FRONTEND_SERVICE="penpot-frontend"
FRONTEND_URL="http://localhost:8080"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "Compose file not found: $COMPOSE_FILE" >&2
  exit 1
fi

touch "$ENV_FILE"

if ! grep -q '^PENPOT_SECRET_KEY=' "$ENV_FILE" 2>/dev/null; then
  echo "==> Generating PENPOT_SECRET_KEY"
  SECRET="$( (openssl rand -base64 96 2>/dev/null || head -c 96 /dev/urandom | base64) | tr -d '\n=+/' )"
  echo "PENPOT_SECRET_KEY=$SECRET" >> "$ENV_FILE"
fi

echo "==> Starting Penpot services"
docker compose -f "$COMPOSE_FILE" up -d

api() {
  local path="$1" body="$2"
  shift 2
  docker compose -f "$COMPOSE_FILE" exec -T "$FRONTEND_SERVICE" curl -s "$@" \
    -H 'Content-Type: application/json' -H 'Accept: application/json' \
    -d "$body" "$FRONTEND_URL/api/rpc/command/$path"
}

api_status() {
  local path="$1" body="$2"
  shift 2
  docker compose -f "$COMPOSE_FILE" exec -T "$FRONTEND_SERVICE" curl -s -o /dev/null -w '%{http_code}' "$@" \
    -H 'Content-Type: application/json' -H 'Accept: application/json' \
    -d "$body" "$FRONTEND_URL/api/rpc/command/$path"
}

json_get() {
  sed -n "s/.*\"$1\":\"\\([^\"]*\\)\".*/\\1/p"
}

echo "==> Waiting for penpot-backend to become reachable"
READY=""
for _ in $(seq 1 60); do
  if [[ "$(api_status get-profile '{}' 2>/dev/null)" == "200" ]]; then
    READY=1
    break
  fi
  sleep 2
done
[[ -n "$READY" ]] || { echo "Timed out waiting for penpot-backend" >&2; exit 1; }

echo "==> Ensuring account exists ($EMAIL)"
COOKIE_JAR="/tmp/compose-penpot-setup-cookies"
docker compose -f "$COMPOSE_FILE" exec -T "$FRONTEND_SERVICE" rm -f "$COOKIE_JAR"

LOGIN_RESP="$(api login-with-password "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" -c "$COOKIE_JAR" || true)"

if ! echo "$LOGIN_RESP" | grep -q '"id"'; then
  echo "==> Registering new account"
  PREP_RESP="$(api prepare-register-profile "{\"fullname\":\"$FULLNAME\",\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")"
  REG_TOKEN="$(echo "$PREP_RESP" | json_get token)"
  if [[ -z "$REG_TOKEN" ]]; then
    echo "prepare-register-profile failed: $PREP_RESP" >&2
    exit 1
  fi
  api register-profile "{\"token\":\"$REG_TOKEN\"}" >/dev/null
  LOGIN_RESP="$(api login-with-password "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" -c "$COOKIE_JAR")"
fi

if ! echo "$LOGIN_RESP" | grep -q '"id"'; then
  echo "login-with-password failed: $LOGIN_RESP" >&2
  exit 1
fi

docker compose -f "$COMPOSE_FILE" exec -T "$FRONTEND_SERVICE" rm -f "$COOKIE_JAR"

echo "==> Setup complete:"
echo "    Penpot UI:    http://localhost:9001  (login: $EMAIL / $PASSWORD)"
echo "    MCP endpoint: http://localhost:9001/mcp/stream (SSE: /mcp/sse)"
echo "    To use design-editing tools (execute_code, export_shape, ...),"
echo "    open a file in the Penpot UI and connect the Penpot MCP Plugin."
