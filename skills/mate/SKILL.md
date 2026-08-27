---
name: mate
description: "Use when you need the AI assistant to introspect or debug a running Symfony application : reading logs, the container, the profiler, query results : through the Mate MCP development server. Do NOT trigger when building an MCP server inside your own Symfony app : use the `mcp-bundle` skill for that. Dev tool only, never in production. Triggers on `vendor/bin/mate`, `MatePlugin`, `extra.ai-mate`, `mate/extensions.php`, `mcp:tools:list`, `debug:capabilities`."
license: MIT
compatibility: Requires vendor/bin/mate installed in the target Symfony app. Dev environment only, never production.
metadata:
  author: MadCat34
  email: madcat34@gmail.com
  url: https://github.com/MadCat34
  version: "0.12.0"
---

# Mate

> ⚠️ **Symfony AI is experimental** : APIs may break between releases. Always check `UPGRADE.md` in the [symfony/ai monorepo](https://github.com/symfony/ai) before upgrading.

> ⚠️ **DEV TOOL ONLY : never deploy Mate to production.** Mate exposes your application internals (logs, container, profiler, environment) to the AI assistant. That is fine in dev; catastrophic in prod.

Mate is the dev-time companion that lets the CURRENT AI assistant (Claude Code, Codex, OpenCode, Copilot, …) introspect a running PHP/Symfony app via the MCP protocol over **STDIO only**. It ships a one-binary MCP server (`vendor/bin/mate serve`) that editors wire into their MCP config; the server scans `vendor/` for extensions, aggregates their MCP tools/resources/prompts, and exposes them to the agent.

## When to use Mate vs MCP Bundle

Use **Mate** when:

- You want the CURRENT AI assistant to read YOUR app's internals.
- Dev workflow : debugging, profiling, learning.
- It is an editor plugin you launch on demand (STDIO, per-project).
- You want your app's MCP tools to be discovered from `vendor/` Composer packages.

Use **MCP Bundle** (see `mcp-bundle` skill) when:

- You build an MCP server inside your app for EXTERNAL agents.
- Product feature : exposes your domain to other agents.
- HTTP or STDIO transport for distributed use.

These two skills MUST NOT be used together; their descriptions contain mutually-exclusive trigger clauses.

## Installation

```bash
composer require --dev symfony/ai-mate
```

This pulls in `symfony/ai-mate-composer-plugin` (registered automatically via `composer.json`'s `require`) : see `composer-plugin/src/MatePlugin.php`. After every `composer install`/`composer update`, the plugin re-runs `vendor/bin/mate discover --composer` automatically when `mate/extensions.php` already exists.

Then run the one-time project bootstrap:

```bash
vendor/bin/mate init
```

`init` (see `src/Command/InitCommand.php`):

1. Creates `mate/` directory and scaffolds `mate/extensions.php`, `mate/config.php`, `mate/.env`, `mate/.gitignore`, `mate/AGENT_INSTRUCTIONS.md`.
2. Creates `mcp.json` (template with `##PHP_BINARY##` / `##MATE_ARGS##` placeholders), `bin/codex`, `bin/codex.bat`.
3. Creates a `.mcp.json` symlink pointing at `mcp.json` (so editors that probe either name work).
4. Asks for the PHP binary to launch Mate (defaults to `php`, or `ddev exec php` if `.ddev/` is detected) and patches `mcp.json` accordingly.
5. Creates `mate/src/` (your custom MCP tools) and adds `Mate\\ => mate/src/` to `autoload-dev.psr-4` in `composer.json`.
6. Patches `extra.ai-mate` into `composer.json` with `extension: false` (so the root project is not auto-discovered as a vendor extension), `scan-dirs: [mate/src]`, `includes: [mate/config.php]`.
7. Writes/updates the managed instructions block in `AGENTS.md` between `<!-- BEGIN AI_MATE_INSTRUCTIONS -->` and `<!-- END AI_MATE_INSTRUCTIONS -->` markers (`AgentInstructionsMaterializer::AGENTS_START_MARKER` / `AGENTS_END_MARKER`).

After `init`, run `composer dump-autoload` to register the `Mate\` autoloader.

## Command catalogue

Verified against `src/App.php` (every command below is registered there) and the command classes:

| Command                                          | Purpose                                                                                                    |
| ------------------------------------------------ | ---------------------------------------------------------------------------------------------------------- |
| `vendor/bin/mate init`                           | One-time bootstrap (creates `mate/`, `mcp.json`, `.mcp.json` symlink, patches `composer.json`/`AGENTS.md`) |
| `vendor/bin/mate serve`                          | Start MCP server over **STDIO only** (only flag: `--force-keep-alive`)                                     |
| `vendor/bin/mate discover`                       | Re-scan `vendor/`, write `mate/extensions.php`, regenerate `AGENTS.md` block, install skills               |
| `vendor/bin/mate stop`                           | Stop running Mate servers via PID file + `SIGUSR1`                                                         |
| `vendor/bin/mate clear-cache`                    | Wipe `sys_get_temp_dir()/mate/<user>_<hash>/`                                                              |
| `vendor/bin/mate debug:capabilities`             | Show all MCP capabilities grouped by extension                                                             |
| `vendor/bin/mate debug:extensions`               | Show discovery status (enabled/disabled/loaded)                                                            |
| `vendor/bin/mate mcp:tools:list`                 | List tools with `--filter`, `--extension`, `--format table\|json\|toon`                                    |
| `vendor/bin/mate mcp:tools:inspect <name>`       | Show tool schema (positional arg, `--format text\|json\|toon`)                                             |
| `vendor/bin/mate mcp:tools:call <name> '<json>'` | Execute a tool (positional args, `--format pretty\|json\|toon`)                                            |
| `vendor/bin/mate mcp:resources:read <uri>`       | Read an MCP resource (positional URI, `--format pretty\|json\|toon`)                                       |
| `vendor/bin/mate skills:install`                 | Re-sync extension skills into `.agents/skills/` + `.claude/skills/`                                        |

## Editor MCP configuration (STDIO only)

Mate speaks STDIO only : there is no HTTP transport. The scaffolded `mcp.json` is the source of truth (after `init` patches the PHP binary). The `.mcp.json` symlink is created so editors probing either name work.

`mcp.json` shape (after `init` resolves placeholders):

```json
{
    "mcpServers": {
        "symfony-ai-mate": {
            "command": "php",
            "args": ["./vendor/bin/mate", "serve", "--force-keep-alive"]
        }
    }
}
```

`--force-keep-alive` makes `bin/mate` (the wrapper) relaunch the child **after a clean exit** so the editor gets a fresh server when the client disconnects. The condition is `0 === $exitCode` (`bin/mate:49`): any non-zero code — a crash, or a signal (129–192) — stops the loop and propagates that code. It is not a crash-recovery mechanism.

## Configuration files (real shapes)

### `mate/extensions.php` : key/value map (NOT a flat list)

Generated by `ExtensionConfigSynchronizer::writeExtensionsFile()` (`src/Service/ExtensionConfigSynchronizer.php`):

```php
<?php

// This file is managed by 'mate discover'
// You can manually edit to enable/disable extensions

return [
    'symfony/ai-symfony-mate-extension' => ['enabled' => true],
    'symfony/ai-monolog-mate-extension' => ['enabled' => false],
];
```

Edit by hand to flip `true`/`false`; `discover` preserves your choices when re-syncing (`ExtensionConfigSynchronizer::synchronize()`).

### `mate/config.php` : `ContainerConfigurator` closure (NOT a flat PHP array)

Scaffolded from `resources/mate/config.php` and loaded by `ContainerFactory::loadUserServices()` via `Symfony\Component\DependencyInjection\Loader\PhpFileLoader`:

```php
<?php

use Symfony\Component\DependencyInjection\Loader\Configurator\ContainerConfigurator;

return static function (ContainerConfigurator $container): void {
    $container->parameters()
        // ->set('mate.cache_dir', sys_get_temp_dir().'/mate')
        // ->set('mate.env_file', '.env')   // enables loading mate/.env (and .env.local)
    ;

    $container->services()
        ->defaults()
            ->autowire()
            ->autoconfigure()

        // Register your custom services here
    ;
};
```

To selectively disable features from extensions, use `Symfony\AI\Mate\Container\MateHelper::disableFeatures($container, [...])` (see `src/Container/MateHelper.php`). The default `mate.disabled_features` parameter is `[]`.

### `mate/.env`

Empty by default. Only loaded if you set `mate.env_file` parameter (in `mate/config.php`) to a non-empty string. With `mate.env_file = '.env'`, `ContainerFactory::loadEnvironmentVariables()` loads `mate/.env` and optional `mate/.env.local` via `symfony/dotenv` (which is `require-dev` only : you must `composer require symfony/dotenv` for the runtime). Missing the package raises `MissingDependencyException`.

## Environment variables

Only three env vars are read by `default.config.php` (`src/default.config.php:41-47`):

- `MATE_DEBUG` : boolean, enables debug logging.
- `MATE_DEBUG_FILE` : boolean, also writes log lines to a file.
- `MATE_DEBUG_LOG_FILE` : file name (relative to `mate.root_dir`), default `dev.log`.

There are no `MATE_LOG_LEVEL` / `MATE_CACHE_DIR` / `MATE_TRUNCATION_LOG_LINES` env vars : those do not exist in this codebase.

## Extension discovery : `extra.ai-mate` keys

Extensions are NOT detected via `composer.json` `keywords`. The mechanism is in `src/Discovery/ComposerExtensionDiscovery.php`:

- The discovery loop iterates every package in `vendor/composer/installed.json` and reads `extra.ai-mate`.
- If `extra.ai-mate.extension === false` → skip (root project uses this to opt out).
- If the key is absent or `true` → discovered (subject to other checks).

Recognised keys (`extra.ai-mate.*`):

| Key            | Type                 | Purpose                                                                                                                                                             |
| -------------- | -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `extension`    | `bool`               | `false` to opt out of discovery (used by the root project). Absent/`true` = discovered.                                                                             |
| `scan-dirs`    | `string[]`           | Directories scanned for `#[McpTool]` / `#[McpResource]` / `#[McpPrompt]` attributes. Relative to `vendor/<package>/`.                                               |
| `includes`     | `string[] \| string` | PHP `ContainerConfigurator` files to load into the DI container. Relative to `vendor/<package>/`.                                                                   |
| `instructions` | `string`             | Path to an `INSTRUCTIONS.md` aggregated into the MCP handshake `instructions` field.                                                                                |
| `skills`       | `string[] \| string` | Directories containing skill subfolders (each must have a `SKILL.md`). Installed under `.agents/skills/mate-<name>` and mirrored into `.claude/skills/mate-<name>`. |

Real example packages (verified at `src/Bridge/Symfony/composer.json` and `src/Bridge/Monolog/composer.json`):

- `symfony/ai-symfony-mate-extension` : type `symfony-ai-mate`, scans `Capability`, includes `config/config.php`, instructions `INSTRUCTIONS.md`.
- `symfony/ai-monolog-mate-extension` : type `symfony-ai-mate`, scans `Capability`, includes `config/config.php`, instructions `INSTRUCTIONS.md`.

The root package `symfony/ai-mate` ships its own `extra.ai-mate` (`scan-dirs: [src/Capability]`, `instructions: INSTRUCTIONS.md`, `skills: [skills]`) and a built-in `Symfony\AI\Mate\Capability\ServerInfo` tool named `server-info`.

## Key gotchas

- **No keyword requirement.** Discovery runs against `vendor/composer/installed.json` and reads `extra.ai-mate.extension` to opt out. `keywords: ["symfony-ai-mate-extension"]` does NOT exist in this codebase and is not consulted.
- **`extensions.php` is a key/value map**, not a flat list of strings. ContainerFactory reads `enabled` per package.
- **`config.php` is a `ContainerConfigurator` closure**, not a flat PHP array. Use `$container->parameters()` / `$container->services()`.
- **Composer plugin auto-runs `discover --composer`** on every `composer install`/`composer update` once `mate/extensions.php` exists; it runs `proc_open` with `--composer` to keep output compact (`MatePlugin::onPostInstallOrUpdate()`).
- **`init` patches `composer.json`** with `extra.ai-mate.extension = false` and adds `autoload-dev.psr-4.Mate\\ => 'mate/src/'`. Do not undo these manually.
- **`discover` flags are only `--composer` and `--ignore-missing-file`** : there is no `--regenerate-instructions`; instructions are regenerated automatically on every `discover`.
- **`serve` has only `--force-keep-alive`** : no `--host`, `--port`, or `--http`. STDIO only.
- **`mcp:tools:call` uses positional args** : `vendor/bin/mate mcp:tools:call <tool-name> '<json-input>'` (default `'{}'`).
- **`stop` is PID-based**: PID file `sys_get_temp_dir()/mate/<user>_<hash>/server_<pid>.pid`, `StopCommand` reads it and sends `posix_kill($pid, SIGUSR1)` (or `taskkill /F /PID` on Windows). Do not `pkill -f mate` : you will hit unrelated processes.
- **Cache dir defaults to `sys_get_temp_dir().'/mate'`** then overridden to `sys_get_temp_dir().'/mate/<user>_<hash>'` by `ContainerFactory::registerCoreServices()` : NOT `'%kernel.cache_dir%/mate'`.
- **`mate.disabled_features`** (set via `MateHelper::disableFeatures()`) is the mechanism to selectively disable tools/resources/prompts/templates from extensions.
- **Tool names are flat** (e.g. `server-info`, `monolog-search`), never dotted (`symfony.profiler.get_last_requests`).

## Common tasks

- **Initial setup**: see `references/patterns.md#initial-setup`.
- **Custom extension with skills**: see `references/patterns.md#custom-extension`.
- **Bootstrap check**: see `references/patterns.md#bootstrap-check`.
- **Reading skill files via MCP**: see `references/patterns.md#reading-skills-via-mcp`.

## References

- **CLI reference**: [references/api.md](references/api.md)
- **Patterns**: [references/patterns.md](references/patterns.md)
- **Gotchas**: [references/gotchas.md](references/gotchas.md)

## See also

- `mcp-bundle` skill : for the inverse use case (you build an MCP server)
- `ai-bundle` skill : Symfony AI integration in your app (Mate is its dev companion)
