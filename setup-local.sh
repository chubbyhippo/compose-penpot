#!/usr/bin/env bash
#
# setup-local.sh - Same as setup.sh, but defaults to compose-local.yaml.
#
# Usage:
#   ./setup-local.sh [email] [password] [fullname]
#
# Examples:
#   ./setup-local.sh
#   ./setup-local.sh me@example.com 'Sup3rSecret!' "My Name"
#
# Copyright (C) 2026 compose-penpot contributors
# Licensed under the GNU General Public License v3.0 (see LICENSE).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "$SCRIPT_DIR/setup.sh" compose-local.yaml "$@"
