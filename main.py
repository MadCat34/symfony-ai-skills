"""MkDocs-macros module.

The pre-build hook in ``scripts/build-skill-index.py`` writes the skill and
recipe indexes to ``.cache/skills-index/{skills,recipes}.json``. This
module loads those JSON files and re-exposes them as plain Jinja
variables so the Markdown pages can use them directly:

    {% for skill in skills %}
      ...
    {% endfor %}

    {% for recipe in recipes %}
      ...
    {% endfor %}

mkdocs-macros-plugin reads ``module_name: main`` from ``mkdocs.yml`` and
calls ``define_env(env)`` once per build.
"""
from __future__ import annotations

import json
from pathlib import Path


CACHE_DIR = Path(__file__).resolve().parent / ".cache" / "skills-index"


def _load(name: str) -> list[dict]:
    """Read a JSON list from the cache, returning [] when missing.

    Each item gets a 1-based ``index`` field injected so partials can
    render eyebrows like ``SKILL · 03`` without relying on the Jinja
    ``loop`` variable (which macros-plugin does not expose inside
    ``{% include %}`` partials).
    """
    path = CACHE_DIR / f"{name}.json"
    if not path.exists():
        return []
    items = json.loads(path.read_text(encoding="utf-8"))
    for i, item in enumerate(items, start=1):
        item.setdefault("index", i)
    return items


def define_env(env):
    """Expose the indexes as Jinja variables on every page."""
    env.variables["skills"] = _load("skills")
    env.variables["recipes"] = _load("recipes")
    import math
    env.filters["sin"] = lambda x: math.sin(math.radians(float(x)))
    env.filters["cos"] = lambda x: math.cos(math.radians(float(x)))


def on_pre_page_macros(env):
    """Mark the landing page so extra.css can scope the Atelier signature.

    The home page declares `home_page: true` in its front matter; every
    other page leaves it absent. We mirror the value as a Jinja variable
    so templates can branch on it and as a body class injected by
    Material via a small hook on ``on_pre_page``.
    """
    page = getattr(env, "page", None)
    if page is None:
        return None
    is_home = bool(page.meta.get("home_page", False))
    env.variables["is_home"] = is_home
    return None
