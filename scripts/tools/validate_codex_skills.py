#!/usr/bin/env python3

from __future__ import annotations

import sys
from pathlib import Path

import yaml


DEFAULT_ROOTS = [
    Path.home() / ".codex" / "skills",
    Path.home() / ".agents" / "skills",
]


def load_frontmatter(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        raise ValueError("missing leading YAML frontmatter block")

    parts = text.split("---", 2)
    if len(parts) < 3:
        raise ValueError("missing closing YAML frontmatter delimiter")

    data = yaml.safe_load(parts[1])
    if not isinstance(data, dict):
        raise ValueError("frontmatter is not a YAML mapping")

    for key in ("name", "description"):
        if key not in data or not str(data[key]).strip():
            raise ValueError(f"missing required field: {key}")

    return data


def validate_path(path: Path) -> list[str]:
    failures: list[str] = []

    if path.is_file():
        targets = [path]
    else:
        targets = sorted(path.rglob("SKILL.md"))

    for target in targets:
        try:
            data = load_frontmatter(target)
            desc_line = next(
                (line for line in target.read_text(encoding="utf-8").splitlines() if line.startswith("description:")),
                "",
            )
            if ": " in desc_line[len("description: ") :] and '"' not in desc_line and "'" not in desc_line:
                failures.append(
                    f"{target}: description contains ':' and should be quoted for Codex compatibility"
                )
                continue
            print(f"OK {target} ({data['name']})")
        except Exception as exc:
            failures.append(f"{target}: {exc}")

    return failures


def main(argv: list[str]) -> int:
    roots = [Path(arg).expanduser() for arg in argv] if argv else DEFAULT_ROOTS
    failures: list[str] = []
    checked_any = False

    for root in roots:
        if not root.exists():
            failures.append(f"{root}: path does not exist")
            continue
        checked_any = True
        failures.extend(validate_path(root))

    if not checked_any:
        print("No skill paths found.", file=sys.stderr)
        return 1

    if failures:
        print("\nFailures:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print("\nAll checked skills are valid.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
