# Mate : Gotchas (post-audit)

Every item below is sourced from `src/mate/`. Misconceptions that exist in older documentation or training data are explicitly called out as `WRONG`/`CORRECT` pairs.

## 1. Extension discovery: `extra.ai-mate.extension`, NOT `keywords`

`WRONG`: "Mate auto-discovers packages via `keywords: ["symfony-ai-mate-extension"]`."

`CORRECT`: `ComposerExtensionDiscovery::discover()` (`src/Discovery/ComposerExtensionDiscovery.php:61-104`) iterates `vendor/composer/installed.json` and inspects `extra.ai-mate` on each package. The only relevance of `keywords` is whatever Composer itself does with it; Mate's discovery loop never reads them.

```jsonc
// Vendor extension — opt-in
"extra": { "ai-mate": { "scan-dirs": ["Capability"], "includes": ["config/config.php"] } }

// Root project — opt-out (set by `mate init`)
"extra": { "ai-mate": { "extension": false, "scan-dirs": ["mate/src"], "includes": ["mate/config.php"] } }
```

If `extra.ai-mate.extension === false`, discovery skips the package (`discover()` lines 75-77). Absent or `true` = discovered.

## 2. `extensions.php` is a key/value map, not a flat list

`WRONG`: `return ['symfony/ai-symfony-mate-extension', 'symfony/ai-monolog-mate-extension'];`

`CORRECT`: `ExtensionConfigSynchronizer::writeExtensionsFile()` (`src/Service/ExtensionConfigSynchronizer.php:113-136`) emits a string-keyed map with `['enabled' => bool]` values. `ContainerFactory::getEnabledExtensions()` (lines 171-192) walks the map and filters by `$config['enabled']`.

```php
<?php

// This file is managed by 'mate discover'
// You can manually edit to enable/disable extensions

return [
    'symfony/ai-symfony-mate-extension' => ['enabled' => true],
    'symfony/ai-monolog-mate-extension' => ['enabled' => false],
];
```

If `extensions.php` is malformed, `getEnabledExtensions()` returns `[]` and the root project (`_custom`) is the only extension loaded.

## 3. `config.php` is a `ContainerConfigurator` closure, not a flat array

`WRONG`: `return ['truncation' => [...], 'secrets_exclusion' => [...], 'log_level' => 'info'];`

`CORRECT`: `ContainerFactory::loadUserServices()` (lines 242-261) loads `mate/config.php` via `Symfony\Component\DependencyInjection\Loader\PhpFileLoader`. The file MUST return a `Closure(ContainerConfigurator): void`. The keys `truncation`, `secrets_exclusion`, `flat_structure`, `log_level` do not exist in this codebase.

```php
<?php

use Symfony\Component\DependencyInjection\Loader\Configurator\ContainerConfigurator;

return static function (ContainerConfigurator $container): void {
    $container->parameters()
        ->set('mate.skills_dir', '.agents/skills')
        ->set('mate.skill_mirrors', ['claude' => '.claude/skills']);

    $container->services()->defaults()->autowire()->autoconfigure();
};
```

Use `Symfony\AI\Mate\Container\MateHelper::disableFeatures()` (`src/Container/MateHelper.php`) for granular disabling : there is no framework-level `secrets_exclusion` or `truncation` config.

## 4. Env vars: only `MATE_DEBUG`, `MATE_DEBUG_FILE`, `MATE_DEBUG_LOG_FILE`

`WRONG`: `MATE_LOG_LEVEL`, `MATE_CACHE_DIR`, `MATE_TRUNCATION_LOG_LINES` exist as env vars.

`CORRECT`: `default.config.php` (lines 41-47) reads exactly three:

| Variable | Default | Effect |
|---|---|---|
| `MATE_DEBUG` | `false` | Enables PSR-3 debug logs |
| `MATE_DEBUG_FILE` | `false` | Also writes log lines to the file |
| `MATE_DEBUG_LOG_FILE` | `'dev.log'` | File path relative to `mate.root_dir` |

`mate/.env` is **not** auto-loaded. `ContainerFactory::loadEnvironmentVariables()` only acts when the `mate.env_file` parameter is set to a non-empty string in `mate/config.php`, and it requires `symfony/dotenv` (otherwise `MissingDependencyException`).

## 5. Cache dir: `sys_get_temp_dir()/mate/...`, not `'%kernel.cache_dir%/mate'`

`WRONG`: "The cache lives in `var/cache/mate/` (kernel.cache_dir)."

`CORRECT`:

- `default.config.php:50` sets `mate.cache_dir = sys_get_temp_dir().'/mate'`.
- `ContainerFactory::registerCoreServices()` (lines 59-69) overrides it to `sys_get_temp_dir().'/mate/<sanitizedUser>_<md5(rootDir)[0..8]>'` so concurrent projects share `/tmp/mate/` without colliding.

`mate.cache_dir` can be overridden in `mate/config.php` : `clear-cache` and `stop` both read this parameter.

## 6. `serve` flags: only `--force-keep-alive`

`WRONG`: `vendor/bin/mate serve [--host=…] [--port=…] [--http]`.

`CORRECT`: `ServeCommand::configure()` (lines 60-63) adds exactly one option: `--force-keep-alive`. The only transport is `new StdioTransport()`. There is no HTTP transport anywhere in the codebase.

`--force-keep-alive` requires the `bin/mate` wrapper (not raw `bin/mate.php`). Its semantics are the **inverse** of what the flag name suggests: `bin/mate:49` restarts the child only when `0 === $exitCode`, and stops on every non-zero code — signals (129–192) get a dedicated message, everything else a generic one, and both `exit($exitCode)`. A crashing server is therefore not restarted.

## 7. `discover` flags: `--composer` and `--ignore-missing-file` only

`WRONG`: `vendor/bin/mate discover --regenerate-instructions`.

`CORRECT`: `DiscoverCommand::configure()` (lines 60-64) adds two options:

- `--composer` : compact one-line output (used by the Composer plugin).
- `--ignore-missing-file` : exit `SUCCESS` immediately if `mate/extensions.php` is absent.

`mate/AGENT_INSTRUCTIONS.md` and the `AGENTS.md` managed block are regenerated on every `discover` automatically (`DiscoverCommand::execute()` → `AgentInstructionsMaterializer::materializeForExtensions()`). There is no separate `--regenerate-instructions` flag.

## 8. `mcp:tools:call` uses positional args, not `--arg=value`

`WRONG`: `vendor/bin/mate mcp:tools:call search-logs --query="error" --level=error`.

`CORRECT`: `ToolsCallCommand::configure()` (lines 65-71) accepts two positional arguments:

```bash
vendor/bin/mate mcp:tools:call search-logs '{"query": "error", "level": "error"}'
vendor/bin/mate mcp:tools:call server-info '{}'  # default if omitted
```

The JSON string is the second positional arg; it must be a JSON object (line 118: "JSON input must be an object"). Only `--format` is a flag (`pretty|json|toon`).

## 9. `mcp:tools:list` flags are `--filter`, `--extension`, `--format`

`WRONG`: `vendor/bin/mate mcp:tools:list [--extension=foo]`.

`CORRECT`: `ToolsListCommand::configure()` (lines 72-79) declares three options: `--filter` (glob with `*` and `?`), `--extension` (package name), `--format table|json|toon` (default `table`). All combinations work; missing filters that produce zero results raise `InvalidArgumentException`.

## 10. `mcp:tools:inspect` is positional + `--format`

`WRONG`: `vendor/bin/mate mcp:tools:inspect --tool=server-info`.

`CORRECT`: `vendor/bin/mate mcp:tools:inspect server-info --format=text|json|toon`. The tool name is the required positional argument (`configure()` lines 75-78).

## 11. `debug:extensions` flags are `--format text|json|toon`, `--show-all`

`WRONG`: `vendor/bin/mate debug:extensions --json`.

`CORRECT`: `DebugExtensionsCommand::configure()` (lines 101-106) declares exactly two options: `--format text|json|toon` (default `text`) and `--show-all` (default off, reveals disabled extensions).

## 12. Auto-discovery via the Composer plugin

`symfony/ai-mate-composer-plugin` is a runtime dependency of `symfony/ai-mate` (`src/mate/composer.json:36`). `MatePlugin::onPostInstallOrUpdate()` (`composer-plugin/src/MatePlugin.php:59-113`):

- Listens to `ScriptEvents::POST_INSTALL_CMD` and `ScriptEvents::POST_UPDATE_CMD`.
- If `mate/extensions.php` exists, runs `proc_open [\PHP_BINARY, $mateBin, 'discover', '--composer']` : i.e. compact output. The plugin owns the child process; failures are surfaced via `writeError()`.
- If `mate/extensions.php` does not exist, prints a banner suggesting `vendor/bin/mate init` and does nothing.

This means after the first `composer require --dev symfony/ai-mate` + `vendor/bin/mate init`, every subsequent `composer require/remove/update` of any package that declares `extra.ai-mate` will re-sync `mate/extensions.php` and re-install skills automatically.

## 13. `init` patches `composer.json` and `AGENTS.md`

`InitCommand::updateComposerJson()` (lines 252-315) writes (if missing):

```jsonc
"extra": {
    "ai-mate": {
        "extension": false,        // opt the root project OUT of vendor discovery
        "scan-dirs": ["mate/src"],
        "includes": ["mate/config.php"]
    }
},
"autoload-dev": {
    "psr-4": { "Mate\\": "mate/src/" }
}
```

If you delete these by hand, `discover` will start treating the root project as a vendor extension and you will get duplicated `_custom` entries in `debug:extensions`.

`InitCommand` also writes a managed block in `AGENTS.md` between `<!-- BEGIN AI_MATE_INSTRUCTIONS -->` / `<!-- END AI_MATE_INSTRUCTIONS -->` (`AgentInstructionsMaterializer::AGENTS_START_MARKER` / `AGENTS_END_MARKER`). Anything outside these markers is preserved verbatim.

## 14. Stop mechanism: PID file + `SIGUSR1`, not `pkill`

`WRONG`: `pkill -f "vendor/bin/mate"`.

`CORRECT`: `ServeCommand::execute()` (lines 96-99) writes `<cacheDir>/server_<pid>.pid`. `StopCommand::execute()` (lines 46-98) scans for `server_*.pid`, sends `posix_kill($pid, SIGUSR1)` (Windows: `taskkill /F /PID <pid>`), and unlinks the file.

`App::build()` (lines 71-75) registers the `SIGUSR1` handler that sets `RunnerControl::$state = RunnerState::STOP`, so the server exits gracefully when stopped.

`SIGUSR1` requires `posix` and `pcntl` extensions on non-Windows : `StopCommand` returns `Command::FAILURE` with a clear error if they are missing.

## 15. `mate.disabled_features` : the only selective-disable knob

`WRONG`: `mate/config.php` has a top-level `secrets_exclusion` / `flat_structure` / `truncation` section.

`CORRECT`: The only framework-supported way to disable a specific tool/resource/prompt/resource-template is the `mate.disabled_features` parameter, set via `Symfony\AI\Mate\Container\MateHelper::disableFeatures()` (see `src/Container/MateHelper.php`). The shape is `[extension => [feature => ['enabled' => false]]]`, and `FilteredDiscoveryLoader::isFeatureAllowed()` (lines 147-152) is the consumer.

## 16. Tool names are flat

`WRONG`: tools are named like `symfony.profiler.get_last_requests` or `doctrine.query.run`.

`CORRECT`: tool names are flat strings (e.g. `server-info`, `monolog-search`). `CapabilityCollector::formatTools()` (lines 98-111) keys the tools array by the bare attribute name. There is no dotted-namespace convention in this codebase.

## 17. Skill install: prefix `mate-` and refuse symlinks in skill trees

`SkillsInstaller::install()` (`src/Service/SkillsInstaller.php`) prefixes every skill directory with `mate-` (e.g. `mate-system-information`). Skills containing symlinks anywhere in their tree are rejected (`containsSymlink()` lines 165-189) to prevent a malicious package from exposing arbitrary files outside its own directory through the installed link. The source-of-truth lives in `.agents/skills/` and mirrors into `.claude/skills/` : both managed directories.

## 18. Real extension package names

`WRONG`: `symfony/profiler-extension`, `doctrine/query-extension`.

`CORRECT`: The bundled bridges are `symfony/ai-symfony-mate-extension` (`src/Bridge/Symfony/composer.json`) and `symfony/ai-monolog-mate-extension` (`src/Bridge/Monolog/composer.json`). Both use Composer package type `symfony-ai-mate` and `extra.ai-mate.scan-dirs: ["Capability"]` (singular, capitalised).

## 19. `mate/.env` is committed (not gitignored); neither is auto-loaded without config

`resources/mate/.gitignore` contains exactly one line: `.env.local`. So the file `mate/.env` itself is committed (empty by default), but `mate/.env.local` is not. Importantly, neither `.env` nor `.env.local` is auto-loaded unless you set `mate.env_file` (parameter) in `mate/config.php` AND have `symfony/dotenv` installed; otherwise loading is a no-op.

## See also

- `references/api.md` : the canonical command catalogue
- `references/patterns.md` : initial setup and bootstrap checks
