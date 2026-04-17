#!/usr/bin/env python3
"""Sync repository metadata in docs/package files from repo-config.env."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = ROOT / "repo-config.env"
README_PATH = ROOT / "README.md"
PYPROJECT_PATH = ROOT / "pyproject.toml"


def load_env(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        key, value = line.split("=", 1)
        data[key] = value
    required = {"REPO_URL", "ISSUES_URL"}
    missing = required.difference(data)
    if missing:
        raise ValueError(f"Missing required keys in {path}: {sorted(missing)}")
    return data


def replace_between(text: str, start: str, end: str, replacement: str) -> str:
    start_idx = text.index(start) + len(start)
    end_idx = text.index(end, start_idx)
    return text[:start_idx] + replacement + text[end_idx:]


def sync_readme(readme_text: str, repo_url: str) -> str:
    return replace_between(
        readme_text,
        "git clone ",
        "\ncd ",
        repo_url,
    )


def sync_pyproject(pyproject_text: str, repo_url: str, issues_url: str) -> str:
    lines = []
    for line in pyproject_text.splitlines():
        if line.startswith("Homepage = "):
            lines.append(f'Homepage = "{repo_url}"')
        elif line.startswith("Issues = "):
            lines.append(f'Issues = "{issues_url}"')
        else:
            lines.append(line)
    return "\n".join(lines) + "\n"


def main() -> None:
    config = load_env(CONFIG_PATH)
    README_PATH.write_text(sync_readme(README_PATH.read_text(), config["REPO_URL"]))
    PYPROJECT_PATH.write_text(
        sync_pyproject(PYPROJECT_PATH.read_text(), config["REPO_URL"], config["ISSUES_URL"])
    )
    print("Repository metadata synchronized.")


if __name__ == "__main__":
    main()
