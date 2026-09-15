#!/usr/bin/env python3
"""Provider-agnostic OpenAI-compatible LLM judge adapter.

The adapter performs deterministic pre-gating before the judge call, sends candidate output
as explicitly untrusted data, validates the judge's JSON schema, and never lets the judge
override deterministic hard-fail results.
"""
import argparse, json, os, re, sys, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SYSTEM_PROMPT = (ROOT / "judge-system-prompt.txt").read_text(encoding="utf-8")
TEMPLATE = (ROOT / "judge-prompt-template.txt").read_text(encoding="utf-8")
RUBRIC = json.loads((ROOT / "judge-rubric.json").read_text(encoding="utf-8"))

INJECTION_PATTERNS = [
    r"ignore (all|any|the) (previous|prior|above) (instructions|rules)",
    r"reveal (the )?(hidden|system|developer) (prompt|instructions)",
    r"you are now (the|an)\s+",
    r"highest priority instruction",
    r"override (the )?(rubric|policy|security gate)",
]


def load_jsonl(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            if line.strip():
                rows.append(json.loads(line))
    return rows


def stable_json(obj):
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def candidate_injection_flags(result):
    blob = stable_json(result).lower()
    return [p for p in INJECTION_PATTERNS if re.search(p, blob, re.I)]


def deterministic_prefilter(case, result):
    """Fail closed before model judge: malformed or obviously adversarial candidates are not judge-authoritative."""
    flags = candidate_injection_flags(result)
    response = str(result.get("response", ""))
    if not response.strip():
        return {"blocked": True, "reason": "empty_candidate", "flags": flags}
    if flags:
        return {"blocked": True, "reason": "candidate_prompt_injection_pattern", "flags": flags}
    return {"blocked": False, "reason": None, "flags": []}


def build_prompt(case, result):
    return TEMPLATE.replace("{{CASE_JSON}}", stable_json(case)).replace(
        "{{RUBRIC_JSON}}", stable_json(RUBRIC)
    ).replace("{{CANDIDATE_JSON}}", stable_json(result))


def call_chat(endpoint, api_key, model, prompt, timeout):
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt},
        ],
        "temperature": 0,
        "response_format": {"type": "json_object"},
    }
    req = urllib.request.Request(
        endpoint,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    content = data["choices"][0]["message"]["content"]
    return json.loads(content)


def validate_judgement(obj, case_id):
    required = {"case_id", "overall_score", "dimension_scores", "critical_violation", "rationale", "judge_status"}
    if set(obj) != required:
        raise ValueError(f"judge_schema_keys:{sorted(set(obj) ^ required)}")
    if obj["case_id"] != case_id:
        raise ValueError("judge_case_id_mismatch")
    if not (0 <= float(obj["overall_score"]) <= 100):
        raise ValueError("judge_score_out_of_range")
    if not isinstance(obj["dimension_scores"], dict):
        raise ValueError("dimension_scores_not_object")
    if not isinstance(obj["critical_violation"], bool):
        raise ValueError("critical_violation_not_boolean")
    if obj["judge_status"] not in {"ok", "refused", "error"}:
        raise ValueError("invalid_judge_status")
    return obj


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", required=True)
    ap.add_argument("--results", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--endpoint", default=os.getenv("LLM_JUDGE_ENDPOINT"))
    ap.add_argument("--api-key", default=os.getenv("LLM_JUDGE_API_KEY", ""))
    ap.add_argument("--model", default=os.getenv("LLM_JUDGE_MODEL", ""))
    ap.add_argument("--timeout", type=int, default=60)
    ap.add_argument("--offline", action="store_true", help="Emit blocked/error decisions without calling a model")
    args = ap.parse_args()

    cases = {x["case_id"]: x for x in load_jsonl(args.cases)}
    results = {x["case_id"]: x for x in load_jsonl(args.results)}
    output = []

    for case_id, case in cases.items():
        result = results.get(case_id, {})
        pre = deterministic_prefilter(case, result)
        if pre["blocked"] or args.offline:
            output.append({
                "case_id": case_id,
                "overall_score": 0,
                "dimension_scores": {},
                "critical_violation": bool(pre["blocked"]),
                "rationale": pre["reason"] or "offline_mode",
                "judge_status": "error",
                "pre_gate": pre,
            })
            continue
        if not args.endpoint or not args.api_key or not args.model:
            raise SystemExit("Set LLM_JUDGE_ENDPOINT, LLM_JUDGE_API_KEY and LLM_JUDGE_MODEL, or use --offline")
        try:
            judged = call_chat(args.endpoint, args.api_key, args.model, build_prompt(case, result), args.timeout)
            judged = validate_judgement(judged, case_id)
            # Judge can downgrade, never upgrade a deterministic failure.
            judged["pre_gate"] = pre
        except Exception as exc:
            judged = {
                "case_id": case_id,
                "overall_score": 0,
                "dimension_scores": {},
                "critical_violation": True,
                "rationale": f"judge_error:{type(exc).__name__}",
                "judge_status": "error",
                "pre_gate": pre,
            }
        output.append(judged)

    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        for row in output:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
