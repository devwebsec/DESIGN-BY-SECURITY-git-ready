#!/usr/bin/env python3
"""Combine deterministic report and LLM-judge scores with fail-closed precedence."""
import argparse, json
from pathlib import Path

def load_jsonl(path):
    with open(path, encoding="utf-8") as f:
        return [json.loads(x) for x in f if x.strip()]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--deterministic-report", required=True)
    ap.add_argument("--judge-results", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--minimum-judge-score", type=float, default=85)
    args = ap.parse_args()
    det = json.load(open(args.deterministic_report, encoding="utf-8"))
    judge = load_jsonl(args.judge_results)
    judge_by_id = {x["case_id"]: x for x in judge}
    cases = []
    judge_scores = []
    judge_failures = []
    for item in det["cases"]:
        jid = item["case_id"]
        j = judge_by_id.get(jid)
        if not j:
            judge_failures.append(f"missing_judge:{jid}")
            cases.append({"case_id": jid, "deterministic": item, "judge": None, "passed": False})
            continue
        score = float(j.get("overall_score", 0))
        critical = bool(j.get("critical_violation", True))
        judge_scores.append(score)
        passed = bool(item["hard_fail_compliant"]) and not critical and score >= args.minimum_judge_score and j.get("judge_status") == "ok"
        if not passed:
            judge_failures.append(jid)
        cases.append({"case_id": jid, "deterministic": item, "judge": j, "passed": passed})
    judge_avg = round(sum(judge_scores) / len(judge_scores), 2) if judge_scores else 0
    passed = bool(det["passed"]) and not judge_failures and judge_avg >= args.minimum_judge_score
    report = {
        "schema_version": "1.0",
        "passed": passed,
        "deterministic_passed": bool(det["passed"]),
        "judge_average": judge_avg,
        "minimum_judge_score": args.minimum_judge_score,
        "judge_failures": judge_failures,
        "precedence": "deterministic_hard_fail > judge_score",
        "cases": cases,
    }
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    json.dump(report, open(args.out, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
    print(f"COMBINED EVAL: {'PASS' if passed else 'FAIL'} judge_average={judge_avg}")
    return 0 if passed else 1

if __name__ == "__main__": raise SystemExit(main())
