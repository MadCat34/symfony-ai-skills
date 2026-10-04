---
name: symfony-ai-bundle
description: 'Use when wiring Symfony AI into a Symfony application with the AI Bundle: `config/packages/ai.yaml` for platforms, agents, stores and chats, services auto-registered as tools with `#[AsTool]`, tools restricted with `#[IsGrantedTool]`, processors, the profiler, or an agent given a remote MCP server''s tools (`mcp_server`). Not for plain PHP without the framework (use the component skills) or for building an MCP server (`symfony-mcp-bundle`).'
license: MIT
metadata:
  author: Romain Bastide <madcat34@gmail.com>
  url: https://github.com/MadCat34
  version: 0.14.2
  tags: symfony, php, ai, symfony-bundle, ai-yaml, configuration, dependency-injection, security, profiler
---

# Symfony AI Bundle

## Purpose

The Symfony integration layer for the AI components. It turns
`config/packages/ai.yaml` into `Platform`, `Agent`, `MultiAgent`, `Store`,
`Vectorizer`, `Indexer`, `Retriever` and `Chat` services; registers tools and
processors from PHP attributes; gates tools with Symfony Security
(`#[IsGrantedTool]`); and adds a Profiler data collector when `kernel.debug` is
true. Namespace: `Symfony\AI\AiBundle`.

## When to use

- A Symfony application (FrameworkBundle) that should get AI services from YAML
  instead of `new Platform(...)` calls.
- Services that should become agent tools automatically through `#[AsTool]`.
- Tools that only some users may call (`#[IsGrantedTool]`).
- Processors registered with `#[AsInputProcessor]` / `#[AsOutputProcessor]`.
- Seeing platform, tool, agent, store and message-store calls in the Profiler.
- Handing a remote MCP server's tools to an agent (`mcp_server`).

## When not to use

- Plain PHP without the Symfony framework: use `symfony-ai-platform`,
  `symfony-ai-agent`, `symfony-ai-store` or `symfony-ai-chat` directly.
- Building an MCP server inside the application: use `symfony-mcp-bundle`.
- Letting a coding assistant inspect the running application: use `symfony-ai-mate`.

## Prerequisites

PHP 8.2+, Symfony 7.3+ or 8.x with `symfony/framework-bundle`, the bundle, the
components it should wire, and a platform bridge:

```bash
composer require symfony/ai-bundle
composer require symfony/ai-platform symfony/ai-agent symfony/ai-store symfony/ai-chat
composer require symfony/ai-open-ai-platform
# OPENAI_API_KEY=sk-...
```

Optional: `symfony/security-core` for `#[IsGrantedTool]`, `symfony/validator`
for `ValidateToolCallArgumentsListener` and the structured-output validator.
The bundle removes the services of missing optional packages
(`AiBundle::loadExtension()`), and `services.yaml` must keep
`_defaults: { autoconfigure: true }`.

## Examples

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

    message_store:
        memory:
            support:
                identifier: 'session_id'

    chat:
        support:
            agent: 'ai.agent.default'
            # The id is built as ai.message_store.<type>.<name>; the store has
            # to be declared above or the container fails to compile.
            message_store: 'ai.message_store.memory.support'
```

A tool, discovered through its attribute and injected into the agent:

```php
namespace App\AI;

use Symfony\AI\Agent\Toolbox\Attribute\AsTool;

#[AsTool(name: 'get_weather', description: 'Get current weather for a city.', method: 'getWeather')]
class WeatherService
{
    public function getWeather(string $city): string
    {
        return sprintf('Weather in %s: sunny, 22°C', $city);
    }
}
```

## Configuration keys

Source: `config/options.php`. The root keys are:

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

## Key gotchas

- **Keys that do not exist**: there is no `ai.profiler.*` (the collector follows
  `kernel.debug`), no `ai.agent.*.system_prompt` (the key is `prompt:`, a string
  or `{ text | file, include_tools, enable_translation, translation_domain }`),
  no `ai.agent.*.input_processors` (processors come from attributes or
  interfaces), and no `ai.store.<name>.bridge` (the provider is the parent key:
  `ai.store.pinecone.default`).
- **`ai.chat.<name>` only takes `agent:` and `message_store:`.**
- **`ai.platform.ollama` uses `endpoint:`**; `openai` and `anthropic` take no `base_url:`.
- **Env vars use `'%env(VAR)%'`**, not `'%VAR%'`, which reads a container
  parameter and is empty in production for env-only values.
- **Tools are opt-in.** Without `tools: true` (or `enabled: true`) the agent has
  no tools; an explicit `services:` list narrows them.
- **`#[IsGrantedTool]` always throws `AccessDeniedException` on denial**
  (`IsGrantedToolAttributeListener::__invoke()`); there is no `throwOnDenied`
  option.
- **Processor order and scope.** Built-in priorities: `SystemPromptInputProcessor`
  = `-30`, `MemoryInputProcessor` = `-40` (`AiBundle::processAgentConfig()`);
  higher runs first. `#[AsInputProcessor(agent: '…')]` binds to one agent
  service id, `agent: null` to all.
- **`fault_tolerant_toolbox` defaults to `true`**: a failing tool call becomes a
  structured error the LLM sees. It is the only fault-tolerance key.

## Troubleshooting

| Error | Cause | Fix |
| --- | --- | --- |
| `… platform configuration requires "symfony/ai-…-platform" package. Try running "composer require …".` | The bridge for a configured platform is not installed. | Run the `composer require` from the message. |
| `Agent configuration requires "symfony/ai-agent" package. …` (same for store, chat, message store, vectorizer, indexer, retriever) | The YAML configures a component that is not installed. | Install the named component. |
| `Using #[IsGrantedTool] attribute requires additional dependencies. Try running "composer install symfony/security-core".` | `symfony/security-core` is missing. | `composer require symfony/security-core`. |
| `The "mcp_server" tool configuration requires "symfony/ai-mcp-tool" package. …` (or `"symfony/mcp-bundle"`) | `mcp_server` tools need both packages. | Install both, then declare the connection under `mcp.clients`. |
| `Unrecognized option "system_prompt" under "ai.agent.default"` | A key that does not exist (see Key gotchas). | Use the real key: `prompt:`, `endpoint:`, `ai.store.<provider>.<name>`. |
| `The service "ai.chat.support" has a dependency on a non-existent service "ai.message_store.memory.support".` | A chat references a message store that is not declared. | Declare it under `ai.message_store.<type>.<name>` first. |
| The agent never calls a `#[AsTool]` service | Autoconfiguration is off, or `tools` is not enabled for that agent. | Keep `autoconfigure: true`; set `tools: true` or list the service. |

## Limitations

- The bundle is experimental: configuration keys change between minor
  versions. Pin `symfony/ai-bundle` and read `UPGRADE.md` in the monorepo
  before upgrading.
- Symfony 7.3+ or 8.x with FrameworkBundle only.
- The Profiler integration has no YAML switch: it exists only when
  `kernel.debug` is true.
- A `MultiAgent` cannot receive processors (`ProcessorCompilerPass` skips it).

## Usage

- **Register a platform**: add `ai.platform.<provider>` with its required keys
  (`api_key` for hosted providers, `endpoint` for ollama).
- **Register an agent**: add `ai.agent.<name>` with `platform`, `model`,
  optional `tools`, `prompt`, `speech`.
- **Gate a tool**: add `#[IsGrantedTool]` on the method or class.
- **Add a processor**: implement `InputProcessorInterface` /
  `OutputProcessorInterface` for every agent, or `#[AsInputProcessor(agent: '…')]`
  for one.
- **Build a RAG pipeline**: configure `ai.vectorizer` and
  `ai.store.<provider>.<name>`, then `ai.indexer` (a loader or `source`) and
  `ai.retriever`.
- **Persist a chat**: configure `ai.message_store.<provider>.<name>` (e.g.
  `doctrine`, `cache`, `redis`) and `ai.chat.<name>` referencing the agent and
  message-store service ids.
- **Route between agents**: configure agents under `ai.agent.<name>` and the
  orchestration under `ai.multi_agent.<name>` (`orchestrator`, `fallback`, `handoffs`).
- **Debug in dev**: the data collector appears in the Web Debug Toolbar as soon
  as an AI component runs; agent calls, platform invocations and tool
  executions also show in the performance timeline.
- **Give an agent a remote MCP server's tools**: declare the connection under
  `mcp.clients` (`symfony-mcp-bundle`), then add `- mcp_server: '<client>.<server>'`
  to the agent's `tools:` list.
- **Run tool calls concurrently**: `tools: { execution_strategy: fiber, services: [...] }`.
- **Resolve async jobs in a worker**: inject `Symfony\AI\Platform\Job\JobRunner`
  and `JobClientInterface $<platform>` (e.g. `$openai`).

## References

- Read [`references/config.md`](references/config.md) when writing or fixing
  `ai.yaml`: the full option tree, per-provider keys, `ai.agent` tools,
  `mcp_server`, async jobs.
- Read [`references/processors.md`](references/processors.md) when adding or
  ordering input/output processors.
- Read [`references/security.md`](references/security.md) when restricting
  tools with `#[IsGrantedTool]`.
- Read [`references/patterns.md`](references/patterns.md) when the user wants a
  complete, working configuration for a scenario.
- Read [`references/gotchas.md`](references/gotchas.md) when the container
  fails to compile or a service is missing and the cause is not above.

## See also

- `symfony-mcp-bundle`: an MCP server inside the application, and `mcp.clients`.
- `symfony-ai-agent`: the agent framework the bundle configures.
- `symfony-ai-platform`, `symfony-ai-store`, `symfony-ai-chat`: the components
  without the bundle.
