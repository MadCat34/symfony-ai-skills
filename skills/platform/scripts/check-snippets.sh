#!/usr/bin/env bash
# Validate all PHP code blocks in this skill's markdown files.
# Extracts fenced blocks marked ```php, writes them to a temp dir,
# runs `php -l` on each, exits non-zero if any block fails to lint.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

idx=0
fail=0
shopt -s globstar nullglob

# Extract php blocks from each markdown file
for md in "$SKILL_DIR"/SKILL.md "$SKILL_DIR"/references/*.md; do
  [ -e "$md" ] || continue
  out="$TMP/$(basename "$md" .md)"
  mkdir -p "$out"
  awk -v outdir="$out" -v idx="$idx" '
    /^```php$/ { in_block=1; out=sprintf("%s/%03d.php", outdir, idx); next }
    /^```$/ && in_block { in_block=0; idx++; next }
    in_block { print > out }
  ' "$md"
done

# Lint each extracted block
for f in "$TMP"/*.php; do
  [ -e "$f" ] || continue
  out=$(php -l "$f" 2>&1)
  if ! echo "$out" | grep -q "No syntax errors"; then
    echo "FAIL $f"
    echo "$out"
    fail=1
  fi
done

exit "$fail"