#!/usr/bin/env bash
# Validate the PHP code blocks a reader is meant to copy-paste.
#
# Scope: SKILL.md and references/*.md EXCEPT references/api.md. The api.md files
# are signature catalogues (bodyless method declarations, ASCII namespace trees)
# that cannot parse as standalone PHP by construction; they are covered by
# scripts/check-symbols.sh instead, which verifies the symbols actually exist.
#
# Each extracted block is prefixed with `<?php` — without it, php -l treats the
# file as literal HTML and can never report an error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
shopt -s nullglob

for md in "$SKILL_DIR"/SKILL.md "$SKILL_DIR"/references/*.md; do
  [ -e "$md" ] || continue
  base="$(basename "$md" .md)"
  [ "$base" = "api" ] && continue

  out="$TMP/$base"
  mkdir -p "$out"

  # Extract every ```php block. Close on ANY fence line so a stray closing
  # language tag cannot swallow the prose that follows.
  awk -v outdir="$out" '
    /^```php$/ && !in_block { in_block=1; first=1; f=sprintf("%s/%03d.php", outdir, idx); next }
    /^```/     &&  in_block { in_block=0; idx++; next }
    in_block {
      # Only synthesise an opening tag when the snippet does not carry its own.
      if (first) { if ($0 !~ /^<\?php/) print "<?php" > f; first=0 }
      print > f
    }
  ' "$md"
done

while IFS= read -r f; do
  out=$(php -l "$f" 2>&1)
  if ! grep -q "No syntax errors" <<<"$out"; then
    rel="${f#$TMP/}"
    if [ "${rel%%/*}" = "SKILL" ]; then echo "FAIL $SKILL_DIR/SKILL.md (block ${rel##*/})"; else echo "FAIL $SKILL_DIR/references/${rel%%/*}.md (block ${rel##*/})"; fi
    echo "$out" | head -3
    fail=1
  fi
done < <(find "$TMP" -name '*.php' | sort)

exit "$fail"
