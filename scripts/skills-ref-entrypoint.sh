#!/bin/sh
# Wrapper pour le service skills-ref.
# Initialise le cache sparse-checkout de agentskills/agentskills au premier
# lancement, puis forward tous les arguments à `uv run skills-ref`.
set -eu

CACHE=/skills-ref-cache

# uv n'est pas dans l'image python:3.12-slim — toujours l'installer.
pip install --quiet --no-cache-dir uv >/dev/null

if [ ! -f "$CACHE/skills-ref/pyproject.toml" ]; then
  apt-get update
  apt-get install -y --no-install-recommends git
  git clone --filter=blob:none --no-checkout \
    https://github.com/agentskills/agentskills.git /tmp/agentskills
  cd /tmp/agentskills
  git sparse-checkout init --cone
  git sparse-checkout set skills-ref
  git checkout main
  cp -r /tmp/agentskills/skills-ref "$CACHE/skills-ref"
  cd /
  rm -rf /tmp/agentskills
  cd "$CACHE/skills-ref" && uv sync --quiet
fi

cd "$CACHE/skills-ref"
exec uv run skills-ref "$@"