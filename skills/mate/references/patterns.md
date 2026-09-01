# Mate : Patterns

Three common patterns grounded in the actual `src/mate/` source.

## Contents

- 1. Initial setup
- 2. Custom extension with `extra.ai-mate.skills`
- 3. Bootstrap check
- 4. Reading skill files via a resource

## 1. Initial setup {#initial-setup}

```bash
composer require --dev symfony/ai-mate
vendor/bin/mate init          # asks how the agent should invoke Mate, then scaffolds mate/
composer dump-autoload         # registers the Mate\ autoloader
vendor/bin/mate discover       # also runs automatically via the Composer plugin on install/update
vendor/bin/mate skills:install # also runs inside `discover`; explicit re-sync only
```

`init` writes `mate/AGENT_INSTRUCTIONS.md` and updates the managed block in `AGENTS.md` (plus a `CLAUDE.md` import for Claude Code). There is no MCP config file to wire up — point the coding agent at these two files, or let it read them itself. Verify the tool surface with:

```bash
vendor/bin/mate tools:list
vendor/bin/mate debug:capabilities --extension=_custom
```

If the project runs inside a container (DDEV, Docker, Symfony CLI), answer `init`'s invocation prompt with the wrapper (`ddev exec vendor/bin/mate`, `symfony php vendor/bin/mate`, …) so the agent — and the interpreter-version check, once `mate.php_version` is set — runs Mate against the *application's* PHP, not the host's.

## 2. Custom extension with `extra.ai-mate.skills` {#custom-extension}

Build a vendor Composer package that ships tools plus skills. The skeleton below mirrors what `src/Bridge/Symfony/` and `src/Bridge/Monolog/` look like.

```text
acme/mate-myext/
├── composer.json
├── Capability/MyTools.php
├── config/config.php
├── INSTRUCTIONS.md
└── skills/my-pkg-tools/SKILL.md
```

`composer.json`:

```json
{
    "name": "acme/mate-myext",
    "type": "symfony-ai-mate",
    "require": {
        "php": ">=8.2",
        "symfony/ai-mate": "^0.13"
    },
    "autoload": {
        "psr-4": {
            "Acme\\MateMyext\\": ""
        }
    },
    "extra": {
        "ai-mate": {
            "scan-dirs": ["Capability"],
            "includes": ["config/config.php"],
            "instructions": "INSTRUCTIONS.md",
            "skills": ["skills"]
        }
    }
}
```

`Capability/MyTools.php` — the native `#[MateTool]` attribute, not an `mcp/sdk` one, and `name` is required:

```php
<?php

namespace Acme\MateMyext;

use Symfony\AI\Mate\Attribute\MateTool;

class MyTools
{
    #[MateTool(
        name: 'my-symfony-version',
        title: 'My Symfony Version',
        description: 'Return the running Symfony Kernel::VERSION constant',
    )]
    public function getSymfonyVersion(): string
    {
        return \Symfony\Component\HttpKernel\Kernel::VERSION;
    }
}
```

A tool returning data captured from the inspected application (not the case here — this one returns a constant) should wrap it with `ResponseEncoder::encodeUntrusted()` instead of `encode()`, so the agent knows to treat it as untrusted data rather than instructions (see `references/api.md`).

`config/config.php` (optional : only needed if you want to register extra services):

```php
<?php

use Acme\MateMyext\MyExtraService;
use Symfony\Component\DependencyInjection\Loader\Configurator\ContainerConfigurator;

return static function (ContainerConfigurator $container): void {
    $container->services()
        ->set(MyExtraService::class)
            ->autowire()
            ->public();
};
```

`skills/my-pkg-tools/SKILL.md` (standard agent-skill frontmatter):

```markdown
---
name: my-pkg-tools
description: Use when you need to…
---

# My Pkg Tools

…
```

Workflow:

```bash
composer require acme/mate-myext       # the plugin auto-runs vendor/bin/mate discover --composer
vendor/bin/mate skills:install          # explicit re-sync of extension skills
vendor/bin/mate tools:list              # confirm my-symfony-version is listed
```

On `discover` the new package is added to `mate/extensions.php` as `'acme/mate-myext' => ['enabled' => true]`, and each `skills/<name>/` directory becomes `mate-<name>`, copied into `.agents/skills/` (a real copy, safe to commit) and mirrored as a relative symlink under `.claude/skills/` (`SkillInstaller::install()` / `linkMirror()`). Stale `mate-*` entries in either directory are pruned on every install.

## 3. Bootstrap check {#bootstrap-check}

When the assistant cannot see Mate tools:

```bash
# 1. Verify Mate is installed and on PATH
vendor/bin/mate --version
# Symfony AI Mate 0.13.0

# 2. Verify the DI container builds and discover runs
vendor/bin/mate discover

# 3. Verify extensions are registered
vendor/bin/mate debug:extensions --show-all

# 4. Verify capabilities are advertised
vendor/bin/mate debug:capabilities --format=json | jq '.summary'

# 5. Verify a specific tool is reachable
vendor/bin/mate tools:inspect server-info --format=json
vendor/bin/mate tools:call server-info --format=pretty

# 6. If the cache is stale, blow it away
vendor/bin/mate clear-cache
```

If a tool is missing after `composer require acme/mate-myext`:

```bash
vendor/bin/mate debug:extensions --extension=acme/mate-myext --format=json
# Expect status: enabled, loaded: true
vendor/bin/mate debug:capabilities --extension=acme/mate-myext --type=tool
# Expect my-symfony-version listed
```

If the package shows `enabled: true` but `loaded: false`, the `extra.ai-mate.scan-dirs` or `extra.ai-mate.includes` paths are wrong relative to `vendor/<package>/`.

If a custom `#[MateTool]` method silently doesn't show up despite the extension loading, check for the two attribute mistakes discovery skips with only a log line : a missing `name` argument, or the attribute placed on the class instead of the method.

## 4. Reading skill files via a resource {#reading-skills-via-resource}

When the assistant needs the full text of an extension's `SKILL.md` (rather than relying on the copy under `.agents/skills/`), use a resource URI registered by the extension (the bundled `system-information` skill and the bridges ship their own).

```bash
# Inspect what resources are available
vendor/bin/mate debug:capabilities --type=resource --format=json

# Read one
vendor/bin/mate resources:read <uri> --format=pretty
```

For the bundled `system-information` skill shipped at `src/mate/skills/system-information/SKILL.md`, prefer reading it directly from disk (`cat .agents/skills/mate-system-information/SKILL.md`) : `discover` installs it as a real copy in your project, kept in sync with the `vendor/` source.

## See also

- `references/api.md` : full command catalogue, env vars, parameters, exception map
- `references/gotchas.md` : the audit-corrected list of misconceptions
