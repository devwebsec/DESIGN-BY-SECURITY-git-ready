#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$ROOT/judge_adapter.py" \
  --cases "$ROOT/cases.jsonl" \
  --results "$ROOT/fixtures/results.jsonl" \
  --out "$ROOT/judge-results.offline.jsonl" \
  --offline
