# Mate API Reference

All facts below come from `src/Command/*.php`, `src/default.config.php`, `src/Container/ContainerFactory.php`, `src/Service/ExtensionConfigSynchronizer.php`, `src/Service/SkillsInstaller.php`, `src/Discovery/ComposerExtensionDiscovery.php`, `src/Encoding/ResponseEncoder.php`, `src/Capability/ServerInfo.php`, `src/Container/MateHelper.php`, `src/Command/Trait/EnsuresToonFormatAvailabilityTrait.php`, `src/Command/Session/CliSession.php`, and the bridge `composer.json` files at `src/Bridge/Symfony/composer.json` and `src/Bridge/Monolog/composer.json`.

`vendor/bin/mate` is the wrapper (`bin/mate` + `bin/mate.php`); it locates the project's `vendor/autoload.php`, builds the DI container via `ContainerFactory`, and runs `App::build($container)` which registers all commands shown below.

---

## Global conventions

### Output formats

The `--format` flag is supported on inspection/call commands. Values:

| Value | Where | Notes |
|---|---|---|
| `text` | `debug:capabilities`, `debug:extensions` (default), `mcp:tools:inspect` (default) | Human-readable SymfonyStyle output |
| `json` | `debug:capabilities`, `debug:extensions`, `mcp:tools:list`, `mcp:tools:inspect`, `mcp:tools:call`, `mcp:resources:read` | Pretty JSON |
| `toon` | `debug:capabilities`, `debug:extensions`, `mcp:tools:list`, `mcp:tools:inspect`, `mcp:tools:call`, `mcp:resources:read` | TOON (Token-Oriented Object Notation); requires `composer require helgesverre/toon` (else `EnsuresToonFormatAvailabilityTrait::ensureToonFormatAvailable()` aborts with `Command::FAILURE`) |
| `table` | `mcp:tools:list` (default) | Console table (Tool Name / Description / Handler / Extension) |
| `pretty` | `mcp:tools:call` (default), `mcp:resources:read` (default) | SymfonyStyle definition list |

Tool responses use `Symfony\AI\Mate\Encoding\ResponseEncoder` which prefers TOON when the package is installed, otherwise JSON (`ResponseEncoder::encode()`).

### TOON availability

`EnsuresToonFormatAvailabilityTrait` (`src/Command/Trait/EnsuresToonFormatAvailabilityTrait.php`):

- `isToonFormatAvailable()` returns `true` iff `class_exists(Toon::class)`.
- If `--format=toon` is requested without `helgesverre/toon` installed, the command prints an error and a note pointing to `composer require helgesverre/toon`, then returns `Command::FAILURE`.

### STDIO only

`ServeCommand` constructs `new StdioTransport()` (`src/Command/ServeCommand.php:102`) : there is no HTTP transport anywhere in the codebase.

---

## Commands

### `init`

Source: `src/Command/InitCommand.php`. Idempotent : overwrites only if you confirm.

What it creates (`$files` array, lines 77-86):

| Path | Action |
|---|---|
| `mate/` | `mkdir 0750` (see `FilePermissions::DIRECTORY`) |
| `mate/extensions.php` | from `resources/mate/extensions.php` |
| `mate/config.php` | from `resources/mate/config.php`; chmod `0640` (`FilePermissions::FILE`) |
| `mate/.env` | from `resources/mate/.env`; chmod `0640` |
| `mate/.gitignore` | contains `.env.local` only |
| `mate/AGENT_INSTRUCTIONS.md` | from `resources/mate/AGENT_INSTRUCTIONS.md` |
| `mcp.json` | from `resources/mcp.json` (placeholders `##PHP_BINARY##`, `##MATE_ARGS##`) |
| `bin/codex` | shell shim for Codex CLI; chmod `0755` (`FilePermissions::EXECUTABLE`) |
| `bin/codex.bat` | Windows shim |
| `.mcp.json` | `symlink('mcp.json', '.mcp.json')` (offered to replace if exists) |
| `mate/src/` | your custom MCP tools; `.gitignore` empty file inside |

After `init` runs, `mcp.json` is patched via `applyPhpBinaryToMcpJson()` so `command` = chosen PHP binary (default `php`, or `ddev exec php` if `.ddev/` exists), and `args` = `[<extra>, './vendor/bin/mate', 'serve', '--force-keep-alive']` (`InitCommand::applyPhpBinaryToMcpJson()`).

`updateComposerJson()` writes (if missing):

```json
{
    "extra": {
        "ai-mate": {
            "extension": false,
            "scan-dirs": ["mate/src"],
            "includes": ["mate/config.php"]
        }
    },
    "autoload-dev": {
        "psr-4": {
            "Mate\\": "mate/src/"
        }
    }
}
```

Also writes a managed instructions block into `AGENTS.md` between `<!-- BEGIN AI_MATE_INSTRUCTIONS -->` and `<!-- END AI_MATE_INSTRUCTIONS -->` (`AgentInstructionsMaterializer::AGENTS_START_MARKER` / `AGENTS_END_MARKER`).

### `serve`

Source: `src/Command/ServeCommand.php`.

| Flag | Type | Notes |
|---|---|---|
| `--force-keep-alive` | `VALUE_NONE` | Must be used via the wrapper `bin/mate` (not raw `mate.php`); wrapper loops on non-zero exit. When invoked without the wrapper, the command prints a hint and returns `Command::INVALID`. |

Behaviour:

- Builds an MCP `Server` with `setProtocolVersion('2025-03-26')` (overridable via `mate.mcp_protocol_version`), `setServerInfo('Symfony AI Mate', '0.12.0', ...)`, `setRegistry(...)`, `setSession(new FileSessionStore(<cacheDir>/sessions))`, `setLogger(...)`, `setContainer(...)`.
- Aggregates instructions from all extensions and calls `setInstructions()` if non-null (`ServeCommand::execute()`).
- Writes PID file `<cacheDir>/server_<pid>.pid`, removes it in `finally`.
- Runs `new StdioTransport()`.

### `discover`

Source: `src/Command/DiscoverCommand.php`.

| Flag | Type | Notes |
|---|---|---|
| `--composer` | `VALUE_NONE` | Compact one-line-per-package output (used by the Composer plugin). |
| `--ignore-missing-file` | `VALUE_NONE` | Exit `SUCCESS` immediately if `mate/extensions.php` is absent. |

Behaviour:

- Calls `extensionDiscovery->discover()` and `extensionDiscovery->discoverRootProject()`.
- On zero extensions: still materialises `mate/AGENT_INSTRUCTIONS.md` + the `AGENTS.md` block for the root project.
- Otherwise: `extensionConfigSynchronizer->synchronize($extensions)` writes a fresh `mate/extensions.php` (preserving prior `enabled` flags : `ExtensionConfigSynchronizer::synchronize()`), then re-runs `AgentInstructionsMaterializer::materializeForExtensions()` and `SkillsInstaller::install()` for the enabled subset.

There is no `--regenerate-instructions` flag : instructions are regenerated on every `discover`.

### `stop`

Source: `src/Command/StopCommand.php`.

No flags. Behaviour (`StopCommand::execute()`):

- Scans `<cacheDir>` for files matching `server_*.pid`.
- On non-Windows: requires `posix_kill` + `SIGUSR1` (else `Command::FAILURE`). Sends `posix_kill($pid, SIGUSR1)` to each PID and removes the PID file.
- On Windows: `taskkill /F /PID <pid>`.

The signal is converted to `RunnerControl::$state = RunnerState::STOP` by `App::build()` (`src/App.php:71-75`) which registers `SIGUSR1` against the `getSignalRegistry()` when both `SIGUSR1` and `RunnerControl` exist.

### `clear-cache`

Source: `src/Command/ClearCacheCommand.php`. No flags. Walks `<cacheDir>` (default `sys_get_temp_dir()/mate/<user>_<hash>/`, see `ContainerFactory::registerCoreServices()`) with `Symfony\Component\Finder\Finder`, unlinks every file, then removes empty subdirectories.

### `debug:capabilities`

Source: `src/Command/DebugCapabilitiesCommand.php`.

| Flag | Type | Default | Notes |
|---|---|---|---|
| `--format` | `text\|json\|toon` | `text` | Output encoding |
| `--extension` | package name | : | Filter; `_custom` selects the root project |
| `--type` | `tool\|resource\|prompt\|template` | : | Filter by capability kind |

JSON/TOON result shape: `extensions` (map of extension name → capabilities grouped by `tools`/`resources`/`prompts`/`resource_templates`) plus `summary` (`extensions` count + totals per kind).

### `debug:extensions`

Source: `src/Command/DebugExtensionsCommand.php`.

| Flag | Type | Default | Notes |
|---|---|---|---|
| `--format` | `text\|json\|toon` | `text` | Output encoding |
| `--show-all` | `VALUE_NONE` | off | Include disabled extensions in the text listing |

JSON/TOON result shape: `extensions` (each entry: `type: 'root_project'|'vendor_extension'`, `status: 'enabled'|'disabled'`, `loaded: bool`, `scan_dirs: string[]`, `includes: string[]`, optional `agent_instructions: string`) + `summary` (`total_discovered`, `enabled`, `disabled`, `loaded`).

### `mcp:tools:list`

Source: `src/Command/ToolsListCommand.php`.

| Flag | Type | Default | Notes |
|---|---|---|---|
| `--filter` | glob pattern | : | `*` and `?` wildcards; case-insensitive |
| `--extension` | package name | : | Restrict to one extension |
| `--format` | `table\|json\|toon` | `table` | |

JSON/TOON shape: `tools` (map `toolName → {name, description, handler, input_schema, extension}`) + `summary.total`.

### `mcp:tools:inspect`

Source: `src/Command/ToolsInspectCommand.php`.

| Arg / Flag | Type | Default | Notes |
|---|---|---|---|
| `tool-name` | positional, required | : | Flat tool name, e.g. `server-info` |
| `--format` | `text\|json\|toon` | `text` | |

Text view: title = tool name, definition list (`Description`, `Handler`, `Extension`), then a JSON-formatted `Input Schema` section. JSON view dumps the full `{name, description, handler, input_schema, extension}` record.

### `mcp:tools:call`

Source: `src/Command/ToolsCallCommand.php`.

| Arg / Flag | Type | Default | Notes |
|---|---|---|---|
| `tool-name` | positional, required | : | Flat tool name |
| `json-input` | positional, optional | `'{}'` | JSON object with the tool's parameters |
| `--format` | `pretty\|json\|toon` | `pretty` | |

Behaviour: builds `CallToolRequest(name: toolName, arguments: params)`, creates a `CliSession` (`src/Command/Session/CliSession.php`, an `InMemorySessionStore`-backed `SessionInterface`), and dispatches via `Mcp\Capability\Registry\ReferenceHandler::handle()`. JSON-input errors and missing tools both yield `Command::FAILURE`.

### `mcp:resources:read`

Source: `src/Command/ResourcesReadCommand.php`.

| Arg / Flag | Type | Default | Notes |
|---|---|---|---|
| `uri` | positional, required | : | Static URI or template URI (e.g. `symfony-profiler://profile/abc123`) |
| `--format` | `pretty\|json\|toon` | `pretty` | |

Behaviour: resolves the URI against the registry (static or `ResourceTemplateReference` : variable extraction happens automatically). Renders `TextResourceContents` / `BlobResourceContents` separately.

### `skills:install`

Source: `src/Command/SkillsInstallCommand.php`. No flags. Re-runs `SkillsInstaller::install()` for all enabled extensions plus the root project. Already-installed skills are left untouched; dangling `mate-*` symlinks under `.agents/skills/` or `.claude/skills/` are pruned (`SkillsInstaller::pruneStale()`).

---

## Built-in core capability

`Symfony\AI\Mate\Capability\ServerInfo` (`src/Capability/ServerInfo.php`) : registered as MCP tool `server-info` via `#[McpTool(name: 'server-info', title: 'Server Info', description: 'Get PHP runtime environment details: version, OS, OS family, and loaded extensions')]`.

Returns a TOON (or JSON) object:

```php
[
    'php_version' => \PHP_VERSION,
    'operating_system' => \PHP_OS,
    'operating_system_family' => \PHP_OS_FAMILY,
    'extensions' => get_loaded_extensions(),
]
```

Discovered by the core package's own `extra.ai-mate.scan-dirs: [src/Capability]` (`composer.json:75-83`).

---

## Environment variables

Set in `src/default.config.php:41-47` and consumed at container build time:

| Variable | Type | Default | Effect |
|---|---|---|---|
| `MATE_DEBUG` | bool | `false` | Sets `mate.debug_enabled` → enables PSR-3 debug logs on the runtime `Logger` |
| `MATE_DEBUG_FILE` | bool | `false` | Sets `mate.debug_file_enabled` → also writes log lines to the file |
| `MATE_DEBUG_LOG_FILE` | string | `dev.log` | File path (relative to `mate.root_dir`) |

Other env vars (`MATE_LOG_LEVEL`, `MATE_CACHE_DIR`, `MATE_TRUNCATION_LOG_LINES`, etc.) do not exist in this codebase : do not invent them.

---

## DI parameters (defaults from `src/default.config.php`)

| Parameter | Default | Override via |
|---|---|---|
| `mate.cache_dir` | `sys_get_temp_dir().'/mate'` then overridden in `ContainerFactory::registerCoreServices()` to `sys_get_temp_dir().'/mate/<user>_<hash>'` | `mate/config.php` |
| `mate.root_dir` | project root containing `vendor/autoload.php` (resolved by `bin/mate.php`) | : |
| `mate.env_file` | `null` (disabled) | `mate/config.php`: `$container->parameters()->set('mate.env_file', '.env')` |
| `mate.disabled_features` | `[]` | `MateHelper::disableFeatures($container, [...])` |
| `mate.skills_dir` | `.agents/skills` | `mate/config.php` |
| `mate.skill_mirrors` | `['claude' => '.claude/skills']` | `mate/config.php` |
| `mate.debug_log_file` | `dev.log` | `MATE_DEBUG_LOG_FILE` |
| `mate.debug_file_enabled` | `false` | `MATE_DEBUG_FILE` |
| `mate.debug_enabled` | `false` | `MATE_DEBUG` |
| `mate.mcp_protocol_version` | `2025-03-26` | `mate/config.php` |
| `mate.extensions` | map from `extensions.php` after synchronisation | set by `ContainerFactory::loadExtensions()` |
| `mate.enabled_extensions` | package names with `enabled => true` | set by `ContainerFactory::loadExtensions()` |

---

## `extensions.php` : key/value map

Written by `ExtensionConfigSynchronizer::writeExtensionsFile()` (lines 113-136). Real shape (verified):

```php
<?php

// This file is managed by 'mate discover'
// You can manually edit to enable/disable extensions

return [
    'symfony/ai-symfony-mate-extension' => ['enabled' => true],
    'symfony/ai-monolog-mate-extension' => ['enabled' => false],
];
```

`ContainerFactory::getEnabledExtensions()` (lines 171-192) reads it with `include $extensionsFile`, expects a top-level array, and keeps only entries where `$config['enabled']` is truthy. Package names are written via `var_export()` to neutralise injection.

This is **not** a flat list of strings (`['vendor/pkg', 'vendor/pkg']` is wrong) and **not** a nested `[ ['package' => ..., 'enabled' => ...], ... ]` shape. It is a string-keyed map with `['enabled' => bool]` values.

---

## `config.php` : `ContainerConfigurator` closure

Loaded by `ContainerFactory::loadUserServices()` via `Symfony\Component\DependencyInjection\Loader\PhpFileLoader`. The file MUST return a `Closure(ContainerConfigurator): void`. Real scaffolded shape (`resources/mate/config.php`):

```php
<?php

use Symfony\Component\DependencyInjection\Loader\Configurator\ContainerConfigurator;

return static function (ContainerConfigurator $container): void {
    $container->parameters()
        // Override default parameters here
        // ->set('mate.cache_dir', sys_get_temp_dir().'/mate')
        // ->set('mate.env_file', '.env')   // enables mate/.env loading via symfony/dotenv
    ;

    $container->services()
        ->defaults()
            ->autowire()
            ->autoconfigure()

        // Register your custom services here
    ;
};
```

To disable features selectively (e.g. known-broken tools in a vendor extension), use `MateHelper`:

```php
use Symfony\AI\Mate\Container\MateHelper;
use Symfony\Component\DependencyInjection\Loader\Configurator\ContainerConfigurator;

return static function (ContainerConfigurator $container): void {
    MateHelper::disableFeatures($container, [
        'vendor/buggy-extension' => ['broken-tool', 'half-broken-tool'],
    ]);
};
```

The data structure produced is `mate.disabled_features = ['vendor/buggy-extension' => ['broken-tool' => ['enabled' => false], ...], ...]`, and `FilteredDiscoveryLoader::isFeatureAllowed()` (lines 147-152) consults it.

---

## `extra.ai-mate` extension manifest

Consumed by `src/Discovery/ComposerExtensionDiscovery.php`. Verbatim keys (from the docblock at lines 17-29 and the extractors at lines 253-477):

| Key | Type | Required? | Used for |
|---|---|---|---|
| `extension` | `bool` | No | `false` = skip discovery (root project uses this to opt out). Absent or `true` = discovered. |
| `scan-dirs` | `string[]` | No | Directories scanned by `Mcp\Capability\Discovery\Discoverer` for `#[McpTool]`/`#[McpResource]`/`#[McpPrompt]`. Relative to `vendor/<package>/`. |
| `includes` | `string[] \| string` | No | `ContainerConfigurator` PHP files loaded into the DI container. Relative to `vendor/<package>/`. |
| `instructions` | `string` | No | Path to `INSTRUCTIONS.md` aggregated into MCP `instructions`. Relative to `vendor/<package>/`. |
| `skills` | `string[] \| string` | No | Directories containing `SKILL.md` folders. Each subdir becomes `mate-<name>` under `.agents/skills/` and mirrors into `.claude/skills/mate-<name>`. Relative to `vendor/<package>/`. |

A single string for `includes` or `skills` is coerced to a one-element array (`extractIncludeFiles()` line 336-338, `extractSkillsDirs()` line 448-450).

Traversal is blocked by `PathGuard::hasTraversal()` : directories like `../../etc` are skipped with a warning.

### Real example packages (verified)

**`symfony/ai-symfony-mate-extension`** (`src/Bridge/Symfony/composer.json`):

```json
{
    "name": "symfony/ai-symfony-mate-extension",
    "type": "symfony-ai-mate",
    "extra": {
        "ai-mate": {
            "scan-dirs": ["Capability"],
            "includes": ["config/config.php"],
            "instructions": "INSTRUCTIONS.md"
        }
    }
}
```

**`symfony/ai-monolog-mate-extension`** (`src/Bridge/Monolog/composer.json`):

```json
{
    "name": "symfony/ai-monolog-mate-extension",
    "type": "symfony-ai-mate",
    "extra": {
        "ai-mate": {
            "scan-dirs": ["Capability"],
            "includes": ["config/config.php"],
            "instructions": "INSTRUCTIONS.md"
        }
    }
}
```

Both packages use Composer package type `symfony-ai-mate` (no `keywords` filter is applied at runtime).

### Root package self-declaration

`src/mate/composer.json:75-83`:

```json
{
    "extra": {
        "ai-mate": {
            "scan-dirs": ["src/Capability"],
            "instructions": "INSTRUCTIONS.md",
            "skills": ["skills"]
        }
    }
}
```

This is what makes the built-in `server-info` tool and the bundled `system-information` skill discoverable in the consuming project.

---

## Exceptions

| Class | Extends | Used by |
|---|---|---|
| `Symfony\AI\Mate\Exception\ExceptionInterface` | `\Throwable` | Marker interface for all Mate exceptions |
| `Symfony\AI\Mate\Exception\RuntimeException` | `\RuntimeException` implements `ExceptionInterface` | Base |
| `Symfony\AI\Mate\Exception\FileWriteException` | `RuntimeException` | : |
| `Symfony\AI\Mate\Exception\InvalidArgumentException` | `\InvalidArgumentException` implements `ExceptionInterface` | `DebugCapabilitiesCommand` (`filterExtensions()`, `filterByType()`), `ToolsListCommand` (`filterByExtension()`, `filterByName()`) |
| `Symfony\AI\Mate\Exception\MissingDependencyException` | `RuntimeException` | `ContainerFactory::loadEnvironmentVariables()` (raises when `symfony/dotenv` is missing and `mate.env_file` is set) |
| `Symfony\AI\Mate\Exception\UnsupportedVersionException` | `RuntimeException` | `App::addCommand()` (raised when neither `addCommand()` nor `add()` exists on the console `Application`) |

---

## Composer plugin (`symfony/ai-mate-composer-plugin`)

`composer-plugin/src/MatePlugin.php`:

- Subscribes to `ScriptEvents::POST_INSTALL_CMD` and `ScriptEvents::POST_UPDATE_CMD`.
- On each event: if `mate/extensions.php` exists, `proc_open` `vendor/bin/mate discover --composer` (compact output). Otherwise prints a banner suggesting `vendor/bin/mate init`.
- Declared as a runtime dependency of `symfony/ai-mate` via `"symfony/ai-mate-composer-plugin": "^0.12"` in `src/mate/composer.json:36`.

---

## Helper: `MateHelper::disableFeatures()`

`src/Container/MateHelper.php`. Accepts a map of `extension => [feature, ...]` and sets the `mate.disabled_features` parameter with the `{enabled: false}` shape that `FilteredDiscoveryLoader::isFeatureAllowed()` expects. Must be called once per config (later calls overwrite earlier ones).
