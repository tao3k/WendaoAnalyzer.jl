#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec direnv exec . julia --project="$ROOT" "$ROOT/examples/analyzer_service.jl" "$@"
