#!/usr/bin/env python3
"""Checks that the documentation rules hold.

Every directory that documents itself carries `README.md` in English and
`README.ja.md` in Japanese. Keeping a translation honest is a manual job, but
the ways a pair silently falls apart are mechanical, so they are checked here:

- a README exists in both languages
- the two have the same heading structure, so a section added to one and not
  the other is caught even though the wording differs
- each points at the other
- relative links resolve, including links to directories not created yet
"""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKIP = {".git", ".build", "node_modules"}

HEADING = re.compile(r"^(#{1,6})\s+(.*)$", re.MULTILINE)
LINK = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")


def markdown_files():
    """The Markdown the repository actually carries.

    Tracked files only: an ignored file such as a local CLAUDE.md is
    configuration for whoever works here, not documentation the project ships.
    """
    try:
        listed = subprocess.run(
            ["git", "-C", str(ROOT), "ls-files", "*.md"],
            capture_output=True, text=True, check=True,
        ).stdout.split()
        return [ROOT / name for name in sorted(listed)]
    except (subprocess.CalledProcessError, FileNotFoundError):
        return [
            path for path in sorted(ROOT.rglob("*.md"))
            if not any(part in SKIP for part in path.relative_to(ROOT).parts)
        ]


def heading_levels(text):
    return [len(match.group(1)) for match in HEADING.finditer(text)]


def check_pair(english, problems):
    japanese = english.with_name("README.ja.md")
    shown = english.relative_to(ROOT)

    if not japanese.exists():
        problems.append(f"{shown}: 日本語版 {japanese.name} がない")
        return

    en_text = english.read_text()
    ja_text = japanese.read_text()

    en_levels = heading_levels(en_text)
    ja_levels = heading_levels(ja_text)
    if en_levels != ja_levels:
        problems.append(
            f"{shown}: 見出し構成が日本語版と一致しない "
            f"(英語 {len(en_levels)} 個 {en_levels} / 日本語 {len(ja_levels)} 個 {ja_levels})"
        )

    if "README.ja.md" not in en_text:
        problems.append(f"{shown}: 日本語版への切り替えリンクがない")
    if "README.md" not in ja_text:
        problems.append(f"{japanese.relative_to(ROOT)}: 英語版への切り替えリンクがない")


def check_links(path, problems):
    shown = path.relative_to(ROOT)
    for text, target in LINK.findall(path.read_text()):
        if target.startswith(("http://", "https://", "#", "mailto:")):
            continue
        resolved = (path.parent / target.split("#")[0]).resolve()
        if not resolved.exists():
            problems.append(f"{shown}: リンク切れ [{text}]({target})")


def main():
    problems = []
    files = list(markdown_files())

    for path in files:
        check_links(path, problems)
        if path.name == "README.md":
            check_pair(path, problems)
        elif path.name == "README.ja.md" and not path.with_name("README.md").exists():
            problems.append(f"{path.relative_to(ROOT)}: 英語版 README.md がない")

    for path in files:
        name = path.name
        if name not in {"README.md", "README.ja.md"}:
            problems.append(
                f"{path.relative_to(ROOT)}: 想定していない Markdown。"
                " ドキュメントは README.md と README.ja.md の対で置く"
            )

    if problems:
        print(f"{len(problems)} 件の問題:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    print(f"{len(files)} 個の Markdown を検査。問題なし。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
