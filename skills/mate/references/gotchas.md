# Mate : Gotchas (post-audit)

Every item below is sourced from `src/mate/`. Misconceptions that exist in older documentation or training data (including Mate's own pre-0.13 shape) are explicitly called out as `WRONG`/`CORRECT` pairs.

## Contents

- 1. Extension discovery: `extra.ai-mate.extension`, NOT `keywords`
- 2. `extensions.php` is a key/value map, not a flat list
- 3. `config.php` is a `ContainerConfigurator` closure, not a flat array
- 4. Env vars: only `MATE_DEBUG`, `MATE_DEBUG_FILE`, `MATE_DEBUG_LOG_FILE`
- 5. Cache dir: `sys_get_temp_dir()/mate/...`, not `'%kernel.cache_dir%/mate'`
- 6. Mate is a CLI, not an MCP server — `serve`/`stop` no longer exist
- 7. `discover` flags: `--composer` and `--ignore-missing-file` only
- 8. `tools:call` takes long options, not a positional JSON blob
- 9. `tools:list` flags are `--filter`, `--extension`, `--format`
- 10. `tools:inspect` is positional + `--format`
- 11. `debug:extensions` flags are `--format text|json|toon`, `--show-all`
- 12. Auto-discovery via the Composer plugin
- 13. `init` patches `composer.json`, `AGENTS.md`, and `CLAUDE.md`
- 14. An unknown `--format` is rejected, not silently downgraded
- 15. `mate.disabled_features` : the only selective-disable knob
- 16. Tool names are flat
- 17. `.agents/skills/` is a real copy, not a symlink into `vendor/`
- 18. Real extension package names
- 19. `mate/.env` is committed (not gitignored); neither is auto-loaded without config
- 20. `extensions.php` splits editable state from tool-written state
- 21. `mate.invocation`/`mate.php_version` are not backfilled on an existing project
- 22. `symfony-services` and `monolog-tail` signature changes

## 1. Extension discovery: `extra.ai-mate.extension`, NOT `keywords`

`WRONG`: "Mate auto-discovers packages via `keywords: ["symfony-ai-mate-extension"]`."

`CORRECT`: `ComposerExtensionDiscovery::discover()` iterates `vendor/composer/installed.json` and inspects `extra.ai-mate` on each package. The only relevance of `keywords` is whatever Composer itself does with it; Mate's discovery loop never reads them.

```jsonc
// Vendor extension — opt-in
"extra": { "ai-mate": { "scan-dirs": ["Capability"], "includes": ["config/config.php"] } }

// Root project — opt-out (set by `mate init`)
"extra": { "ai-mate": { "extension": false, "scan-dirs": ["mate/src"], "includes": ["mate/config.php"] } }
```

If `extra.ai-mate.extension === false`, discovery skips the package. Absent or `true` = discovered.

## 2. `extensions.php` is a key/value map, not a flat list

`WRONG`: `return ['symfony/ai-symfony-mate-extension', 'symfony/ai-monolog-mate-extension'];`

`CORRECT`: `ExtensionConfigSynchronizer::writeExtensionsFile()` emits a string-keyed map with `['enabled' => bool]` values. `ContainerFactory::getEnabledExtensions()` walks the map and filters by `$config['enabled']`.

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

`CORRECT`: `ContainerFactory::loadUserServices()` loads `mate/config.php` via `Symfony\Component\DependencyInjection\Loader\PhpFileLoader`. The file MUST return a `Closure(ContainerConfigurator): void`. The keys `truncation`, `secrets_exclusion`, `flat_structure`, `log_level` do not exist in this codebase — nor does a `mate.skills_dir`/`mate.skill_mirrors` parameter (those directories are hardcoded constants, see gotcha 17).

```php
<?php

use Symfony\Component\DependencyInjection\Loader\Configurator\ContainerConfigurator;

return static function (ContainerConfigurator $container): void {
    $container->parameters()
        ->set('mate.invocation', 'vendor/bin/mate')
        ->set('mate.php_version', null);

    $container->services()->defaults()->autowire()->autoconfigure();
};
```

Use `Symfony\AI\Mate\Container\MateHelper::disableFeatures()` (`src/Container/MateHelper.php`) for granular disabling : there is no framework-level `secrets_exclusion` or `truncation` config.

## 4. Env vars: only `MATE_DEBUG`, `MATE_DEBUG_FILE`, `MATE_DEBUG_LOG_FILE`

`WRONG`: `MATE_LOG_LEVEL`, `MATE_CACHE_DIR`, `MATE_TRUNCATION_LOG_LINES` exist as env vars.

`CORRECT`: `default.config.php` reads exactly three:

| Variable | Default | Effect |
|---|---|---|
| `MATE_DEBUG` | `false` | Enables PSR-3 debug logs |
| `MATE_DEBUG_FILE` | `false` | Also writes log lines to the file |
| `MATE_DEBUG_LOG_FILE` | `'dev.log'` | File path relative to `mate.root_dir` |

`mate/.env` is **not** auto-loaded. `ContainerFactory::loadEnvironmentVariables()` only acts when the `mate.env_file` parameter is set to a non-empty string in `mate/config.php`, and it requires `symfony/dotenv` (otherwise `MissingDependencyException`).

## 5. Cache dir: `sys_get_temp_dir()/mate/...`, not `'%kernel.cache_dir%/mate'`

`WRONG`: "The cache lives in `var/cache/mate/` (kernel.cache_dir)."

`CORRECT`:

- `default.config.php` sets `mate.cache_dir = sys_get_temp_dir().'/mate'`.
- `ContainerFactory::registerCoreServices()` overrides it to `sys_get_temp_dir().'/mate/<sanitizedUser>_<md5(rootDir)[0..8]>'` so concurrent projects share `/tmp/mate/` without colliding.

`mate.cache_dir` can be overridden in `mate/config.php` : `clear-cache` reads this parameter.

## 6. Mate is a CLI, not an MCP server — `serve`/`stop` no longer exist

`WRONG`: `vendor/bin/mate serve [--force-keep-alive]`, `vendor/bin/mate stop`, an `mcp.json`/`.mcp.json` config file, an "editor MCP configuration" step.

`CORRECT`: 0.13 removed the `mcp/sdk` dependency, the `ServeCommand`/`StopCommand` classes, and the whole MCP server runtime (`App.php` registers no such commands, and `App::VERSION` is `'0.13.0'`). Mate is a one-shot CLI the coding agent invokes directly, the same way it runs `git status`. `mate init` no longer generates `mcp.json`, `.mcp.json`, or the Codex wrappers (`bin/codex`, `bin/codex.bat`); it writes `mate/AGENT_INSTRUCTIONS.md` and a managed block in `AGENTS.md`/`CLAUDE.md` instead. If you're carrying these files over from a pre-0.13 project, delete `mcp.json`, `.mcp.json`, `bin/codex`, `bin/codex.bat`, and stop invoking `mate serve`/`mate stop`.

## 7. `discover` flags: `--composer` and `--ignore-missing-file` only

`WRONG`: `vendor/bin/mate discover --regenerate-instructions`.

`CORRECT`: `DiscoverCommand::configure()` adds two options:

- `--composer` : compact one-line output (used by the Composer plugin).
- `--ignore-missing-file` : exit `SUCCESS` immediately if `mate/extensions.php` is absent.

`mate/AGENT_INSTRUCTIONS.md` and the `AGENTS.md` managed block are regenerated on every `discover` automatically (`DiscoverCommand::execute()` → `AgentInstructionsMaterializer::materializeForExtensions()`). There is no separate `--regenerate-instructions` flag.

## 8. `tools:call` takes long options, not a positional JSON blob

`WRONG`: `vendor/bin/mate mcp:tools:call search-logs '{"query": "error", "level": "error"}'` (the pre-0.13 shape).

`CORRECT`: the command is now `tools:call`, and each tool parameter is its own `--<param>=<value>` long option:

```bash
vendor/bin/mate tools:call search-logs --query=error --level=error
vendor/bin/mate tools:call server-info                                    # no parameters
vendor/bin/mate tools:call some-tool --json='{"tags": ["a", "b"]}'        # complex/array params, or a
                                                                            # param name that collides
                                                                            # with a reserved/global flag
```

A bare JSON-looking positional token is still accepted as a backwards-friendly alias for `--json` (`ToolsCallCommand::parseRawTokens()`), but it's an undocumented fallback, not the intended usage. Only `--format` (`pretty|json|toon`) and `--json` are reserved option names; everything else is treated as a dynamic tool parameter.

## 9. `tools:list` flags are `--filter`, `--extension`, `--format`

`WRONG`: `vendor/bin/mate mcp:tools:list [--extension=foo]` (pre-0.13 command name).

`CORRECT`: `vendor/bin/mate tools:list` declares three options: `--filter` (glob with `*` and `?`), `--extension` (package name), `--format table|json|toon` (default `table`). All combinations work; missing filters that produce zero results raise `InvalidArgumentException`.

## 10. `tools:inspect` is positional + `--format`

`WRONG`: `vendor/bin/mate mcp:tools:inspect --tool=server-info` (pre-0.13 command name).

`CORRECT`: `vendor/bin/mate tools:inspect server-info --format=text|json|toon`. The tool name is the required positional argument.

## 11. `debug:extensions` flags are `--format text|json|toon`, `--show-all`

`WRONG`: `vendor/bin/mate debug:extensions --json`.

`CORRECT`: `DebugExtensionsCommand::configure()` declares exactly two options: `--format text|json|toon` (default `text`) and `--show-all` (default off, reveals disabled extensions).

## 12. Auto-discovery via the Composer plugin

`symfony/ai-mate-composer-plugin` is a runtime dependency of `symfony/ai-mate`. `MatePlugin::onPostInstallOrUpdate()`:

- Listens to `ScriptEvents::POST_INSTALL_CMD` and `ScriptEvents::POST_UPDATE_CMD`.
- If `mate/extensions.php` exists, runs `proc_open [\PHP_BINARY, $mateBin, 'discover', '--composer']` : i.e. compact output. The plugin owns the child process; failures are surfaced via `writeError()`.
- If `mate/extensions.php` does not exist, prints a banner suggesting `vendor/bin/mate init` and does nothing.

This means after the first `composer require --dev symfony/ai-mate` + `vendor/bin/mate init`, every subsequent `composer require/remove/update` of any package that declares `extra.ai-mate` will re-sync `mate/extensions.php` and re-install skills automatically.

## 13. `init` patches `composer.json`, `AGENTS.md`, and `CLAUDE.md`

`InitCommand::updateComposerJson()` writes (if missing):

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

`InitCommand` also writes a managed block in `AGENTS.md` between `<!-- BEGIN AI_MATE_INSTRUCTIONS -->` / `<!-- END AI_MATE_INSTRUCTIONS -->`, and patches `CLAUDE.md` to import `AGENTS.md` so Claude Code picks up the same instructions. Anything outside the managed markers is preserved verbatim.

## 14. An unknown `--format` is rejected, not silently downgraded

`WRONG`: assuming `vendor/bin/mate tools:call server-info --format=csv` falls back to the human-readable `pretty` output with exit code `0`.

`CORRECT`: `EnsuresToonFormatAvailabilityTrait::ensureFormatSupported()` checks the value against the command's supported list and returns `Command::FAILURE` with `Unknown output format "csv". Supported: "pretty", "json", "toon".` on a miss. A script depending on the old silent-fallback behavior now gets a non-zero exit instead of an unparseable table.

## 15. `mate.disabled_features` : the only selective-disable knob

`WRONG`: `mate/config.php` has a top-level `secrets_exclusion` / `flat_structure` / `truncation` section.

`CORRECT`: The only framework-supported way to disable a specific tool/resource/resource-template is the `mate.disabled_features` parameter, set via `Symfony\AI\Mate\Container\MateHelper::disableFeatures()` (see `src/Container/MateHelper.php`). The shape is `[extension => [feature => ['enabled' => false]]]`, and `FilteredDiscoveryLoader::isFeatureAllowed()` is the consumer.

## 16. Tool names are flat

`WRONG`: tools are named like `symfony.profiler.get_last_requests` or `doctrine.query.run`.

`CORRECT`: tool names are flat strings (e.g. `server-info`, `monolog-search`). `CapabilityCollector::formatTools()` keys the tools array by the bare attribute name. There is no dotted-namespace convention in this codebase.

## 17. `.agents/skills/` is a real copy, not a symlink into `vendor/`

`SkillInstaller::install()` (`src/Skill/SkillInstaller.php`) prefixes every skill directory with `mate-` (e.g. `mate-system-information`) and places it under `.agents/skills/` as a **plain copy** of the source skill, not a symlink into `vendor/`. This is a deliberate change from the previous symlink-based approach : since the installed tree is a real copy, you can read and diff exactly what your agent will load, and committing `.agents/skills/` is safe and recommended (an upstream skill update then shows up as a reviewable diff). Mate does not add it to your `.gitignore`.

Only `.claude/skills/` is still a symlink : a **relative** link pointing at the corresponding `.agents/skills/` copy (falling back to a second copy when the filesystem does not support symlinks, e.g. some Windows setups — `SkillInstaller::linkMirror()`). Both `.agents/skills/` and `.claude/skills/` are Mate-managed and get pruned of stale `mate-*` entries on every `skills:install` (`pruneStrays()`). These two directory names are hardcoded constants (`SkillInstaller::AGENTS_SKILLS_DIR`/`CLAUDE_SKILLS_DIR`), not DI parameters — see gotcha 3.

To customize a skill's content instead of editing the generated copy directly (which gets overwritten on the next `skills:install`), set `'mode' => 'override'` for it in `mate/extensions.php` and edit your own copy under `mate/skills/<name>/` — see gotcha 20 below on `extensions.php` state.

## 18. Real extension package names

`WRONG`: `symfony/profiler-extension`, `doctrine/query-extension`.

`CORRECT`: The bundled bridges are `symfony/ai-symfony-mate-extension` (`src/Bridge/Symfony/composer.json`) and `symfony/ai-monolog-mate-extension` (`src/Bridge/Monolog/composer.json`). Both use Composer package type `symfony-ai-mate` and `extra.ai-mate.scan-dirs: ["Capability"]` (singular, capitalised).

## 19. `mate/.env` is committed (not gitignored); neither is auto-loaded without config

`resources/mate/.gitignore` contains exactly one line: `.env.local`. So the file `mate/.env` itself is committed (empty by default), but `mate/.env.local` is not. Importantly, neither `.env` nor `.env.local` is auto-loaded unless you set `mate.env_file` (parameter) in `mate/config.php` AND have `symfony/dotenv` installed; otherwise loading is a no-op.

## 20. `extensions.php` splits editable state from tool-written state

Per-skill entries in `mate/extensions.php` mix two kinds of fields (`SkillStateRepository`, `src/Skill/SkillStateRepository.php`):

- **Yours to edit**: `enabled` (bool) and `mode` (`'managed'` or `'override'`).
- **Written by `skills:install` on every run, do not hand-edit**: `state` (`'managed'` | `'override'` | `'disabled'`), `source`, `source_hash`, `hash`, and `targets`.

```php
return [
    'acme/mate-myext' => [
        'enabled' => true,
        'skills' => [
            'weather' => [
                'enabled' => true,
                'mode' => 'managed',        // yours: switch to 'override' to take ownership of the content
                'state' => 'managed',       // written by skills:install
                'source' => '...',          // written
                'source_hash' => '...',     // written
                'hash' => '...',            // written
                'targets' => ['...'],       // written
            ],
        ],
    ],
];
```

Setting `mode: 'override'` tells `skills:install` to stop overwriting that skill's `.agents/skills/mate-<name>/` copy from the upstream source on every run; place your own version under `mate/skills/<name>/` instead. If you previously ran a `0.13` development build before this field set stabilized, delete the now-unused `mate/skills.lock.php` — it is neither read nor written by the current version.

## 21. `mate.invocation`/`mate.php_version` are not backfilled on an existing project

`WRONG`: assuming an upgrade to 0.13 automatically pins `mate.php_version` and updates `mate.invocation` for you.

`CORRECT`: these two parameters are only asked interactively by `init` when `mate/config.php` does not yet exist. `discover` never adds them to an existing `mate/config.php`. An existing project therefore keeps `mate.invocation = 'vendor/bin/mate'` and `mate.php_version = null` (interpreter check off) until you add both by hand — do **not** re-run `vendor/bin/mate init` to do this: accepting its overwrite prompt replaces `mate/config.php` with the template and drops any services you registered in it. This matters most when the application does not run on the host (DDEV, Docker, Symfony CLI) : an unpinned Mate started on the host reports on the host's runtime, not the containerized one.

## 22. `symfony-services` and `monolog-tail` signature changes

`WRONG`: `json_decode($output, true)` on `symfony-services` gives you `id => class` directly; `monolog-tail --lines=50`.

`CORRECT`: `symfony-services` wraps its payload in the `untrusted_data` envelope (`json_decode($output, true)['untrusted_data']['services']`, plus `count`/`truncated`, nested per context for multi-kernel apps) and fails outright if no container has been dumped yet, instead of returning an empty result. `monolog-tail` takes `--limit`, not `--lines`.

## See also

- `references/api.md` : the canonical command catalogue
- `references/patterns.md` : initial setup and bootstrap checks
