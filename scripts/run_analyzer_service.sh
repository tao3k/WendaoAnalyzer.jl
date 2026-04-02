#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec direnv exec . julia "$ROOT/scripts/run_analyzer_example.jl" "$@"
