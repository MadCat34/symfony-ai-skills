<?php

/*
 * Helper for scripts/check-method-signatures.sh.
 *
 * Reads a JSON array of Symfony\AI\* FQCNs on stdin and reflects each one, using
 * two autoload layers:
 *   1. A bare PSR-4 autoloader pointing straight at the monorepo's component
 *      src/ directories, registered FIRST so it always wins for Symfony\AI\*
 *      classes — a component's own vendor/ may carry a Packagist-installed
 *      copy of a sibling package (e.g. agent's vendor has its own copy of
 *      symfony/ai-platform), and we want the local checkout, not that copy.
 *   2. Each component's own vendor/autoload.php (from `composer install` run
 *      inside src/<component>/), for the external dependencies (psr/log,
 *      symfony/serializer, oskarstark/enum-helper, ...) that a bare PSR-4
 *      mapping alone cannot resolve.
 *
 * Prints {fqcn: {exists, error, methods: {name: {params, return, public,
 * static, declaringClass}}}} as JSON on stdout.
 *
 * Usage: php reflect-signatures.php <monorepo-root> < fqcns.json
 */

$mono = $argv[1] ?? null;
if (!$mono || !is_dir($mono)) {
    fwrite(STDERR, "usage: php reflect-signatures.php <monorepo-root> < fqcns.json\n");
    exit(1);
}

$components = [
    'Platform' => 'src/platform/src', 'Agent' => 'src/agent/src',
    'Chat' => 'src/chat/src',         'Store' => 'src/store/src',
    'AiBundle' => 'src/ai-bundle/src', 'McpBundle' => 'src/mcp-bundle/src',
    'Mate' => 'src/mate/src',
];

spl_autoload_register(function (string $class) use ($mono, $components): void {
    if (!str_starts_with($class, 'Symfony\\AI\\')) {
        return;
    }
    $rest = substr($class, \strlen('Symfony\\AI\\'));
    $parts = explode('\\', $rest);
    $component = array_shift($parts);
    if (!isset($components[$component])) {
        return;
    }
    $path = $mono . '/' . $components[$component] . '/' . implode('/', $parts) . '.php';
    if (is_file($path)) {
        require $path;
    }
});

foreach (array_values($components) as $srcDir) {
    $auto = $mono . '/' . \dirname($srcDir) . '/vendor/autoload.php';
    if (is_file($auto)) {
        require $auto;
    }
}

function type_to_string(?ReflectionType $type): ?string
{
    if (null === $type) {
        return null;
    }
    if ($type instanceof ReflectionNamedType) {
        $name = $type->getName();
        $nullable = $type->allowsNull() && 'null' !== strtolower($name) && 'mixed' !== strtolower($name);

        return ($nullable ? '?' : '') . $name;
    }
    if ($type instanceof ReflectionUnionType) {
        return implode('|', array_map('type_to_string', $type->getTypes()));
    }
    if ($type instanceof ReflectionIntersectionType) {
        return implode('&', array_map('type_to_string', $type->getTypes()));
    }

    return (string) $type;
}

function default_to_string(ReflectionParameter $p): ?string
{
    // Order matters: a variadic param reports isOptional() === true but has no
    // actual default, and isDefaultValueConstant()/getDefaultValue() throw on it.
    if (!$p->isDefaultValueAvailable()) {
        return null;
    }
    if ($p->isDefaultValueConstant()) {
        return $p->getDefaultValueConstantName();
    }
    try {
        $v = $p->getDefaultValue();
    } catch (\Throwable) {
        return null;
    }

    return match (true) {
        null === $v => 'null',
        \is_bool($v) => $v ? 'true' : 'false',
        \is_array($v) => '[' . implode(',', array_map(static fn ($x) => var_export($x, true), $v)) . ']',
        \is_object($v) => 'new ' . (new ReflectionClass($v))->getShortName() . '(...)',
        default => var_export($v, true),
    };
}

$fqcns = json_decode(file_get_contents('php://stdin'), true) ?? [];
$out = [];

foreach ($fqcns as $fqcn) {
    $entry = ['exists' => false, 'error' => null, 'methods' => []];
    try {
        $exists = class_exists($fqcn) || interface_exists($fqcn) || trait_exists($fqcn) || enum_exists($fqcn);
    } catch (\Throwable $e) {
        $entry['error'] = $e->getMessage();
        $out[$fqcn] = $entry;
        continue;
    }
    if (!$exists) {
        $out[$fqcn] = $entry;
        continue;
    }
    $entry['exists'] = true;

    try {
        $rc = new ReflectionClass($fqcn);
    } catch (\Throwable $e) {
        $entry['error'] = $e->getMessage();
        $out[$fqcn] = $entry;
        continue;
    }

    // One class' one method must never take the whole batch down with it.
    foreach ($rc->getMethods() as $rm) {
        try {
            $params = [];
            foreach ($rm->getParameters() as $p) {
                $params[] = [
                    'name' => $p->getName(),
                    'type' => type_to_string($p->getType()),
                    'variadic' => $p->isVariadic(),
                    'byref' => $p->isPassedByReference(),
                    'default' => default_to_string($p),
                ];
            }
            $entry['methods'][$rm->getName()] = [
                'params' => $params,
                'return' => type_to_string($rm->getReturnType()),
                'public' => $rm->isPublic(),
                'static' => $rm->isStatic(),
                'declaringClass' => $rm->getDeclaringClass()->getName(),
            ];
        } catch (\Throwable) {
            // Skip this one method; the class and its other methods are still reported.
            continue;
        }
    }
    $out[$fqcn] = $entry;
}

echo json_encode($out);
