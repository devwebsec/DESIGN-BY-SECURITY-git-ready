#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$ROOT/tests/security-design-pipeline"
SKILL_ARCHIVE="$ROOT/skills/security-copilot/security-copilot_v4.skill"
SKILL_SHA256="$ROOT/skills/security-copilot/security-copilot_v4.skill.sha256"
CONTRACT="$ROOT/contracts/security-design-contract.json"

pass=0
fail=0

good() { printf 'PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL  %s\n' "$1"; fail=$((fail+1)); }

check_file() {
  local f="$1"
  [[ -f "$f" ]] && good "${f#$ROOT/}" || bad "${f#$ROOT/}"
}

check_contains() {
  local f="$1" pattern="$2" label
  label="${3:-${1#$ROOT/} contains [$2]}"
  if grep -Fq "$pattern" "$f"; then good "$label"; else bad "$label"; fi
}

printf '%s\n' '=== Security Design Pipeline Integration Test ==='
printf '%s\n' 'Repository contract: Design-by-Security ↔ Security Copilot v4'

check_file "$ROOT/design-by-security/DESIGN-BY-SECURITY-PROMPT.md"
check_file "$ROOT/design-by-security/DESIGN-BY-SECURITY-ADAPTER.md"
check_file "$ROOT/skills/security-copilot/security-copilot_v4.skill"
check_file "$ROOT/skills/security-copilot/security-copilot_v4.skill.sha256"
check_file "$ROOT/skills/security-copilot/DESIGN-BY-SECURITY-ADAPTER.md"
check_file "$ROOT/build-security-copilot.sh"
check_file "$CONTRACT"

if python3 - "$CONTRACT" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
d = json.loads(p.read_text())
assert d['contract_version'] == '1.1'
assert d['lifecycle'] == ['DESIGN','BUILD','DEPLOY','DETECT','RESPOND','LEARN','REDESIGN']
for key in ('design_to_operations','operations_to_design','mandatory_artifacts','security_gate'):
    assert key in d
assert len(d['design_to_operations']['required']) >= 15
assert len(d['operations_to_design']['required']) >= 12
assert len(d['mandatory_artifacts']) >= 16
assert 'destructive_action_without_human_approval' in d['security_gate']['hard_fail']
PY
then good 'canonical contract is valid'; else bad 'canonical contract is valid'; fi

if (cd "$ROOT" && sha256sum -c skills/security-copilot/security-copilot_v4.skill.sha256 >/dev/null 2>&1); then
  good 'security-copilot_v4.skill SHA-256 matches lock file'
else
  bad 'security-copilot_v4.skill SHA-256 matches lock file'
fi

if unzip -t "$SKILL_ARCHIVE" >/dev/null 2>&1; then
  good 'security-copilot_v4.skill archive integrity'
else
  bad 'security-copilot_v4.skill archive integrity'
fi

for member in \
  security-copilot/SKILL.md \
  security-copilot/references/adapters-and-specialized-engines.md \
  security-copilot/references/analysis-engines.md \
  security-copilot/references/available-modes.md \
  security-copilot/references/mode-orchestrator-and-triage.md \
  security-copilot/references/output-formats.md \
  security-copilot/references/playbooks.md \
  security-copilot/references/process-and-quality.md; do
  if unzip -Z1 "$SKILL_ARCHIVE" | grep -Fxq "$member"; then good "archive contains $member"; else bad "archive contains $member"; fi
done

check_contains "$ROOT/design-by-security/DESIGN-BY-SECURITY-PROMPT.md" 'DESIGN → BUILD → DEPLOY → DETECT → RESPOND → LEARN → REDESIGN'
check_contains "$ROOT/design-by-security/DESIGN-BY-SECURITY-PROMPT.md" 'Score не заменяет risk assessment, security gate или control validation.'
check_contains "$ROOT/design-by-security/DESIGN-BY-SECURITY-ADAPTER.md" 'contracts/security-design-contract.json'
check_contains "$ROOT/design-by-security/DESIGN-BY-SECURITY-ADAPTER.md" 'Security Copilot'
check_contains "$ROOT/skills/security-copilot/DESIGN-BY-SECURITY-ADAPTER.md" 'Detection-by-Design'
check_contains "$ROOT/tests/security-design-pipeline/pipeline-manifest.yml" 'contract: contracts/security-design-contract.json'

if ! grep -RniE 'currently supported|Tell them where to go|Hello, world!|Add other actions to build' --include='*.md' --include='*.yml' "$ROOT" >/dev/null; then
  good 'no known template/stale placeholder text'
else
  bad 'no known template/stale placeholder text'
fi

run_tc() {
  local id="$1" file="$2"; shift 2
  local ok=1 pattern
  printf '\n--- %s ---\n' "$id"
  [[ -f "$file" ]] && good "$id scenario file" || { bad "$id scenario file"; return; }
  for pattern in "$@"; do
    if grep -Fq "$pattern" "$file"; then good "$id: [$pattern]"; else bad "$id: missing [$pattern]"; ok=0; fi
  done
  (( ok )) || { printf 'TC RESULT: %s FAIL\n' "$id"; return; }
  printf 'TC RESULT: %s PASS\n' "$id"
}

run_tc 'TC-001' "$TEST_DIR/TC-001-web-api.md" \
  'Trust boundaries' 'Attack surface' 'Critical attack path' 'Expected requirements' 'Expected controls' 'Security Copilot handoff'
run_tc 'TC-002' "$TEST_DIR/TC-002-identity-compromise.md" \
  'WHO→FROM WHERE→IDENTITY→RESOURCE→WHEN→PRIVILEGE→PURPOSE' 'blast radius' 'LATERAL MOVEMENT' 'Expected controls' 'Destructive actions require human approval' 'Security Copilot handoff'
run_tc 'TC-003' "$TEST_DIR/TC-003-supply-chain.md" \
  'SOURCE CODE → DEPENDENCIES → DEVELOPER → CI/CD → BUILD RUNNER → ARTIFACT → REGISTRY → DEPLOYMENT' 'malicious dependency' 'SBOM' 'provenance' 'artifact integrity/signing' 'Security Copilot handoff'
run_tc 'TC-004' "$TEST_DIR/TC-004-soc-feedback.md" \
  'DETECTION → TRIAGE → VALIDATION → CONTAINMENT → ROOT CAUSE → SECURITY DEBT → REQUIREMENT/CONTROL CHANGE → VALIDATION → REDESIGN' 'root cause' 'security debt item' 'residual risk' 'redesign decision' 'Security Copilot handoff'

printf '\n--- Packaging gate ---\n'
TMPDIR="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT
if SECURITY_COPILOT_SKILL_ARCHIVE="$SKILL_ARCHIVE" "$ROOT/build-security-copilot.sh" "$TMPDIR/security-copilot" >/dev/null 2>&1; then
  good 'builder executes successfully'
  if [[ -f "$TMPDIR/security-copilot/SKILL.md" ]]; then good 'builder output contains SKILL.md'; else bad 'builder output contains SKILL.md'; fi
else
  bad 'builder executes successfully'
fi

printf '\nRESULT: %d passed, %d failed\n' "$pass" "$fail"
if (( fail > 0 )); then printf '%s\n' 'PIPELINE INTEGRATION: FAIL'; exit 1; fi
printf '%s\n' 'PIPELINE INTEGRATION: PASS'
