---
name: symfony-ai-agent
description: 'Use when building an AI agent with Symfony AI Agent: letting an LLM call PHP services as tools, running the tool-calling loop, injecting memory, routing tasks between sub-agents, or adding speech, even when the question does not name Symfony or PHP. Triggers on `Agent`, `Toolbox`, `#[AsTool]` without the bundle, `ChainToolbox`, `McpToolbox`, `MultiAgent`. Not for one-shot LLM calls (`symfony-ai-platform`), persisted conversations (`symfony-ai-chat`) or `ai.yaml` (`symfony-ai-bundle`).'
license: MIT
metadata:
  author: Romain Bastide <madcat34@gmail.com>
  url: https://github.com/MadCat34
  version: 0.14.1
  tags: symfony, php, ai, agent, tool-calling, function-calling, memory, multi-agent, mcp
---

# Symfony AI Agent

## Purpose

The agent framework on top of `symfony/ai-platform`. An `Agent` wraps a
`PlatformInterface` with a typed input/output processor pipeline, an optional
tool-calling loop, optional memory, and, on top, a `MultiAgent` router or a
`SpeechAgent` wrapper.

## When to use

- The LLM must call PHP code as tools, in a loop, until it has an answer.
- Services exposed as tools with `#[AsTool]` on the class, in plain PHP.
- Memory injected before each call (`MemoryInputProcessor` + providers).
- Routing between specialised sub-agents (`MultiAgent`) or speech in and out (`SpeechAgent`).
- Tools from a remote MCP server handed to an agent without the bundle (`McpToolbox`).

## When not to use

- A one-shot completion, or a tool loop driven by hand: use `symfony-ai-platform`.
- Conversation history that survives between HTTP requests: use `symfony-ai-chat`
  (it wraps an `Agent`); agent memory is read-only retrieval, not history.
- Agents, tools and processors declared in `config/packages/ai.yaml`: use `symfony-ai-bundle`.
- Storing the documents behind embedding memory: use `symfony-ai-store`.

## Prerequisites

PHP 8.2+, the agent and platform packages, a bridge, and its API key:

```bash
composer require symfony/ai-agent symfony/ai-platform
composer require symfony/ai-open-ai-platform
# OPENAI_API_KEY=sk-...
```

## Examples

A tool-calling agent. Tools are objects with `#[AsTool]` on the **class**; the
`Toolbox` goes to `Agent` through the named `toolbox` argument:

```php
use Symfony\AI\Agent\Agent;
use Symfony\AI\Agent\Toolbox\Toolbox;
use Symfony\AI\Agent\Toolbox\Attribute\AsTool;
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;

#[AsTool('get_weather', 'Get the current weather for a city.')]
final class WeatherService
{
    public function __invoke(string $city): string
    {
        return sprintf('Weather in %s: sunny, 22C', $city);
    }
}

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);
$toolbox = new Toolbox([new WeatherService()]);

$agent = new Agent($platform, 'gpt-4o-mini', toolbox: $toolbox);

$result = $agent->call("What's the weather in Paris?");
echo $result->getContent();
```

`Agent::call()` accepts `string|MessageBag|UserMessage` and returns a lazy
`Execution`.

## Architecture

```text
User input (string|MessageBag|UserMessage)
   |
   v
InputProcessor[] (registration order)
   - SystemPromptInputProcessor, MemoryInputProcessor,
     ModelOverrideInputProcessor, ...
   |
   v
PlatformInterface::invoke(model, messages, options)
   |
   v
Tool-calling loop (if a `toolbox` was passed to Agent, max 50 iterations)
   |
   v
OutputProcessor[] (registration order)
   |
   v
Execution (lazy — drives the run only when consumed)
```

The processors mutate a typed `Input` before the platform call and an `Output`
after it. Tool calling is **not** a processor: `Agent` runs its own loop once a
`toolbox` is passed. Nothing runs until the `Execution` is consumed
(`->getContent()`, `->getResult()`, or a `foreach`).

## Key gotchas

- **`Toolbox` is not variadic.** The constructor is `(iterable $tools, ...)`:
  pass `[new WeatherService()]`, an array, not a splat.
- **`#[AsTool]` targets the class, not a method.** Positional arguments are
  `(string $name, string $description, string $method = '__invoke', array $metadata = [])`;
  repeat the attribute to expose several methods of one class.
- **Processors run in registration order, for input and output alike.**
- **Memory is read-only retrieval.** `MemoryProviderInterface::load(Input)`
  returns `list<Memory>` and never writes. `StaticMemoryProvider` only knows
  what it was seeded with: "my name is Alice", said in an earlier turn, is not
  remembered.
- **An `Execution` is single-use and lazy.** Keep the result after consuming it;
  call the agent again for a new run.

## Troubleshooting

| Error | Cause | Fix |
| --- | --- | --- |
| `Agent::__construct(): Argument #3 ($inputProcessors) must be of type …, Toolbox given` (`TypeError`) | The toolbox was passed positionally, into the input-processor slot. | `new Agent($platform, $model, toolbox: $toolbox)`. |
| `The class "…" is not a tool, please add Symfony\AI\Agent\Toolbox\Attribute\AsTool attribute.` | A service in the `Toolbox` has no `#[AsTool]`. | Add `#[AsTool(name, description)]` on the class. |
| `Method "…" not found in tool "…".` | `#[AsTool(method: …)]` names a method the class does not have. | Fix the method name; the default is `__invoke`. |
| `Maximum number of tool calling iterations (50) exceeded.` (`MaxIterationsExceededException`) | The model keeps calling tools without concluding. | Make tool results conclusive or the prompt clearer; raise `maxToolCalls` only if the task needs it. |
| `Tool "…" is offered by more than one toolbox …` (`ToolConfigurationException`) | Two toolboxes in a `ChainToolbox` expose the same tool name. | Rename one of the tools; names must be unique across the chain. |
| `The agent execution was canceled.` (`RuntimeException`) | The `Execution` was consumed after `cancel()`. | Stop consuming a cancelled execution. |
| `The execution was already consumed. Call the agent again for a new execution.` (`LogicException`) | The same `Execution` was iterated twice. | Keep the first result, or call the agent again. |

## Limitations

- The component is experimental: APIs change between minor versions. Pin
  `symfony/ai-agent` and read `UPGRADE.md` in the monorepo before upgrading.
- The tool loop stops after `maxToolCalls` iterations (50 by default).
- Memory providers only read; persisting a conversation is `symfony-ai-chat`'s job.
- A `MultiAgent` routes each request to one handoff target; it does not run
  sub-agents in parallel.

## Usage

Pick the building blocks for the task, then pass them to `Agent` (named
arguments for `toolbox:` and `toolExecutor:`).

| Task                               | Building blocks                                                               |
| ---------------------------------- | ----------------------------------------------------------------------------- |
| Tool-calling agent                 | `Toolbox([services])` passed as `Agent`'s `toolbox` argument                  |
| Tool idempotence / fault tolerance | `FaultTolerantToolbox` wraps a `Toolbox` (converts errors to `ToolResult`)    |
| Static memory (pre-seeded)         | `StaticMemoryProvider(['Alice likes pizza'])` + `MemoryInputProcessor`        |
| Embedding-based memory             | `EmbeddingProvider($platform, $model, $vectorStore)` + `MemoryInputProcessor` |
| Multi-agent routing                | `MultiAgent($orchestrator, [Handoff, ...], $fallback)`                        |
| Speech + chat                      | `SpeechAgent($agent, SpeechConfiguration, $stt, $tts)`                        |
| Concurrent I/O-bound tool calls    | `toolExecutor: new FiberToolExecutor($toolbox)` + `SuspendableTrait` in tools |
| Tools from several toolboxes       | `ChainToolbox([$localToolbox, $mcpToolbox])` (duplicate names throw)          |
| DTO as the tool's argument schema  | `__invoke(#[MapToolArguments] MyDto $dto)`                                    |
| Stop a running agent               | `$execution->cancel()` (then consuming it throws `RuntimeException`)          |

## References

- Read [`references/api-reference.md`](references/api-reference.md) when the
  user needs exact signatures: `Agent`, `Execution`, processors, `Toolbox`,
  tool executors, `#[AsTool]`, memory providers, `MultiAgent`, `McpToolbox`.
- Read [`references/patterns.md`](references/patterns.md) when the user wants
  runnable code: tools, memory, fault tolerance, multi-agent, speech.
- Read [`references/gotchas.md`](references/gotchas.md) when an agent
  misbehaves and the cause is not above: processor order, idempotence,
  recursion depth, `FaultTolerantToolbox` semantics.

## See also

- `symfony-ai-platform`: raw LLM invocation, which `Agent` wraps.
- `symfony-ai-chat`: a persisted conversation wrapping an `Agent`.
- `symfony-ai-store`: the vector store behind `EmbeddingProvider`.
- `symfony-ai-bundle`: agents, tools and processors declared in `ai.yaml`.
