#!/usr/bin/env python3
"""Deterministically balance answer positions for single-answer exam items.

The gauntlet uses every ``source: exam`` question. Keeping one correct letter
dominant makes blind guessing competitive with knowledge, so this script
cycles the correct position across A-D while preserving each option's text
and its matching ``whyNots`` explanation.
"""

import json
import os
import tempfile
from pathlib import Path


PATH = Path(__file__).resolve().parent / "questions.json"
LETTERS = ("A", "B", "C", "D")


def rebalance_question(question, target_key):
    options = question["options"]
    if len(options) != len(LETTERS):
        return False
    answers = question.get("answers", [])
    if question.get("type") != "single" or len(answers) != 1:
        return False

    correct_key = answers[0]
    correct_index = next(
        (index for index, option in enumerate(options) if option.get("key") == correct_key),
        None,
    )
    target_index = LETTERS.index(target_key)
    if correct_index is None:
        raise ValueError(f"missing answer option in {question.get('id', '<unknown>')}")

    reordered = list(options)
    reordered[correct_index], reordered[target_index] = (
        reordered[target_index],
        reordered[correct_index],
    )
    old_to_new = {}
    for index, option in enumerate(reordered):
        old_to_new[option["key"]] = LETTERS[index]
        option["key"] = LETTERS[index]
    question["options"] = reordered
    question["answers"] = [target_key]

    why_nots = question.get("whyNots")
    if isinstance(why_nots, dict):
        question["whyNots"] = {
            old_to_new[key]: value for key, value in why_nots.items() if key in old_to_new
        }
    return True


def main():
    with open(PATH, "r", encoding="utf-8") as source:
        data = json.load(source)

    index = 0
    for question in data["questions"]:
        if question.get("source") != "exam" or question.get("type") != "single":
            continue
        if rebalance_question(question, LETTERS[index % len(LETTERS)]):
            index += 1

    fd, temporary = tempfile.mkstemp(
        dir=PATH.parent, prefix=f".{PATH.name}.", suffix=".tmp"
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as destination:
            destination.write(
                json.dumps(data, ensure_ascii=False, separators=(",", ":"))
            )
        os.replace(temporary, PATH)
    except BaseException:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise

    print(f"rebalanced {index} single-answer exam questions across A-D")


if __name__ == "__main__":
    main()
