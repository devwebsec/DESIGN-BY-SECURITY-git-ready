#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 "$ROOT/evals/llm-security/evaluate.py" \
  --cases "$ROOT/evals/llm-security/cases.jsonl" \
  --results "$ROOT/evals/llm-security/fixtures/results.jsonl" \
  --policy "$ROOT/evals/llm-security/eval-policy.json" \
  --report "$ROOT/evals/llm-security/report.json"
