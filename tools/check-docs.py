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
- every decision record appears in the index that agents read, and every row of
  that index points at a record that exists

Coding-agent configuration under `.claude/` is left alone. It is instructions
for whoever works here rather than documentation the project ships, the same
reason a local CLAUDE.md is ignored, so the pairing rule does not apply to it.
"""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKIP = {".git", ".build", "node_modules"}
AGENT_CONFIG = {".claude"}
DECISIONS = ROOT / "docs" / "decisions"
DECISION_INDEX = ROOT / ".claude" / "skills" / "siop-decisions" / "SKILL.md"

HEADING = re.compile(r"^(#{1,6})\s+(.*)$", re.MULTILINE)
LINK = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")


def documentation(path):
    """Whether this Markdown file is documentation the project ships.

    An ignored file such as a local CLAUDE.md never reaches here, and what
    lives under `.claude/` is agent configuration for whoever works here —
    skills, decision records — held to the conventions in CLAUDE.md instead.
    """
    parts = path.relative_to(ROOT).parts
    return not any(part in SKIP | AGENT_CONFIG for part in parts)


def markdown_files():
    """The Markdown the repository actually carries."""
    try:
        listed = subprocess.run(
            ["git", "-C", str(ROOT), "ls-files", "*.md"],
            capture_output=True, text=True, check=True,
        ).stdout.split()
        candidates = [ROOT / name for name in sorted(listed)]
    except (subprocess.CalledProcessError, FileNotFoundError):
        candidates = sorted(ROOT.rglob("*.md"))
    return [path for path in candidates if documentation(path)]


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


def check_decision_index(problems):
    """Decision records are only reachable through their index.

    `docs/decisions/` is a log: written once, in English alone, so that
    recording a decision stays cheap enough to actually happen. Nothing reads
    the directory itself — agents read the index in the `siop-decisions` skill
    and open only the records a task touches. A record left out of that index
    is therefore invisible, which the pairing rules would never catch.
    """
    records = sorted(path.name for path in DECISIONS.glob("*.md")) if DECISIONS.is_dir() else []
    if not records:
        return

    if not DECISION_INDEX.exists():
        problems.append(
            f"{DECISION_INDEX.relative_to(ROOT)}: 決定記録の目次がない"
        )
        return

    text = DECISION_INDEX.read_text()
    listed = {
        target.rsplit("/", 1)[-1]
        for _, target in LINK.findall(text)
        if "docs/decisions/" in target
    }

    shown = DECISION_INDEX.relative_to(ROOT)
    for name in records:
        if name not in listed:
            problems.append(f"{shown}: {name} が目次にない")
    for name in sorted(listed - set(records)):
        problems.append(f"{shown}: 目次が指す {name} が存在しない")


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
        if path.parent == DECISIONS:
            continue
        if name not in {"README.md", "README.ja.md"}:
            problems.append(
                f"{path.relative_to(ROOT)}: 想定していない Markdown。"
                " ドキュメントは README.md と README.ja.md の対で置く"
            )

    check_decision_index(problems)

    if problems:
        print(f"{len(problems)} 件の問題:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    print(f"{len(files)} 個の Markdown を検査。問題なし。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
