# Mate : Patterns

Three common patterns grounded in the actual `src/mate/` source.

## 1. Initial setup {#initial-setup}

```bash
composer require --dev symfony/ai-mate
vendor/bin/mate init
composer dump-autoload        # registers the Mate\ autoloader
vendor/bin/mate discover      # also runs automatically via the Composer plugin on install/update
vendor/bin/mate skills:install # also runs inside `discover`; explicit re-sync only
```bash

`init` writes `mcp.json` (with PHP-binary placeholders resolved) and a `.mcp.json` symlink to `mcp.json`. The agent should pick this up automatically : verify with:

```bash
vendor/bin/mate debug:capabilities --extension=_custom
```

For Claude Code, point it at `mcp.json` (or rely on the symlink). The MCP server is STDIO-only (`StdioTransport` in `ServeCommand::execute()`), and the recommended args are `["./vendor/bin/mate", "serve", "--force-keep-alive"]` : `bin/mate` wraps the actual call so the child is restarted on non-zero exits (`bin/mate` lines 26-62).

## 2. Custom extension with `extra.ai-mate.skills` {#custom-extension}

Build a vendor Composer package that ships MCP capabilities plus skills. The skeleton below mirrors what `src/Bridge/Symfony/` and `src/Bridge/Monolog/` look like.

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
        "symfony/ai-mate": "^0.12"
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
```php

`Capability/MyTools.php`:

```php
<?php

namespace Acme\MateMyext;

use Mcp\Capability\Attribute\McpTool;
use Symfony\AI\Mate\Encoding\ResponseEncoder;

class MyTools
{
    #[McpTool(
        name: 'my-symfony-version',
        title: 'My Symfony Version',
        description: 'Return the running Symfony Kernel::VERSION constant',
    )]
    public function getSymfonyVersion(): string
    {
        return ResponseEncoder::encode([
            'symfony_version' => \Symfony\Component\HttpKernel\Kernel::VERSION,
        ]);
    }
}
```

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
```yaml

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
vendor/bin/mate debug:capabilities      # confirm my-symfony-version is listed
```text

On `discover` the new package is added to `mate/extensions.php` as `'acme/mate-myext' => ['enabled' => true]`, and each `skills/<name>/` directory becomes `mate-<name>` under `.agents/skills/` and `.claude/skills/` (symlinked, see `SkillsInstaller::placeSkill()`). Dangling `mate-*` links are pruned on every install.

## 3. Bootstrap check {#bootstrap-check}

When the assistant cannot see Mate tools:

```bash
# 1. Verify Mate is installed and on PATH
vendor/bin/mate --version
# Symfony AI Mate 0.12.0

# 2. Verify the DI container builds and discover runs
vendor/bin/mate discover

# 3. Verify extensions are registered
vendor/bin/mate debug:extensions --show-all

# 4. Verify capabilities are advertised
vendor/bin/mate debug:capabilities --format=json | jq '.summary'

# 5. Verify a specific tool is reachable
vendor/bin/mate mcp:tools:inspect server-info --format=json
vendor/bin/mate mcp:tools:call server-info '{}' --format=pretty

# 6. If the cache is stale, blow it away
vendor/bin/mate clear-cache
```

If a tool is missing after `composer require acme/mate-myext`:

```bash
vendor/bin/mate debug:extensions --extension=acme/mate-myext --format=json
# Expect status: enabled, loaded: true
vendor/bin/mate debug:capabilities --extension=acme/mate-myext --type=tool
# Expect my-symfony-version listed
```text

If the package shows `enabled: true` but `loaded: false`, the `extra.ai-mate.scan-dirs` or `extra.ai-mate.includes` paths are wrong relative to `vendor/<package>/`.

## 4. Reading skill files via `mcp:resources:read` {#reading-skills-via-mcp}

When the assistant needs the full text of an extension's `SKILL.md` (rather than relying on the symlinked copy under `.agents/skills/`), use the MCP resources URI registered by the bundled `system-information` skill or your extension's own resources.

```bash
# Inspect what resources are available
vendor/bin/mate debug:capabilities --type=resource --format=json

# Read one
vendor/bin/mate mcp:resources:read <uri> --format=pretty
```

For the bundled `system-information` skill shipped at `src/mate/skills/system-information/SKILL.md`, prefer reading it directly from disk (`cat .agents/skills/mate-system-information/SKILL.md`) : it is symlinked into your project by `discover` and tracks the `vendor/` copy.

## See also

- `references/api.md` : full command catalogue, env vars, parameters, exception map
- `references/gotchas.md` : the audit-corrected list of misconceptions
