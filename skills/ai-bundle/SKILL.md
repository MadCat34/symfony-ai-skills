---
name: ai-bundle
description: Use when configuring Symfony AI components via YAML, registering tools with PHP attributes, or wiring Symfony Security (`#[IsGrantedTool]`) or Profiler integration. Triggers on `config/packages/ai.yaml`, `#[AsTool]`, `#[AsInputProcessor]`, `#[AsOutputProcessor]`, `#[IsGrantedTool]`. Do NOT trigger for raw library use without Symfony (use `platform` / `agent` / `store` / `chat` directly).
license: MIT
metadata:
  author: MadCat34
  email: madcat34@gmail.com
  url: https://github.com/MadCat34
  version: "0.2.0"
---

# AI Bundle

> ⚠️ **Symfony AI is experimental** : APIs may break between releases. Always check `UPGRADE.md` in the [symfony/ai monorepo](https://github.com/symfony/ai) before upgrading.

The Symfony integration layer for the AI components. Wires `Platform`, `Agent`, `Store`, `Chat`, `Indexer`, `Retriever`, `Vectorizer`, and `MultiAgent` as Symfony services; registers tools and processors via PHP attributes; integrates with Symfony Security (`#[IsGrantedTool]`), the Profiler data collector (auto-loaded when `kernel.debug` is true), and the DI compiler passes for processor ordering, JSON-schema provider validation, and traceable decorator wrapping.

Source of truth: `https://github.com/symfony/ai/tree/main/src/ai-bundle/` (namespace `Symfony\AI\AiBundle`).

## When to use AI Bundle vs raw components

Use **AI Bundle** when:

- You are in a Symfony app (or bundle) using the FrameworkBundle.
- You want YAML-configured services (no manual `new Platform(...)` calls).
- You want auto-discovery of `#[AsTool]` methods on your services.
- You want security gating via `#[IsGrantedTool]` on tool methods/classes.
- You want the Profiler / data collector showing platform calls, tool calls, agent calls, store calls, and message-store calls per request : automatically enabled when `kernel.debug` is true.

Use **raw components** (`platform`, `agent`, `store`, `chat`) when:

- You are in a non-Symfony app.
- You want minimal dependencies (no `symfony/framework-bundle`).

## Installation

```bash
composer require symfony/ai-bundle
# Plus the components you will use
composer require symfony/ai-platform symfony/ai-agent symfony/ai-store symfony/ai-chat
composer require symfony/ai-open-ai-platform
# OPENAI_API_KEY=sk-...
```

The bundle requires `symfony/framework-bundle` and either `symfony/security-core` is optional (`#[IsGrantedTool]`), `symfony/validator` (for `ValidateToolCallArgumentsListener` and structured-output validator subscriber) is optional. The bundle uses `willBeAvailable()` to remove services for missing optional packages : `AiBundle::loadExtension()` lines 387-413.

## Quick reference

`config/packages/ai.yaml`:

```yaml
ai:
    platform:
        openai:
            api_key: '%env(OPENAI_API_KEY)%'

    agent:
        default:
            platform: 'ai.platform.openai'
            model: 'gpt-4o-mini'
            tools:
                enabled: true   # auto-register every service tagged "ai.tool"
                # or an explicit list:
                # services:
                #     - 'App\AI\WeatherService'
            prompt: 'You are a helpful assistant.'

    store:
        pinecone:
            default:
                index_name: 'docs'

    indexer:
        docs:
            vectorizer: 'ai.vectorizer.default'
            store: 'ai.store.pinecone.default'

    vectorizer:
        default:
            platform: 'ai.platform.openai'
            model: 'text-embedding-3-small'

    chat:
        support:
            agent: 'ai.agent.default'
            message_store: 'ai.message_store.memory.support'
```

```php
namespace App\AI;

use Symfony\AI\Agent\Toolbox\Attribute\AsTool;

class WeatherService
{
    #[AsTool(name: 'get_weather', description: 'Get current weather for a city.', method: 'getWeather')]
    public function getWeather(string $city): string
    {
        return sprintf('Weather in %s: sunny, 22°C', $city);
    }
}
```

That's it. The bundle auto-discovers `WeatherService` via the `#[AsTool]` attribute (`AiBundle::loadExtension()` lines 333-339), registers it as a tool, wires the agent + platform, and injects everything via DI.

## Real config keys (top-level)

Source: `config/options.php`. The canonical root keys are:

| Key | Purpose |
| --- | --- |
| `ai.platform` | LLM providers (openai, anthropic, ollama, azure, gemini, …) |
| `ai.model` | Extra `class` + `capabilities` registered on the per-platform `ModelCatalog` |
| `ai.agent` | Agents (platform + model + tools + prompt + speech) |
| `ai.multi_agent` | Orchestrator + handoffs + fallback over multiple agents |
| `ai.store` | Vector stores grouped by provider (memory, pinecone, postgres, …) |
| `ai.vectorizer` | Vectorizer wrapping a platform and an embedding model |
| `ai.retriever` | Retriever over (store, vectorizer) |
| `ai.indexer` | Indexer built from loader + source + transformers + filters + vectorizer + store |
| `ai.chat` | Chat = (agent, message_store) |
| `ai.message_store` | Persistent message stores (cache, doctrine, memory, redis, …) |

**There is no `ai.profiler.*` key.** The data collector is added automatically when `kernel.debug` is true; see `AiBundle::loadExtension()` lines 381-384 and `DebugCompilerPass::process()` (no `ai.profiler.*` YAML exists).

**Processors are never listed under `ai.agent.*.input_processors` / `output_processors`.** They are auto-tagged via `#[AsInputProcessor]` / `#[AsOutputProcessor]` attributes, or auto-registered when a service implements `InputProcessorInterface` / `OutputProcessorInterface` (see `AiBundle::loadExtension()` lines 341-358).

**The only `fault_tolerance` key is `fault_tolerant_toolbox` (boolean, default `true`).** There is no `max_retries` or `circuit_breaker_threshold`.

**The agent key is `prompt:` accepting a string or array (`{ text | file, include_tools, enable_translation, translation_domain }`), not `system_prompt:`.**

**Store configuration is grouped by provider. The provider key (`pinecone`) is the parent key, not `bridge`.** Example: `ai.store.pinecone.default` (NOT `ai.store.<name>.bridge: pinecone`).

**`ai.chat.<name>` only takes `agent:` and `message_store:` keys.** There is no `ai.chat.<name>.chat_store.*`.

**`ai.platform.ollama` uses `endpoint:`, not `base_url:`.** `ai.platform.openai` and `ai.platform.anthropic` do NOT take `base_url:`.

See `references/config.md` for the full tree.

## Key gotchas

- **Autoconfiguration must be enabled** in `services.yaml`. The bundle relies on `_defaults: { autoconfigure: true }`. Without it, `#[AsTool]`, `#[AsInputProcessor]`, `#[AsOutputProcessor]`, and `#[IsGrantedTool]` are never registered.
- **Env var interpolation.** Use `'%env(VAR)%'` not `'%VAR%'` : the latter reads container parameters and is empty in production for env-only vars.
- **`#[IsGrantedTool]` always throws on denial.** The `IsGrantedToolAttributeListener::__invoke()` (lines 73-83) unconditionally throws `AccessDeniedException`; there is no `throwOnDenied: true` option. Remove the attribute or change the security expression if you want to allow graceful denial.
- **Security dependency missing.** If `symfony/security-core` is not installed, the listener is removed at compile time and `#[IsGrantedTool]` throws `InvalidArgumentException` at container build time (`AiBundle::loadExtension()` lines 368-374). Install `symfony/security-core` to enable it.
- **Processor ordering.** Built-in processors use priorities: `SystemPromptInputProcessor` = `-30`, `MemoryInputProcessor` = `-40`, the auto-injected tool `AgentProcessor` = `-10` (`AiBundle::processAgentConfig()` lines 1280-1282 and 1346-1377). Higher priority runs first.
- **Processor scope.** `#[AsInputProcessor(agent: '...')]` binds to a specific agent service id; `agent: null` (default) applies to all agents. `ProcessorCompilerPass::process()` lines 36-48 match either exact service id or null.
- **Profiling is on `kernel.debug`, not a YAML key.** When `kernel.debug` is false, `ai.data_collector` and `ai.traceable_toolbox` are removed. Do not try to enable the profiler via YAML.
- **`tools: enabled` is opt-in.** Default is no tools. Set `tools: true` (or `enabled: true`) to auto-register every `#[AsTool]` service, or pass an explicit `services:` list to constrain which tools an agent sees (`config/options.php` lines 267-313).
- **`fault_tolerant_toolbox` defaults to `true`.** A failing tool call becomes a structured denial that the LLM sees : disable only if you want uncaught exceptions.
- **No `ai.profiler.*` config, no `ai.agent.*.system_prompt`, no `ai.store.*.bridge`.** The current audited skill previously documented hallucinated keys; see `references/config.md` for the real tree.

## Common tasks

- **Register a platform**: add `ai.platform.<provider>` (e.g. `openai`, `anthropic`, `ollama`). Each provider has its own required keys (`api_key` for hosted providers, `endpoint` for ollama). See `references/config.md`.
- **Register an agent**: add `ai.agent.<name>` with `platform`, `model`, optional `tools`, `prompt`, `speech`. See `references/config.md`.
- **Gate a tool with security**: add `#[IsGrantedTool]` on the method or class. See `references/security.md`.
- **Custom processor auto-tagging**: implement `InputProcessorInterface`/`OutputProcessorInterface` for global hooks, or `#[AsInputProcessor(agent: '…')]` for scoped. See `references/processors.md`.
- **Build a RAG pipeline**: configure `ai.vectorizer` + `ai.store.<provider>.<name>`, then `ai.indexer` (with a loader or `source`) and `ai.retriever`. See `references/config.md`.
- **Persistent chat**: configure `ai.message_store.<provider>.<name>` (e.g. `doctrine`, `cache`, `redis`) and `ai.chat.<name>` referencing the agent + message_store service ids. See `references/config.md`.
- **Multi-agent routing**: configure agents under `ai.agent.<name>` and orchestration under `ai.multi_agent.<name>` with `orchestrator`, `fallback`, and `handoffs`. See `references/config.md`.
- **Debug in dev**: the Profiler data collector appears in the Web Debug Toolbar as soon as any AI component is invoked; no setup needed.

## References

- **YAML config reference**: [references/config.md](references/config.md)
- **Processors reference**: [references/processors.md](references/processors.md)
- **Security reference**: [references/security.md](references/security.md)
- **Patterns**: [references/patterns.md](references/patterns.md)
- **Gotchas**: [references/gotchas.md](references/gotchas.md)

## See also

- `mcp-bundle` skill : for MCP server registration inside your Symfony app
- `agent` skill : for the underlying Agent framework
- `platform`, `store`, `chat` skills : for raw usage without the bundle
