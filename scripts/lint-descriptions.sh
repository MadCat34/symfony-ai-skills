#!/usr/bin/env bash
# Lint skill descriptions for quality and routing compliance.
# Verifies that each SKILL.md has a description of minimum length and includes
# a "Do NOT trigger when" clause to preserve routing discipline.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

failed=0

for skill_md in skills/*/SKILL.md; do
    skill_dir=$(dirname "$skill_md")
    skill_name=$(basename "$skill_dir")

    # Extract description from frontmatter (between first and second ---)
    description=$(awk 'BEGIN{ok=0} /^---$/{ok++; next} ok==1 && /^description:/{
        gsub(/^description: /, "");
        gsub(/^["'"'"']|["'"'"']$/, "");
        print;
        exit
    }' "$skill_md")

    # Check 1: description exists and is non-empty
    if [ -z "$description" ]; then
        echo "FAIL $skill_md: description is empty" >&2
        ((failed++))
        continue
    fi

    # Check 2: description is at least 60 characters (short enough to read, long enough to be meaningful)
    desc_len=${#description}
    if [ "$desc_len" -lt 60 ]; then
        echo "FAIL $skill_md: description too short ($desc_len chars, min 60). Text: \"$description\"" >&2
        ((failed++))
    fi

    # Check 3: description contains "Do NOT trigger" clause (routing discipline)
    # Exception: orchestrators (meta-skills like symfony-ai) don't need this clause
    if ! echo "$description" | grep -q "Do NOT trigger"; then
        if ! echo "$skill_name" | grep -q "^symfony-ai$"; then
            echo "FAIL $skill_md: missing \"Do NOT trigger\" clause in description (routing discipline required)" >&2
            ((failed++))
        fi
    fi
done

if [ "$failed" -gt 0 ]; then
    echo "$failed description quality issue(s)" >&2
    exit 1
fi

echo "OK: all skill descriptions pass quality checks"
exit 0
