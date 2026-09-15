# DESIGN-BY-SECURITY

## Security Architecture & Engineering Operating System

This repository combines two complementary layers:

- **Design-by-Security** — architecture-first security design, threat modeling, security requirements, controls, validation and security gates.
- **Security Copilot v4** — operational SOC, IR, DFIR, hunting, detection, IOC/CTI, malware and security-engineering analysis.

Operating model:

`DESIGN → BUILD → DEPLOY → DETECT → RESPOND → LEARN → REDESIGN`

## Repository structure

```text
.
├── .github/workflows/
│   └── security-design-integration.yml
├── contracts/
│   └── security-design-contract.json
├── design-by-security/
│   ├── DESIGN-BY-SECURITY-PROMPT.md
│   ├── DESIGN-BY-SECURITY-ADAPTER.md
│   └── INTEGRATION.md
├── skills/security-copilot/
│   ├── security-copilot_v4.skill
│   ├── security-copilot_v4.skill.sha256
│   ├── DESIGN-BY-SECURITY-ADAPTER.md
│   └── INTEGRATION.md
├── tests/security-design-pipeline/
│   ├── pipeline-manifest.yml
│   ├── run-pipeline.sh
│   └── TC-001..TC-004 scenario contracts
├── AI_SECURITY_COPILOT_2_1-*.md
├── DESIGN-BY-SECURITY-COPILOT-2.0-MASTER-PROMPT.md
├── build-security-copilot.sh
├── LICENSE
└── SECURITY.md
```

## Design principle

Do not bolt security onto an already-defined architecture. Start with:

`BUSINESS → ASSETS → DATA → IDENTITIES → ARCHITECTURE → TRUST BOUNDARIES → ATTACK SURFACE → THREATS → ATTACK PATHS → REQUIREMENTS → CONTROLS → VALIDATION`

The operational layer closes the loop:

`DETECT → RESPOND → LEARN → REDESIGN`

Design-by-Security and Security Copilot are intentionally kept separate so that architecture remains the security-design gate and the operational skill remains reusable.

## Contract and validation

The canonical machine-readable integration contract is `contracts/security-design-contract.json`. Human-readable semantics are defined in `design-by-security/DESIGN-BY-SECURITY-ADAPTER.md`.

The integration suite validates structure, contract invariants, scenario coverage, archive integrity and packaging safety:

```bash
bash tests/security-design-pipeline/run-pipeline.sh
```

The suite is intentionally a static contract test. It does **not** prove that an LLM will always produce a semantically correct answer; that requires model-evaluation tests in addition to repository CI.

## Current security-framework references

The project aligns its incident-response model with NIST SP 800-61 Rev. 3 and uses security-by-design principles consistent with OWASP guidance. Standards and ATT&CK mappings should be re-verified before regulated or legally significant use.

## LLM evaluation hardening

`evals/llm-security/` is the semantic evaluation layer for model behavior. It complements static repository tests rather than replacing them.

Run the offline hardened suite with:

```bash
bash evals/llm-security/run-eval.sh
```

The evaluation contract is intentionally provider-agnostic: an external adapter may call any approved LLM, but it must emit the JSONL result format defined by `evals/llm-security/adapter-contract.schema.json`. The deterministic evaluator then enforces hard-fail behavior, evidence discipline and security-gate semantics.
