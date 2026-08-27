#!/usr/bin/env bash
# Verify that every Symfony\AI\* symbol cited in skills/ resolves to a real file
# in the symfony/ai monorepo.
#
# This is the guard that matters for this repository. `php -l` validates syntax,
# but the defects that actually reach readers are semantic: a perfectly
# well-formed `use` statement naming a class that does not exist.
#
# Monorepo location: $SYMFONY_AI_SRC, defaulting to ../symfony-ai
#
# Symbols the docs deliberately assert are ABSENT live in
# scripts/known-absent-symbols.txt. Those are checked in reverse: the run fails
# if such a symbol ever appears in the monorepo, because the doc's negative
# claim would then be stale.

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MONO="${SYMFONY_AI_SRC:-$REPO/../symfony-ai}"

if [ ! -d "$MONO/src" ]; then
  echo "SKIP: monorepo not found at $MONO (set SYMFONY_AI_SRC)" >&2
  exit 0
fi

MONO="$MONO" REPO="$REPO" python3 - <<'PY'
import os, re, sys, glob

MONO = os.environ['MONO']
REPO = os.environ['REPO']
os.chdir(REPO)

COMPONENTS = {
    'Platform': 'src/platform/src', 'Agent': 'src/agent/src',
    'Chat': 'src/chat/src',         'Store': 'src/store/src',
    'AiBundle': 'src/ai-bundle/src','McpBundle': 'src/mcp-bundle/src',
    'Mate': 'src/mate/src',
}

absent_file = 'scripts/known-absent-symbols.txt'
known_absent = set()
if os.path.exists(absent_file):
    for line in open(absent_file):
        line = line.split('#')[0].strip()
        if line:
            known_absent.add(line)

def resolve(component, parts):
    base = os.path.join(MONO, COMPONENTS[component], *parts)
    # A .php file is a class; a directory is a namespace segment.
    return os.path.exists(base + '.php') or os.path.isdir(base)

SYMBOL = re.compile(r'Symfony\\AI\\([A-Za-z]+)((?:\\[A-Za-z_][A-Za-z0-9_]*)+)')
missing, stale = {}, []

for path in sorted(glob.glob('skills/**/*.md', recursive=True)):
    for lineno, line in enumerate(open(path), 1):
        stripped = line.strip()
        # `namespace X;` declares, it does not reference. Docblock continuations
        # are prose about types, not imports.
        if stripped.startswith('namespace ') or stripped.startswith('*'):
            continue
        for m in SYMBOL.finditer(line):
            component, rest = m.group(1), m.group(2)
            if component not in COMPONENTS:
                continue
            parts = rest.strip('\\').split('\\')
            # Trailing lowercase segment = a method or property, not a class.
            if not parts[-1][:1].isupper():
                continue
            fqcn = m.group(0)
            if fqcn in known_absent:
                if resolve(component, parts):
                    stale.append((fqcn, f'{path}:{lineno}'))
                continue
            if not resolve(component, parts):
                missing.setdefault(fqcn, []).append(f'{path}:{lineno}')

for fqcn in sorted(missing):
    print(f'FAIL {fqcn} does not exist in the monorepo')
    for loc in missing[fqcn]:
        print(f'       {loc}')

for fqcn, loc in stale:
    print(f'FAIL {fqcn} is listed in {absent_file} but DOES exist now')
    print(f'       {loc} — the negative claim is stale')

total = len(missing) + len(stale)
print(f'{total} symbol problem(s)')
sys.exit(1 if total else 0)
PY
