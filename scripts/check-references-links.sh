#!/usr/bin/env bash
# Verify cross-linking integrity between SKILL.md and references/*.md
# Ensures that all reference files in a skill directory are cited in the References section,
# and detects orphaned/uncited reference files.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

failed=0

for skill_md in skills/*/SKILL.md; do
    skill_dir=$(dirname "$skill_md")
    skill_name=$(basename "$skill_dir")
    references_dir="$skill_dir/references"

    # Skip skills without a references/ directory (e.g., symfony-ai orchestrator)
    if [ ! -d "$references_dir" ]; then
        continue
    fi

    # Find the References section in SKILL.md
    if ! grep -q "^## References" "$skill_md"; then
        echo "FAIL $skill_md: missing \"## References\" section" >&2
        ((failed++))
        continue
    fi

    # Extract reference file names from the References section
    # Look for patterns like [text](references/filename.md) or just references/filename
    declared_refs=$(sed -n '/^## References/,/^## /p' "$skill_md" | grep -o 'references/[a-z0-9_-]*\.md' | sed 's|references/||' | sort -u)

    # Check each file in references/ is cited in the section
    for ref_file in "$references_dir"/*.md; do
        ref_basename=$(basename "$ref_file")
        if ! echo "$declared_refs" | grep -q "^${ref_basename}$"; then
            echo "FAIL $skill_md: reference file \"$ref_basename\" not cited in References section" >&2
            ((failed++))
        fi
    done

    # Check each declared reference in the section actually exists
    for declared_ref in $declared_refs; do
        if [ ! -f "$references_dir/$declared_ref" ]; then
            echo "FAIL $skill_md: declared reference \"$declared_ref\" does not exist" >&2
            ((failed++))
        fi
    done
done




if [ "$failed" -gt 0 ]; then
    echo "$failed reference integrity issue(s)" >&2
    exit 1
fi

echo "OK: all reference links are consistent"
exit 0
