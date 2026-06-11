#!/usr/bin/env python3
"""Local release-surface audit for AWS Boss Battle."""

from __future__ import annotations

import argparse
import ipaddress
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlparse


ALLOWED_EMAILS = {"AI2M2IA@users.noreply.github.com"}

EMAIL_RE = re.compile(
    r"(?<![\w.+-])([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})(?![\w.-])"
)
AWS_ACCESS_KEY_RE = re.compile(
    r"\b(?:(?:AKIA|ASIA)[A-Z0-9]{16}|A3T[A-Z0-9][A-Z0-9]{16})\b"
)
SECRET_BLOCK_RE = re.compile(
    r"-----BEGIN [A-Z0-9 ]*(?:PRIVATE|SECRET)[A-Z0-9 ]*-----"
)
URL_RE = re.compile(r"\bhttps?://[^\s<>'\"`)]+")

LOCAL_PATH_PATTERNS = (
    (
        "local macOS or Linux user path",
        re.compile(r"(?<![\w/])/(?:Users|home)/[A-Za-z0-9._-]+(?:/[^\s<>'\"`]*)?"),
    ),
    (
        "local Windows user path",
        re.compile(
            r"(?i)\b[A-Z]:[\\/](?:Users|Documents and Settings)[\\/][^\\/\s:<>\"']+"
        ),
    ),
    (
        "local mounted volume path",
        re.compile(r"(?<![\w/])/(?:Volumes)/[^\s<>'\"`]+"),
    ),
    (
        "local macOS temporary/cache path",
        re.compile(r"(?<![\w/])/(?:private/)?var/folders/[^\s<>'\"`]+"),
    ),
    (
        "local file URL",
        re.compile(r"\b" + re.escape("file" + ":///") + r"[^\s<>'\"`]+"),
    ),
)

PRIVATE_DOMAIN_SUFFIXES = (
    ".corp",
    ".home",
    ".internal",
    ".lan",
    ".local",
    ".private",
)
PRIVATE_HOSTS = {"localhost"}
ALLOWED_PRIVATE_URLS = {
    ("README.md", "http://" + "localhost:8000"),
}

FORBIDDEN_RELEASE_DIRS = {".godot", "__pycache__", "build", "exports", "user-data"}
SKIPPED_WALK_DIRS = FORBIDDEN_RELEASE_DIRS | {
    ".git",
    ".pytest_cache",
    "__pycache__",
}
FORBIDDEN_FILE_NAMES = {
    ".DS_Store",
    "Thumbs.db",
    "desktop.ini",
    "export_presets.cfg",
}
FORBIDDEN_FILE_PREFIXES = ("._",)
TEMP_SUFFIXES = (".tmp", ".temp", ".swp", ".swo", ".orig", ".rej")
EXPORT_SUFFIXES = (
    ".7z",
    ".aab",
    ".apk",
    ".dmg",
    ".exe",
    ".pck",
    ".pkg",
    ".rar",
    ".tar",
    ".tar.gz",
    ".tgz",
    ".wasm",
    ".zip",
)
BINARY_SUFFIXES = (
    ".aab",
    ".apk",
    ".bin",
    ".dmg",
    ".exe",
    ".gif",
    ".gz",
    ".ico",
    ".jar",
    ".jpeg",
    ".jpg",
    ".mov",
    ".mp3",
    ".mp4",
    ".ogg",
    ".pdf",
    ".png",
    ".pck",
    ".rar",
    ".tar",
    ".tgz",
    ".wasm",
    ".webp",
    ".zip",
)
MAX_TEXT_BYTES = 2 * 1024 * 1024

BRITISH_TO_AMERICAN = {
    "analyse": "analyze",
    "analysed": "analyzed",
    "analysing": "analyzing",
    "behaviour": "behavior",
    "cancelled": "canceled",
    "centre": "center",
    "colour": "color",
    "customise": "customize",
    "customised": "customized",
    "defence": "defense",
    "favour": "favor",
    "favourite": "favorite",
    "grey": "gray",
    "initialise": "initialize",
    "initialised": "initialized",
    "labelling": "labeling",
    "licence": "license",
    "localise": "localize",
    "localised": "localized",
    "offence": "offense",
    "optimise": "optimize",
    "optimised": "optimized",
    "organisation": "organization",
    "organise": "organize",
    "organised": "organized",
    "recognise": "recognize",
    "recognised": "recognized",
    "travelling": "traveling",
}
BRITISH_SPELLING_RE = re.compile(
    r"\b(" + "|".join(re.escape(word) for word in BRITISH_TO_AMERICAN) + r")\b",
    re.IGNORECASE,
)

LICENSE_REQUIRED_FRAGMENTS = (
    ("AGPL-3.0 title", "GNU AFFERO GENERAL PUBLIC LICENSE"),
    ("AGPL-3.0 version", "Version 3, 19 November 2007"),
    ("standard AGPL terms", "TERMS AND CONDITIONS"),
    ("standard AGPL ending", "END OF TERMS AND CONDITIONS"),
    (
        "Section 7 additional terms",
        "ADDITIONAL TERMS UNDER SECTION 7 OF THE GNU AGPL v3.0",
    ),
    ("AGPL-3.0 Section 7(b)", "AGPL-3.0 Section 7(b)"),
    ("AGPL-3.0 Section 7(c)", "AGPL-3.0 Section 7(c)"),
    ("AI(2)M(2)IA attribution", "AI(2)M(2)IA"),
    ("original source repository", "https://github.com/AI2M2IA/aws-game"),
)


@dataclass(frozen=True)
class Finding:
    path: str
    line: int | None
    reason: str

    def sort_key(self) -> tuple[str, int, str]:
        return (self.path, self.line or 0, self.reason)

    def format(self) -> str:
        if self.line is None:
            return f"{self.path}: {self.reason}"
        return f"{self.path}:{self.line}: {self.reason}"


def repo_root_from_script() -> Path:
    return Path(__file__).resolve().parents[2]


def run_git_ls_files(root: Path) -> list[Path] | None:
    try:
        result = subprocess.run(
            [
                "git",
                "-C",
                str(root),
                "ls-files",
                "-z",
                "--cached",
                "--others",
                "--exclude-standard",
            ],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except OSError:
        return None
    if result.returncode != 0:
        return None
    rel_paths = [item for item in result.stdout.split("\0") if item]
    return [Path(rel_path) for rel_path in rel_paths]


def walk_release_surface(root: Path) -> list[Path]:
    paths: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [
            name for name in dirnames if name not in SKIPPED_WALK_DIRS
        ]
        base = Path(dirpath)
        for filename in filenames:
            full_path = base / filename
            paths.append(full_path.relative_to(root))
    return paths


def release_surface_paths(root: Path) -> list[Path]:
    paths = run_git_ls_files(root)
    if paths is None:
        paths = walk_release_surface(root)
    return sorted(set(paths), key=lambda path: path.as_posix())


def rel_text(path: Path) -> str:
    return path.as_posix()


def has_forbidden_release_dir(path: Path) -> str | None:
    for part in path.parts:
        if part in FORBIDDEN_RELEASE_DIRS:
            return part + "/"
    return None


def forbidden_path_reason(path: Path) -> str | None:
    rel = rel_text(path)
    lower = rel.lower()
    name = path.name
    lower_name = name.lower()

    release_dir = has_forbidden_release_dir(path)
    if release_dir is not None:
        return f"generated or local directory is in the release surface: {release_dir}"
    if name in FORBIDDEN_FILE_NAMES:
        return f"local or generated file is in the release surface: {name}"
    if name.startswith(FORBIDDEN_FILE_PREFIXES):
        return f"OS metadata file is in the release surface: {name}"
    if lower_name.endswith(".log"):
        return "log file is in the release surface"
    if lower_name.endswith(".save"):
        return "player save data is in the release surface"
    if lower_name.endswith((".pyc", ".pyo")):
        return "Python cache file is in the release surface"
    if lower_name.endswith(TEMP_SUFFIXES) or lower_name.endswith("~"):
        return "temporary file is in the release surface"
    if lower.endswith(EXPORT_SUFFIXES) or any(
        part.lower().endswith(".app") for part in path.parts
    ):
        return "local export artifact or archive is in the release surface"
    return None


def should_scan_content(path: Path) -> bool:
    if has_forbidden_release_dir(path) is not None:
        return False
    if forbidden_path_reason(path) is not None:
        return False
    return True


def read_text(path: Path) -> str | None:
    if path.suffix.lower() in BINARY_SUFFIXES:
        return None
    try:
        data = path.read_bytes()
    except OSError:
        return None
    if len(data) > MAX_TEXT_BYTES or b"\0" in data[:4096]:
        return None
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return None


def is_i18n_json(path: Path) -> bool:
    return len(path.parts) == 3 and path.parts[:2] == ("data", "i18n") and path.suffix == ".json"


def english_segments(path: Path, line: str) -> list[str]:
    if is_i18n_json(path):
        return []

    suffix = path.suffix.lower()
    if suffix in {".gd", ".py", ".sh"}:
        if "#" not in line:
            return []
        return [line.split("#", 1)[1]]

    if suffix in {
        ".cfg",
        ".godot",
        ".import",
        ".json",
        ".md",
        ".svg",
        ".tscn",
        ".txt",
        ".yaml",
        ".yml",
    } or path.name in {"LICENSE", "AGENTS.md", "CLAUDE.md"}:
        return [line]

    return []


def private_url_reason(url: str) -> str | None:
    parsed = urlparse(url)
    host = parsed.hostname
    if not host:
        return None

    normalized = host.strip("[]").lower()
    if normalized in PRIVATE_HOSTS:
        return "private/internal URL"
    if normalized.endswith(PRIVATE_DOMAIN_SUFFIXES):
        return "private/internal URL"

    try:
        ip = ipaddress.ip_address(normalized)
    except ValueError:
        return None

    if ip.is_private or ip.is_loopback or ip.is_link_local:
        return "private/internal URL"
    return None


def scan_text(path: Path, text: str, findings: list[Finding]) -> None:
    rel = rel_text(path)
    for line_number, line in enumerate(text.splitlines(), start=1):
        for match in EMAIL_RE.finditer(line):
            email = match.group(1)
            if email not in ALLOWED_EMAILS:
                findings.append(
                    Finding(rel, line_number, f"personal email address: {email}")
                )

        for label, pattern in LOCAL_PATH_PATTERNS:
            for match in pattern.finditer(line):
                findings.append(
                    Finding(rel, line_number, f"{label}: {match.group(0)}")
                )

        if SECRET_BLOCK_RE.search(line):
            findings.append(Finding(rel, line_number, "private key or secret block"))

        if AWS_ACCESS_KEY_RE.search(line):
            findings.append(Finding(rel, line_number, "AWS access key pattern"))

        for match in URL_RE.finditer(line):
            url = match.group(0).rstrip(".,;:")
            if (rel, url) in ALLOWED_PRIVATE_URLS:
                continue
            reason = private_url_reason(url)
            if reason:
                findings.append(Finding(rel, line_number, f"{reason}: {url}"))

        for segment in english_segments(path, line):
            spelling_match = BRITISH_SPELLING_RE.search(segment)
            if not spelling_match:
                continue
            word = spelling_match.group(1)
            replacement = BRITISH_TO_AMERICAN[word.lower()]
            findings.append(
                Finding(
                    rel,
                    line_number,
                    f"use American English spelling: {word} -> {replacement}",
                )
            )


def check_license(root: Path, findings: list[Finding]) -> None:
    license_path = root / "LICENSE"
    rel = "LICENSE"
    if not license_path.exists():
        findings.append(Finding(rel, None, "missing required LICENSE file"))
        return
    if not license_path.is_file():
        findings.append(Finding(rel, None, "LICENSE exists but is not a file"))
        return

    text = read_text(license_path)
    if text is None:
        findings.append(Finding(rel, None, "LICENSE is missing readable UTF-8 text"))
        return

    for label, fragment in LICENSE_REQUIRED_FRAGMENTS:
        if fragment not in text:
            findings.append(Finding(rel, None, f"missing or damaged {label}"))


def audit(root: Path) -> tuple[list[Finding], int]:
    findings: list[Finding] = []
    paths = release_surface_paths(root)

    check_license(root, findings)

    for rel_path in paths:
        reason = forbidden_path_reason(rel_path)
        if reason is not None:
            findings.append(Finding(rel_text(rel_path), None, reason))
            continue

        if not should_scan_content(rel_path):
            continue

        full_path = root / rel_path
        if not full_path.is_file():
            continue
        text = read_text(full_path)
        if text is None:
            continue
        scan_text(rel_path, text, findings)

    return sorted(findings, key=Finding.sort_key), len(paths)


def print_results(findings: list[Finding], scanned_count: int) -> None:
    if not findings:
        print(f"Static audit passed: {scanned_count} release-surface file(s) checked.")
        return

    print(f"Static audit found {len(findings)} issue(s):")
    for finding in findings:
        print(f"- {finding.format()}")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Audit the AWS Boss Battle release surface for risky local artifacts."
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=repo_root_from_script(),
        help="Repository root to audit. Defaults to this script's repository.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    root = args.root.resolve()
    findings, scanned_count = audit(root)
    print_results(findings, scanned_count)
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
