#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${LLM_JUDGE_ENDPOINT:?Set LLM_JUDGE_ENDPOINT}"
: "${LLM_JUDGE_API_KEY:?Set LLM_JUDGE_API_KEY}"
: "${LLM_JUDGE_MODEL:?Set LLM_JUDGE_MODEL}"
python3 "$ROOT/judge_adapter.py" \
  --cases "$ROOT/cases.jsonl" \
  --results "$ROOT/fixtures/results.jsonl" \
  --out "$ROOT/judge-results.jsonl"
