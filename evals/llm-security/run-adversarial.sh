#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$ROOT/adversarial_mutator.py" \
  --cases "$ROOT/cases.jsonl" \
  --out "$ROOT/mutations/mutated-cases.jsonl"
