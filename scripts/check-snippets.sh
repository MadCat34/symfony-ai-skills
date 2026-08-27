#!/usr/bin/env bash
# Validate the PHP code blocks a reader is meant to copy-paste, across the whole
# repository — including chat/, ai-bundle/, mcp-bundle/ and mate/, which have no
# per-skill script of their own.
#
# Scope: every skills/**/*.md EXCEPT references/api.md. The api.md files are
# signature catalogues (bodyless method declarations, ASCII namespace trees)
# that cannot parse as standalone PHP by construction; they are covered by
# scripts/check-symbols.sh instead, which verifies the symbols actually exist.
#
# Each extracted block is prefixed with `<?php` unless it carries its own tag —
# without one, php -l treats the file as literal HTML and can never report an
# error.

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0

while IFS= read -r md; do
  case "$md" in */references/api.md) continue ;; esac

  out="$TMP/$(echo "${md%.md}" | tr '/' '_')"
  mkdir -p "$out"

  # Extract every ```php block. Close on ANY fence line so a stray closing
  # language tag cannot swallow the prose that follows.
  awk -v outdir="$out" '
    /^```php$/ && !in_block { in_block=1; first=1; f=sprintf("%s/%03d.php", outdir, idx); next }
    /^```/     &&  in_block { in_block=0; idx++; next }
    in_block {
      if (first) { if ($0 !~ /^<\?php/) print "<?php" > f; first=0 }
      print > f
    }
  ' "$md"
done < <(find skills -name '*.md' | sort)

while IFS= read -r f; do
  out=$(php -l "$f" 2>&1)
  if ! grep -q "No syntax errors" <<<"$out"; then
    rel="$(basename "$(dirname "$f")")"
    echo "FAIL $(echo "$rel" | tr '_' '/').md (block $(basename "$f"))"
    echo "$out" | head -3
    fail=1
  fi
done < <(find "$TMP" -name '*.php' | sort)

exit "$fail"
