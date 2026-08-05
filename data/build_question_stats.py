#!/usr/bin/env python3
"""Recompute the summary metadata block at the top of data/questions.json.

questions.json carries a small `counts` block (total / chapter / exam /
selectTwo / byDomain) plus `generatedAt` and `contentHash`, meant as an
at-a-glance summary of the `questions` array below it. Nothing in the game
or the test suite reads these fields at runtime -- they're purely for a
human skimming the raw file -- which is exactly why they silently drifted
out of sync with the real array after a previous edit (see
tests/run_tests.gd's "question bank stats match the actual array" check,
added alongside this script).

Run this after any manual edit to the `questions` array:

    python3 data/build_question_stats.py

It rewrites data/questions.json in place, preserving the existing compact
(single-line) JSON formatting and the questions array's order/content
exactly -- only the metadata block at the top is touched.
"""

import hashlib
import json
import sys
from datetime import datetime, timezone

PATH = "data/questions.json"


def compute_counts(questions):
    by_domain = {}
    chapter = 0
    exam = 0
    select_two = 0
    for question in questions:
        domain = str(question.get("domain"))
        by_domain[domain] = by_domain.get(domain, 0) + 1
        source = question.get("source")
        if source == "chapter":
            chapter += 1
        elif source == "exam":
            exam += 1
        if question.get("type") == "select_two":
            select_two += 1
    return {
        "total": len(questions),
        "chapter": chapter,
        "exam": exam,
        "selectTwo": select_two,
        "byDomain": dict(sorted(by_domain.items())),
    }


def compute_content_hash(questions):
    # Deterministic, order-preserving, dependency-free hash of the actual
    # question content -- just enough to notice "the array changed" at a
    # glance. Not a security control; truncated to match the existing
    # field's 12-hex-char convention.
    canonical = json.dumps(questions, sort_keys=True, separators=(",", ":")).encode(
        "utf-8"
    )
    return hashlib.sha256(canonical).hexdigest()[:12]


def main():
    with open(PATH, "r", encoding="utf-8") as f:
        data = json.load(f)

    questions = data["questions"]
    data["counts"] = compute_counts(questions)
    data["contentHash"] = compute_content_hash(questions)
    data["generatedAt"] = datetime.now(timezone.utc).isoformat(timespec="seconds")

    ordered = {
        "schemaVersion": data["schemaVersion"],
        "generatedAt": data["generatedAt"],
        "contentHash": data["contentHash"],
        "counts": data["counts"],
        "questions": questions,
    }

    with open(PATH, "w", encoding="utf-8") as f:
        f.write(json.dumps(ordered, ensure_ascii=False, separators=(",", ":")))

    print(f"counts: {data['counts']}")
    print(f"contentHash: {data['contentHash']}")
    print(f"generatedAt: {data['generatedAt']}")


if __name__ == "__main__":
    sys.exit(main())
