#!/usr/bin/env python3
"""MkDocs pre-build hook.

Generates docs/_data/skills.json and docs/_data/recipes.json from
skills/*/SKILL.md and skills/recipes/*.md so the Material partials can
list skills and recipes without copying their content.

MkDocs automatically calls the on_pre_build() global if it exists.
Stdlib only — no third-party imports.
"""
from __future__ import annotations

import json
import logging
import re
from pathlib import Path

from mkdocs.config import Config

log = logging.getLogger("mkdocs.hooks.build-skill-index")

REPO_ROOT = Path(__file__).resolve().parent.parent
SKILLS_DIR = REPO_ROOT / "skills"
RECIPES_DIR = SKILLS_DIR / "recipes"
# Cached outside docs/ so 'mkdocs serve' does not watch and re-trigger
# the build loop on every regeneration of these JSON files.
OUT_DIR = REPO_ROOT / ".cache" / "skills-index"

SOURCE_URL_BASE = "https://github.com/MadCat34/symfony-ai-skills/blob/main"
MAX_SUMMARY_CHARS = 180


def parse_frontmatter(text: str) -> tuple[dict[str, str], str]:
    """Return (frontmatter_dict, body) for a Markdown file.

    The frontmatter is delimited by two lines containing only '---'.
    Recognised keys are mapped to a flat dict; the body is everything
    after the closing '---' line.
    """
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n(.*)$", text, re.DOTALL)
    if not m:
        return {}, text
    fm_block, body = m.group(1), m.group(2)
    data: dict[str, str] = {}
    for line in fm_block.splitlines():
        if not line or line.startswith((" ", "-", "\t")):
            continue
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        data[key.strip()] = value.strip().strip('"').strip("'")
    return data, body


def first_paragraph(body: str, max_chars: int = MAX_SUMMARY_CHARS) -> str:
    """Return the first non-heading paragraph of the body, truncated."""
    for para in re.split(r"\n\s*\n", body.strip()):
        para = para.strip()
        if not para or para.startswith("#"):
            continue
        if len(para) > max_chars:
            return para[: max_chars - 1].rstrip() + "…"
        return para
    return ""


def build_skills() -> list[dict[str, str]]:
    skills: list[dict[str, str]] = []
    for d in sorted(SKILLS_DIR.iterdir()):
        if not d.is_dir() or d.name == "recipes":
            continue
        skill_md = d / "SKILL.md"
        if not skill_md.exists():
            continue
        fm, body = parse_frontmatter(skill_md.read_text(encoding="utf-8"))
        skills.append({
            "slug": d.name,
            "title": fm.get("name", d.name),
            "description": fm.get("description", ""),
            "summary": first_paragraph(body),
            "source_url": f"{SOURCE_URL_BASE}/skills/{d.name}/SKILL.md",
        })
    return skills


def build_recipes() -> list[dict[str, object]]:
    recipes: list[dict[str, object]] = []
    for p in sorted(RECIPES_DIR.glob("*.md")):
        if p.name == "README.md":
            continue
        fm, body = parse_frontmatter(p.read_text(encoding="utf-8"))
        composes_raw = fm.get("composes", "")
        recipes.append({
            "slug": p.stem,
            "title": fm.get("title", p.stem),
            "composes": [c.strip() for c in composes_raw.split(",") if c.strip()],
            "summary": first_paragraph(body),
            "source_url": f"{SOURCE_URL_BASE}/skills/recipes/{p.name}",
        })
    return recipes


def on_pre_build(config: Config, **kwargs) -> None:
    """MkDocs hook entry point — runs before every mkdocs build / serve."""
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    skills = build_skills()
    recipes = build_recipes()
    (OUT_DIR / "skills.json").write_text(
        json.dumps(skills, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (OUT_DIR / "recipes.json").write_text(
        json.dumps(recipes, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    # Expose JSON to Jinja templates and Markdown {% for %} loops.
    config["extra_context"] = dict(config.get("extra_context", {}))
    config["extra_context"]["skills"] = skills
    config["extra_context"]["recipes"] = recipes
    log.info(
        "Wrote %d skills and %d recipes to %s and exposed them to Jinja",
        len(skills), len(recipes), OUT_DIR,
    )


if __name__ == "__main__":
    # Allow standalone execution for local testing.
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    on_pre_build({})