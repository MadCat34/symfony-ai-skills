#!/usr/bin/env bash
# Deep check: for every Symfony\AI\* class/interface/trait signature block documented
# in skills/**/*.md (namespace + class/interface declaration with bodyless method
# signatures, as used throughout references/api.md), verify that:
#   1. the class/interface/trait actually exists in the symfony/ai monorepo
#      (reuses the same component-map resolution as check-symbols.sh), and
#   2. every method the docs cite on it actually exists there, with a matching
#      parameter count, parameter names (in order), and (best-effort) types/defaults.
#
# This goes one level deeper than check-symbols.sh, which only checks that a cited
# FQCN resolves to *some* file. That check does not catch a method that was
# renamed/removed/re-signatured while the class itself still exists — which is
# exactly the kind of drift a version bump introduces.
#
# Ground truth for step 2 comes from real PHP Reflection (scripts/reflect-signatures.php),
# not text parsing, whenever a component has `composer install`ed (run it inside
# src/<component>/ for each of the 7 components — see CLAUDE.md). Reflection sees
# inherited methods and gives fully-resolved types, so it also fixes the noisy
# false-WARNs a text-only comparison produces (fully-qualified vs `use`-imported
# short names, `self` vs the class name). A component without an installed
# `vendor/autoload.php` — or a class reflection still can't load (e.g. a base class
# from a package neither this repo nor the component composer-installed) — falls
# back to this script's own paren/brace-aware text parser, applied to both the doc
# block and the real source file, exactly as before.
#
# Monorepo location: $SYMFONY_AI_SRC, defaulting to ../symfony-ai
#
# Exit 1 on any FAIL (method missing, param count/name mismatch). Type/default/
# return-type/visibility mismatches print as WARN and do not fail the run — PHP
# type formatting has enough legitimate variance (nullable vs union, `self` vs
# class name, `array()` vs `[]`) that hard-failing on it would be noisy.

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MONO="${SYMFONY_AI_SRC:-$REPO/../symfony-ai}"

if [ ! -d "$MONO/src" ]; then
  echo "SKIP: monorepo not found at $MONO (set SYMFONY_AI_SRC)" >&2
  exit 0
fi

MONO="$MONO" REPO="$REPO" python3 - <<'PY'
import os, re, sys, glob, json, subprocess

MONO = os.environ['MONO']
REPO = os.environ['REPO']
os.chdir(REPO)

COMPONENTS = {
    'Platform': 'src/platform/src', 'Agent': 'src/agent/src',
    'Chat': 'src/chat/src',         'Store': 'src/store/src',
    'AiBundle': 'src/ai-bundle/src','McpBundle': 'src/mcp-bundle/src',
    'Mate': 'src/mate/src',
}

SYMBOL = re.compile(r'Symfony\\AI\\([A-Za-z]+)((?:\\[A-Za-z_][A-Za-z0-9_]*)+)')

def resolve_file(fqcn):
    """FQCN -> absolute .php path in the monorepo, or None (namespace-only / missing)."""
    m = SYMBOL.match(fqcn)
    if not m or m.group(1) not in COMPONENTS:
        return None
    parts = m.group(2).strip('\\').split('\\')
    base = os.path.join(MONO, COMPONENTS[m.group(1)], *parts)
    return base + '.php' if os.path.isfile(base + '.php') else None

# ---------------------------------------------------------------------------
# PHP-lite signature extraction (no autoload needed: single-file, regex/paren
# scanning, works identically on real source and on bodyless doc blocks).
# ---------------------------------------------------------------------------

def strip_php_comments(text):
    """Blank out // and /* */ comments, preserving newlines so line numbers stay
    aligned. Without this, an inline comment containing a comma (e.g. '// [model,
    app] visibility') is misread by the top-level comma splitter as an extra param."""
    out, i, n, in_str = [], 0, len(text), None
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == '\\':
                i += 1
                if i < n:
                    out.append(text[i])
            elif c == in_str:
                in_str = None
            i += 1
            continue
        if c in ('"', "'"):
            in_str = c
            out.append(c)
            i += 1
            continue
        if c == '/' and i + 1 < n and text[i + 1] == '/':
            j = text.find('\n', i)
            i = n if j == -1 else j
            continue
        if c == '/' and i + 1 < n and text[i + 1] == '*':
            j = text.find('*/', i + 2)
            if j == -1:
                i = n
            else:
                out.append('\n' * text.count('\n', i, j + 2))
                i = j + 2
            continue
        out.append(c)
        i += 1
    return ''.join(out)

def find_matching_paren(text, open_idx):
    depth = 0
    in_str = None
    i = open_idx
    while i < len(text):
        c = text[i]
        if in_str:
            if c == '\\':
                i += 1
            elif c == in_str:
                in_str = None
        else:
            if c in ('"', "'"):
                in_str = c
            elif c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
                if depth == 0:
                    return i
        i += 1
    return len(text) - 1

def extract_functions(text):
    """[{name, params_raw, return_type, modifiers, pos}] in source order."""
    out = []
    for m in re.finditer(r'\bfunction\s+&?\s*(\w+)\s*\(', text):
        name = m.group(1)
        open_idx = m.end() - 1
        close_idx = find_matching_paren(text, open_idx)
        params_raw = text[open_idx + 1:close_idx]
        j = close_idx + 1
        end_sig = j
        while end_sig < len(text) and text[end_sig] not in ';{':
            end_sig += 1
        tail = text[j:end_sig].strip()
        return_type = tail[1:].strip() if tail.startswith(':') else None
        back = m.start()
        while back > 0 and text[back - 1] not in ';{}':
            back -= 1
        modifiers = text[back:m.start()]
        out.append({'name': name, 'params_raw': params_raw, 'return_type': return_type,
                     'modifiers': modifiers, 'pos': m.start()})
    return out

def split_top_level(s, sep=','):
    parts, depth, in_str, cur = [], 0, None, []
    i = 0
    while i < len(s):
        c = s[i]
        if in_str:
            cur.append(c)
            if c == '\\':
                i += 1
                if i < len(s):
                    cur.append(s[i])
            elif c == in_str:
                in_str = None
        else:
            if c in ('"', "'"):
                in_str = c
                cur.append(c)
            elif c in '([{':
                depth += 1
                cur.append(c)
            elif c in ')]}':
                depth -= 1
                cur.append(c)
            elif c == sep and depth == 0:
                parts.append(''.join(cur))
                cur = []
            else:
                cur.append(c)
        i += 1
    if ''.join(cur).strip():
        parts.append(''.join(cur))
    return [p.strip() for p in parts if p.strip()]

def find_top_level_eq(s):
    depth = 0
    for i, c in enumerate(s):
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        elif c == '=' and depth == 0:
            prev = s[i - 1] if i > 0 else ''
            nxt = s[i + 1] if i + 1 < len(s) else ''
            if nxt != '>' and prev not in '=!<>':
                return i
    return None

MOD_RE = re.compile(r'^(public|private|protected|readonly)\s+')

def parse_param(raw):
    raw = re.sub(r'#\[[^\]]*\]\s*', '', raw.strip()).strip()
    default = None
    eq = find_top_level_eq(raw)
    if eq is not None:
        default = raw[eq + 1:].strip()
        raw = raw[:eq].strip()
    mods = []
    while True:
        m = MOD_RE.match(raw)
        if not m:
            break
        mods.append(m.group(1))
        raw = raw[m.end():]
    variadic = '...' in raw
    raw = raw.replace('...', '')
    m = re.search(r'(&)?\$(\w+)\s*$', raw)
    if m:
        name = m.group(2)
        byref = bool(m.group(1))
        type_ = raw[:m.start()].strip()
    else:
        name, byref, type_ = None, False, raw.strip()
    return {'mods': mods, 'variadic': variadic, 'byref': byref, 'name': name, 'type': norm_type(type_), 'default': norm_default(default)}

def norm_type(t):
    if not t:
        return ''
    t = t.strip()
    nullable = t.startswith('?')
    if nullable:
        t = t[1:]
    parts = sorted(p.strip().lstrip('\\') for p in t.split('|') if p.strip())
    if nullable and 'null' not in [p.lower() for p in parts]:
        parts.append('null')
    return '|'.join(sorted(parts, key=str.lower))

def type_basenames(t):
    """Union/intersection members reduced to their short (unqualified) name, for
    equivalence checks: doc text and reflection disagree on qualification style
    (`MessageBag` vs `Symfony\\AI\\Platform\\Message\\MessageBag`) far more often
    than on the actual type, so treat that difference as formatting, not a mismatch.
    Splits on `&` too (intersection types), unlike norm_type's canonical display form."""
    if not t:
        return frozenset()
    nullable = t.startswith('?')
    body = t[1:] if nullable else t
    names = {p.strip().lstrip('\\').rsplit('\\', 1)[-1].lower() for p in re.split(r'[|&]', body) if p.strip()}
    if nullable:
        names.add('null')
    return frozenset(names)

def types_equivalent(a, b, self_name=None):
    """self_name: the enclosing class's short name, so a documented `self`/`static`
    return type is compared against what it actually resolves to."""
    def resolve(x):
        if self_name and x.lstrip('?').lower() in ('self', 'static'):
            return ('?' if x.startswith('?') else '') + self_name
        return x
    return type_basenames(resolve(a)) == type_basenames(resolve(b))

def norm_default(d):
    if d is None:
        return None
    d = d.strip()
    d = re.sub(r'^array\s*\((.*)\)$', r'[\1]', d, flags=re.S)
    d = re.sub(r'\s+', '', d)
    # Doc convention elides a `new X(...)` default's actual arguments (whether the
    # real constructor takes zero or several); collapse both sides the same way so
    # `new NullLogger()` (doc, truly zero-arg) and reflect-signatures.php's own
    # always-`(...)` rendering of any object default don't read as a mismatch.
    d = re.sub(r'^(new\w+)\(.*\)$', r'\1(...)', d, flags=re.S)
    return d.lower() if d.lower() in ('null', 'true', 'false') else d

def parse_signature(func):
    params = [parse_param(p) for p in split_top_level(func['params_raw'])]
    return {'name': func['name'], 'params': params, 'return': norm_type(func['return_type']) if func['return_type'] else None,
            'is_public': 'private' not in func['modifiers'] and 'protected' not in func['modifiers']}

# ---------------------------------------------------------------------------
# Real-source signature cache: {abs_path: {method_name: signature}}
# ---------------------------------------------------------------------------

_source_cache = {}

def real_signatures(path):
    """Text-parser fallback: used when reflection couldn't load the class."""
    if path not in _source_cache:
        text = strip_php_comments(open(path, encoding='utf-8', errors='replace').read())
        sigs = {}
        for f in extract_functions(text):
            sigs[f['name']] = parse_signature(f)
        _source_cache[path] = sigs
    return _source_cache[path]

# ---------------------------------------------------------------------------
# Reflection: one batched call to reflect-signatures.php for every candidate
# FQCN, giving fully-resolved types and inherited methods for free.
# ---------------------------------------------------------------------------

def reflect_batch(fqcns):
    """{fqcn: {method_name: signature}} for every FQCN reflection could load."""
    script = os.path.join(REPO, 'scripts', 'reflect-signatures.php')
    if not fqcns or not os.path.isfile(script):
        return {}
    try:
        proc = subprocess.run(
            ['php', script, MONO], input=json.dumps(sorted(fqcns)),
            capture_output=True, text=True, timeout=120,
        )
        if proc.returncode != 0:
            print(f'WARN reflect-signatures.php exited {proc.returncode}: {proc.stderr[:300]}; '
                  f'falling back to text parsing for every class', file=sys.stderr)
            return {}
        data = json.loads(proc.stdout) if proc.stdout.strip() else {}
    except Exception as e:
        print(f'WARN reflection unavailable ({e}); falling back to text parsing for every class', file=sys.stderr)
        return {}

    out = {}
    for fqcn, entry in data.items():
        if not entry.get('exists') or entry.get('error'):
            continue
        sigs = {}
        methods = entry.get('methods')
        if not isinstance(methods, dict):
            methods = {}  # PHP encodes an empty assoc array as JSON [] -> Python list
        for mname, m in methods.items():
            params = []
            for p in m['params']:
                params.append({
                    'mods': [], 'variadic': p['variadic'], 'byref': p['byref'],
                    'name': p['name'], 'type': norm_type(p['type']), 'default': norm_default(p['default']),
                })
            sigs[mname] = {
                'name': mname, 'params': params,
                'return': norm_type(m['return']) if m['return'] else None,
                'is_public': m['public'],
            }
        out[fqcn] = sigs
    return out

# ---------------------------------------------------------------------------
# Markdown scan: pull out ```php blocks, track namespace/class context inside
# each, and diff every documented method against the real source.
# ---------------------------------------------------------------------------

CLASS_DECL = re.compile(r'^\s*(?:abstract\s+|final\s+)*(?:class|interface|trait|enum)\s+(\w+)', re.M)
NAMESPACE_DECL = re.compile(r'^\s*namespace\s+([A-Za-z0-9_\\]+)\s*;', re.M)
PHP_BLOCK = re.compile(r'```php\n(.*?)```', re.S)

fails, warns = [], []
checked_classes = set()
pending = []  # (fqcn, path_real, path, line_base, block, start, end)

# Pass 1: walk every doc block, resolve each documented class to a real file,
# and collect what needs a signature comparison — without doing the comparison
# yet, so we can reflect every candidate FQCN in a single batched PHP call.
for path in sorted(glob.glob('skills/**/*.md', recursive=True)):
    text = open(path, encoding='utf-8', errors='replace').read()
    for block_m in PHP_BLOCK.finditer(text):
        block = strip_php_comments(block_m.group(1))
        line_base = text[:block_m.start()].count('\n') + 1

        # Walk the block top-to-bottom, tracking current namespace/class,
        # and attribute each function found to the class declared before it.
        markers = sorted(
            [(m.start(), 'ns', m.group(1)) for m in NAMESPACE_DECL.finditer(block)] +
            [(m.start(), 'class', m.group(1)) for m in CLASS_DECL.finditer(block)]
        )
        cur_ns = None
        class_starts = []  # (class_name, ns_active_at_declaration, start_pos)
        for pos, kind, name in markers:
            if kind == 'ns':
                cur_ns = name
            else:
                class_starts.append((name, cur_ns, pos))
        class_spans = [  # (class_name, ns, start_pos, end_pos)
            (name, ns, pos, (class_starts[i + 1][2] if i + 1 < len(class_starts) else len(block)))
            for i, (name, ns, pos) in enumerate(class_starts)
        ]

        for class_name, ns, start, end in class_spans:
            if ns is None:
                continue  # no namespace declared in this block: cannot build a FQCN safely
            fqcn = f'{ns}\\{class_name}'
            path_real = resolve_file(fqcn)
            lineno = line_base + block[:start].count('\n')
            if path_real is None:
                # Only report as a problem if it looks like a real Symfony\AI\* symbol
                # (check-symbols.sh already owns "does this class exist" for prose
                # mentions; here we only care about ones with an explicit namespace).
                if SYMBOL.match(fqcn):
                    fails.append(f'FAIL {fqcn} (declared {path}:{lineno}) does not resolve to a file in the monorepo')
                continue

            checked_classes.add(fqcn)
            pending.append((fqcn, path_real, path, line_base, block, start, end))

reflected = reflect_batch({fqcn for fqcn, *_ in pending})
reflected_count = len(reflected)

# Pass 2: compare. Prefer reflection (fully-resolved types, inherited methods);
# fall back to this script's own text parser for classes reflection couldn't load.
for fqcn, path_real, path, line_base, block, start, end in pending:
            real = reflected.get(fqcn) or real_signatures(path_real)
            doc_funcs = [f for f in extract_functions(block[start:end])]
            for f in doc_funcs:
                doc_sig = parse_signature(f)
                doc_lineno = line_base + block[:start + f['pos']].count('\n')
                loc = f'{path}:{doc_lineno}'
                mname = doc_sig['name']
                if mname not in real:
                    fails.append(f'FAIL {fqcn}::{mname}() ({loc}) — no such method in {os.path.relpath(path_real, MONO)}')
                    continue
                real_sig = real[mname]
                if not real_sig['is_public']:
                    warns.append(f'WARN {fqcn}::{mname}() ({loc}) — documented as public but is private/protected in source')

                dp, rp = doc_sig['params'], real_sig['params']
                if len(dp) != len(rp):
                    fails.append(f'FAIL {fqcn}::{mname}() ({loc}) — {len(dp)} documented param(s), {len(rp)} in source')
                    continue
                for i, (d, r) in enumerate(zip(dp, rp)):
                    if d['name'] != r['name']:
                        fails.append(f"FAIL {fqcn}::{mname}() ({loc}) — param #{i+1} named '${d['name']}' in docs, '${r['name']}' in source")
                        continue
                    if d['variadic'] != r['variadic']:
                        warns.append(f"WARN {fqcn}::{mname}() ({loc}) — param ${d['name']} variadic mismatch (doc={d['variadic']}, source={r['variadic']})")
                    if d['type'] and r['type'] and not types_equivalent(d['type'], r['type']):
                        warns.append(f"WARN {fqcn}::{mname}() ({loc}) — param ${d['name']} type '{d['type']}' in docs, '{r['type']}' in source")
                    if d['default'] is not None and r['default'] is not None and d['default'] != r['default']:
                        warns.append(f"WARN {fqcn}::{mname}() ({loc}) — param ${d['name']} default '{d['default']}' in docs, '{r['default']}' in source")
                    if (d['default'] is None) != (r['default'] is None):
                        warns.append(f"WARN {fqcn}::{mname}() ({loc}) — param ${d['name']} default presence differs (doc={d['default']!r}, source={r['default']!r})")
                if doc_sig['return'] and real_sig['return'] and not types_equivalent(doc_sig['return'], real_sig['return'], self_name=fqcn.rsplit('\\', 1)[-1]):
                    warns.append(f"WARN {fqcn}::{mname}() ({loc}) — return type '{doc_sig['return']}' in docs, '{real_sig['return']}' in source")

fallback_count = len(checked_classes) - reflected_count
print(f'Checked {len(checked_classes)} documented class/interface/trait signature block(s) against {MONO} '
      f'({reflected_count} via reflection, {fallback_count} via text-parsing fallback)')
print()
for line in fails:
    print(line)
if fails:
    print()
for line in warns:
    print(line)
print()
print(f'{len(fails)} FAIL, {len(warns)} WARN')
sys.exit(1 if fails else 0)
PY
