# AI Bundle : Gotchas

Exhaustive list, every item grounded in the source (`https://github.com/symfony/ai/tree/main/src/ai-bundle/`).

## Contents

- 1. Autoconfiguration must be enabled
- 2. Service tag duplicates
- 3. Env var interpolation
- 4. Profiler in production
- 5. Security context in async / Messenger handlers
- 6. Processor order overriding
- 7. Processor scope (per-agent vs global)
- 8. `IsGrantedTool` always throws
- 9. Cache clearing after schema change
- 10. Service IDs vs class names in `tools.services`
- 11. Missing optional package fails the build
- 12. Compiler-pass ordering

## 1. Autoconfiguration must be enabled

```yaml
# config/services.yaml — required
services:
    _defaults:
        autowire: true
        autoconfigure: true
```

If `autoconfigure: false` is set, `AiBundle::loadExtension()` calls `registerAttributeForAutoconfiguration(AsTool::class, …)` (lines 333-339), `AsInputProcessor` (lines 341-346), `AsOutputProcessor` (lines 348-353), and `IsGrantedTool` (lines 370-373) silently have no effect : your services are not tagged, and the agent never sees the tools. No warning is emitted.

## 2. Service tag duplicates

Two `#[AsTool]` attributes on the same method/class produce two tags. The bundle does **not** deduplicate by service id + tool name : `AiBundle::loadExtension()` lines 333-339 just calls `addTag('ai.tool', …)` per attribute occurrence. If you accidentally duplicate, the toolbox exposes the same tool twice and the LLM may pick either. Check with `bin/console debug:container --tag=ai.tool` after changes.

## 3. Env var interpolation

```yaml
# GOOD
api_key: '%env(OPENAI_API_KEY)%'

# BAD — reads from container parameters, not env vars at runtime
api_key: '%OPENAI_API_KEY%'
```

Container parameters are static after compilation. `'%VAR%'` interpolation from `.env` works only for parameters declared in `parameters:` (or `services:` arguments); env vars set via `APP_SECRET` / `OPENAI_API_KEY` must use `'%env(VAR)%'`. Otherwise the platform will start with `api_key: ''` in production.

## 4. Profiler in production

The data collector and traceable decorators are removed when `kernel.debug` is false (`AiBundle::loadExtension()` lines 381-384; `DebugCompilerPass::process()` line 32). There is **no** `ai.profiler.enabled` YAML key. Do not try to enable the data collector in production : it is intentionally absent.

If you want metrics in production, write a custom output processor (see `references/processors.md`) that pushes to your APM and tags it `#[AsOutputProcessor]` so it runs against every agent.

## 5. Security context in async / Messenger handlers

The `IsGrantedToolAttributeListener` (lines 73-83) calls `AuthorizationCheckerInterface::isGranted()`. Outside an HTTP request (Messenger handler, CLI command), the default token storage has no token and `isGranted('ROLE_ADMIN')` returns `false`. The bundle does not propagate the HTTP token into Messenger envelopes; you must set it in your own middleware.

Injecting `#[Target] Security $security` into a tool method does not help : the listener runs **before** the tool body, so by the time your method executes, authorization has already been decided.

## 6. Processor order overriding

`ProcessorCompilerPass::process()` sorts each agent's input and output processors by priority descending — the *same* comparator for both lists, so higher priority is first in **both** chains, not last on output. If you register the same processor via attribute **and** manually in `services.yaml` with two different priorities, you get two tags on the same service and the order is non-deterministic. Stick to one registration path.

Interface-tagged processors (`tagged_by: 'interface'`) are deduped per service (`ProcessorCompilerPass::process()` lines 38-40) : only the first tag of an interface-tagged service is kept.

## 7. Processor scope (per-agent vs global)

`#[AsInputProcessor(agent: 'ai.agent.<name>')]` binds to a specific service id. `agent: null` (or `#[AsInputProcessor]` with no args) applies to **every** `ai.agent.*` service (the compiler pass matches either exact id or null : lines 42-43).

Built-in `SystemPromptInputProcessor` and `MemoryInputProcessor` are tagged with the specific agent id (`AiBundle::processAgentConfig()` lines 1353, 1377) : they do not leak across agents. The `ToolProcessor` is tagged with the agent id and **both** input and output (lines 1281-1282).

## 8. `IsGrantedTool` always throws

The listener unconditionally throws `AccessDeniedException` on `isGranted() === false` (`IsGrantedToolAttributeListener::__invoke()` lines 73-83). There is no `throwOnDenied` parameter on the attribute and no `throw_on_tool_denied` key on `ai.agent.*`. To allow graceful denial, do not put `#[IsGrantedTool]` on the method : the toolbox will still expose it, or write a custom voter that always returns `true`.

Note: `fault_tolerant_toolbox: true` (default, `config/options.php` line 333) wraps **runtime** tool failures, not `AccessDeniedException`. The decorator (`FaultTolerantToolbox`) catches exceptions from the tool body; an `AccessDeniedException` thrown before the body runs propagates unchanged.

## 9. Cache clearing after schema change

If you change an `#[AsTool]` method's `name`, `description`, or `method`, the change does not take effect until you clear the container cache. The bundle does not hot-reload attribute metadata. Run `bin/console cache:clear --env=dev` (and `--env=prod` for prod builds).

The `SchemaProviderValidationPass` (`SchemaProviderValidationPass::process()` lines 28-66) also runs at compile time: if you add `#[Schema(provider: 'some.service')]` on a tool parameter, the provider must be tagged `ai.platform.json_schema.provider` (auto-registered via `SchemaProviderInterface`) or the container build fails.

## 10. Service IDs vs class names in `tools.services`

```yaml
ai:
    agent:
        default:
            tools:
                services:
                    - 'App\AI\WeatherService'             # class name (auto-resolved to its service id)
                    - service: 'app.weather_service'      # explicit service id
                    - agent: 'default'                    # wraps another agent as a sub-tool
                      name: 'delegate'
                      description: 'Delegate to the default agent.'
```

`config/options.php` lines 287-310 accept both. Class names work because Symfony's container resolves them to their default service id. Use service ids when the class is abstract or autowiring-disabled.

## 11. Missing optional package fails the build

`AiBundle::loadExtension()` lines 368-413 use `ContainerBuilder::willBeAvailable()` to remove services for missing optional packages. For most optional deps this is graceful. For `symfony/ai-agent` (used by `ai.agent.*`, `ai.multi_agent.*`, `ai.command.chat`), `symfony/ai-store` (used by `ai.store.*`, `ai.indexer.*`, `ai.retriever.*`), `symfony/ai-chat` (used by `ai.chat.*`, `ai.message_store.*`), and every per-provider bridge (e.g. `symfony/ai-open-ai-platform`), the bundle throws `RuntimeException` with a `composer require …` hint at compile time if you configure the key without installing the package.

For `symfony/security-core`, the autoconfig `IsGrantedTool` closure throws on any service carrying the attribute (lines 370-373). Install the package.

## 12. Compiler-pass ordering

Three passes are added (`AiBundle::build()` lines 180-182): `DebugCompilerPass`, `ProcessorCompilerPass`, `SchemaProviderValidationPass`. They are added in that order; Symfony DI runs them after the rest of the container is built. Adding your own pass that decorates `ai.agent.*` will run after `ProcessorCompilerPass`, which is the one that writes input/output processor arrays into agent arguments (lines 68-70). If you replace the agent definition entirely, your processors will be lost.

## See also

- `references/config.md` : full YAML reference
- `references/processors.md`
- `references/security.md`
- `references/patterns.md`
