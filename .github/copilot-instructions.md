# Copilot instructions

## Repository purpose

This is a content repository, not a Symfony application. It packages eight
agentskills.io-compatible Markdown skills for Symfony AI:

- `symfony-ai` is the orchestrator that routes ambiguous or cross-component
  requests.
- `platform`, `agent`, `chat`, `store`, `ai-bundle`, `mcp-bundle`, and `mate`
  document the individual Symfony AI components.

The same content is distributed as a Claude Code plugin, a Gemini CLI
extension, and a plain `skills/` directory for Codex and other compatible
agents. There is no `composer.json`, `package.json`, application runtime, or
build step. PHP code exists only in fenced snippets in the Markdown and is
syntax-checked, not executed.

Symfony AI is experimental. Verify API changes against the `symfony/ai`
monorepo (`README.md`, `AGENTS.md`, and `examples/`) and its `UPGRADE.md`
before updating documentation; do not rely on memory for API details.

## Architecture and content model

Each component skill uses progressive disclosure:

1. `skills/symfony-ai/SKILL.md` chooses the relevant component(s).
2. A component's `SKILL.md` provides routing, installation, a compact quick
   reference, architecture, gotchas, and conditional links to references.
3. `skills/<component>/references/` contains the detailed API catalogue,
   patterns, gotchas, and component-specific material.

Skill frontmatter descriptions are the routing mechanism. Keep descriptions
specific, include the required negative routing clause (`Do NOT trigger`),
and update sibling descriptions when changing overlapping boundaries. In
particular, `mcp-bundle` means building an MCP server inside a Symfony app,
whereas `mate` means letting an assistant inspect a running app; these must
remain mutually exclusive.

The `SKILL.md` files are routers and must stay below 500 lines. References
carry the detailed material. Every reference file must be linked from its
skill's `## References` section. Reference names are intentionally limited to:
`api`, `patterns`, `gotchas`, `bridges`, `embeddings`, `config`, `processors`,
and `security`. Adding another name requires updating both CI files and the
README convention table.

Keep `AGENTS.md` and `GEMINI.md` synchronized because they are consumer-facing
root context files. `CLAUDE.md` is maintainer-facing and may contain additional
repository details. Installation and distribution changes should also account
for `.claude-plugin/`, `gemini-extension.json`, `INSTALL.md`, and the plain
`skills/` layout.

The `platform`, `agent`, and `store` skills have eval fixtures under
`evals/`; these describe routing behavior but are not automatically run by
CI. The `symfony-ai` orchestrator is intentionally excluded from
reference-name and upstream skills-ref validation.

## Validation commands

There is no application test runner. The CI checks can be reproduced locally
from the repository root:

```bash
# Frontmatter names must match skill directory names; descriptions must exist.
for f in skills/*/SKILL.md; do
  d=$(basename "$(dirname "$f")")
  n=$(awk 'BEGIN{ok=0} /^---$/{ok++; next} ok==1 && /^name:/{print $2; exit}' "$f")
  [ "$n" = "$d" ] || echo "FAIL $f: name='$n' != dir='$d'"
done

# Validate description quality and reference links.
bash scripts/lint-descriptions.sh
bash scripts/check-references-links.sh

# Check all copy-pasteable PHP blocks (requires PHP on PATH).
bash scripts/check-snippets.sh

# Check all documented Symfony AI symbols against a local monorepo checkout.
SYMFONY_AI_SRC=../symfony-ai bash scripts/check-symbols.sh

# Optional: compare documented method signatures with the monorepo.
# Install component dependencies first if reflection is desired.
SYMFONY_AI_SRC=../symfony-ai bash scripts/check-method-signatures.sh
```

The remaining CI checks are package and upstream validation:

```bash
# Check every cited symfony/ai-* and symfony/mcp-* package on Packagist.
for p in $(grep -rhoE 'symfony/(ai|mcp)-[a-z0-9-]+' skills/ | sort -u); do
  curl -s -o /dev/null -w "$p %{http_code}\n" \
    "https://repo.packagist.org/p2/$p.json"
done

# Validate one skill (the targeted equivalent of the CI loop).
git clone --depth=1 https://github.com/agentskills/agentskills.git /tmp/skills-ref
python3 -m pip install --quiet -e /tmp/skills-ref/skills-ref
skills-ref validate skills/platform
```

For the upstream check, replace `skills/platform` with the skill being
changed. `skills/symfony-ai` is not a valid target for this command.

The symbol check skips cleanly if `SYMFONY_AI_SRC` is absent, but CI clones
the monorepo and runs it. The PHP snippet check deliberately excludes
`references/api.md`, whose bodyless signatures are catalogues rather than
standalone PHP programs. `test:skills-ref` is informational in CI
(`allow_failure` / `continue-on-error`).

## Source and maintenance conventions

- Package names cited under `skills/` must exist on Packagist; the check covers
  both `symfony/ai-*` and `symfony/mcp-*`.
- Every referenced `Symfony\AI\*` symbol must resolve in the matching
  component under the Symfony AI monorepo. Deliberately absent symbols belong
  in `scripts/known-absent-symbols.txt`.
- Prefer canonical examples and terminology from the upstream component
  source. Preserve the distinction between reusable component documentation
  and Symfony bundle integration.
- When adding or moving references, update the corresponding `SKILL.md`
  links, and when adding a non-standard reference name also update the
  approved-name case in `.gitlab-ci.yml` and `.github/workflows/ci.yml` plus
  the README table.
- Keep generated/distribution metadata consistent when changing the set of
  skills or supported clients.
