#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
export RAGFLOW_PROJECT_DIR="${SCRIPT_DIR}"

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cd "${SCRIPT_DIR}"

export COMPOSE_PROJECT_NAME="ragflow"

docker compose down
