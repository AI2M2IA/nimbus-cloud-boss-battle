#!/usr/bin/env python3
"""Apply and verify accessibility safeguards on a Godot Web export."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


DESCRIPTION = (
    "Gamified, local-first AWS SAA-C03 practice with boss battles, "
    "flashcards, and keyboard controls."
)
FALLBACK = (
    '<a href="https://github.com/AI2M2IA/nimbus-cloud-boss-battle/releases">'
    "This browser cannot run the game canvas. Download an accessible desktop "
    "build from the releases page.</a>"
)


def harden(html: str) -> str:
    html, viewport_changes = re.subn(
        r"user-scalable\s*=\s*no",
        "user-scalable=yes, maximum-scale=5",
        html,
        count=1,
        flags=re.IGNORECASE,
    )
    if viewport_changes != 1:
        raise ValueError("expected exactly one non-scalable viewport directive")

    if 'name="description"' not in html:
        marker = re.search(r'<meta name="viewport"[^>]*>', html, re.IGNORECASE)
        if marker is None:
            raise ValueError("viewport meta tag not found")
        description = f'\n\t<meta name="description" content="{DESCRIPTION}">'
        html = html[: marker.end()] + description + html[marker.end() :]

    canvas_pattern = re.compile(
        r'(<canvas\b[^>]*\bid="canvas"[^>]*>)\s*'
        r"Your browser does not support the canvas tag\.\s*(</canvas>)",
        re.IGNORECASE,
    )
    html, canvas_changes = canvas_pattern.subn(rf"\1{FALLBACK}\2", html, count=1)
    if canvas_changes != 1:
        raise ValueError("Godot canvas fallback did not match the expected template")

    html, aria_changes = re.subn(
        r'(<canvas\b[^>]*\bid="canvas")',
        r'\1 role="application" aria-label="Nimbus Cloud Boss Battle"',
        html,
        count=1,
        flags=re.IGNORECASE,
    )
    if aria_changes != 1:
        raise ValueError("Godot canvas element not found")

    if "user-scalable=no" in html.lower():
        raise ValueError("zoom-blocking viewport directive remains")
    if DESCRIPTION not in html or FALLBACK not in html:
        raise ValueError("accessible Web metadata was not applied")
    return html


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("html", type=Path)
    args = parser.parse_args()
    source = args.html.read_text(encoding="utf-8")
    args.html.write_text(harden(source), encoding="utf-8")
    print(f"Hardened Web export: {args.html}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
