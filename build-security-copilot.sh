#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT="${1:-security-copilot}"
ARCHIVE="${SECURITY_COPILOT_SKILL_ARCHIVE:-skills/security-copilot/security-copilot_v4.skill}"
OUT="${ROOT}.zip"
TMP=""
cleanup() { [[ -n "$TMP" && -d "$TMP" ]] && rm -rf "$TMP"; }
trap cleanup EXIT

rm -rf -- "$ROOT" "$OUT"
mkdir -p -- "$ROOT"

if [[ ! -f "$ARCHIVE" ]]; then
  echo "ERROR: skill archive not found: $ARCHIVE" >&2
  exit 2
fi

if ! unzip -t "$ARCHIVE" >/dev/null 2>&1; then
  echo "ERROR: invalid security-copilot_v4.skill archive: $ARCHIVE" >&2
  exit 3
fi

TMP="$(mktemp -d)"
unzip -q "$ARCHIVE" -d "$TMP"

# Reject absolute paths and traversal entries before copying anything out.
python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1]).resolve()
for p in root.rglob('*'):
    try:
        p.resolve().relative_to(root)
    except ValueError:
        raise SystemExit(f"ERROR: archive path escapes extraction root: {p}")
PY

ARCHIVE_ROOT="$TMP/security-copilot"
if [[ ! -f "$ARCHIVE_ROOT/SKILL.md" ]]; then
  echo "ERROR: expected security-copilot/SKILL.md after extraction" >&2
  exit 4
fi

for f in references/adapters-and-specialized-engines.md references/analysis-engines.md references/available-modes.md references/mode-orchestrator-and-triage.md references/output-formats.md references/playbooks.md references/process-and-quality.md; do
  [[ -f "$ARCHIVE_ROOT/$f" ]] || { echo "ERROR: missing security-copilot/$f" >&2; exit 5; }
done

cp -a "$ARCHIVE_ROOT/." "$ROOT/"

if [[ -f "design-by-security/DESIGN-BY-SECURITY-PROMPT.md" ]]; then
  mkdir -p "$ROOT/integrations"
  cp "design-by-security/DESIGN-BY-SECURITY-PROMPT.md" "$ROOT/integrations/DESIGN-BY-SECURITY-PROMPT.md"
fi

mkdir -p "$ROOT/integrations"
cat > "$ROOT/integrations/README.md" <<'DOC'
# Design-by-Security integration

Design-by-Security is the upstream architecture/security-design gate.
Security Copilot v4 is the downstream operational analysis engine.

Design-by-Security owns architecture, requirements, controls, validation,
security gates, residual risk and redesign. Security Copilot owns operational
workflows such as SOC triage, incident response, DFIR, hunting, detection
engineering, IOC/CTI analysis, malware analysis and specialized playbooks.

Operational findings feed back into architecture as:
FINDING -> ROOT CAUSE -> SECURITY DEBT -> REQUIREMENT/CONTROL -> VALIDATION -> REDESIGN
DOC

( cd . && zip -qr "$OUT" "$ROOT" )

echo "Built: $OUT"
