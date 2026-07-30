---
name: agent
description: Use when building autonomous AI agents that call tools, hold memory, orchestrate sub-agents, or process input/output through a typed pipeline. Triggers on `Agent`, `#[AsTool]`, `MemoryInputProcessor`, `MultiAgent`, `SpeechAgent`, `InputProcessor`, `OutputProcessor`, `Toolbox`, `AgentProcessor`. Do NOT trigger for raw LLM invocation (use `platform`) or a vector DB (use `store`).
license: MIT
metadata:
  author: MadCat34
  email: madcat34@gmail.com
  url: https://github.com/MadCat34
  version: "0.2.0"
---

# Agent

> ⚠️ **Symfony AI is experimental** : APIs may break between releases. Always check `UPGRADE.md` in the [symfony/ai monorepo](https://github.com/symfony/ai) before upgrading.

The high-level framework for building AI agents on top of `symfony/ai-platform`. An `Agent` is a `PlatformInterface` wrapped with a typed input/output processor pipeline, an optional tool-calling loop, optional memory hydration, and (on top) a `MultiAgent` router or a `SpeechAgent` wrapper.

## When to use Agent vs raw Platform

Use **Agent** when you want one or more of:

- An automatic tool-calling loop driven by the LLM (the model invokes tools until it stops).

- Your own services exposed as tools via `#[AsTool]` on the class.

- Memory retrieved before each call (`MemoryInputProcessor` + providers).

- Sub-agent routing (`MultiAgent`) or audio + chat composition (`SpeechAgent`).

Use **raw Platform** when you want a one-shot completion, full manual control over a tool loop, or access to provider-specific features not yet abstracted by Agent.

## Installation

```bash
composer require symfony/ai-agent
composer require symfony/ai-platform
composer require symfony/ai-open-ai-platform
# OPENAI_API_KEY=sk-...
```text

## Architecture

```text
User input (string|MessageBag|UserMessage)
   |
   v
InputProcessor[] (registration order)

   - SystemPromptInputProcessor, MemoryInputProcessor,
     ModelOverrideInputProcessor, AgentProcessor (tools), ...
   |
   v
PlatformInterface::invoke(model, messages, options)
   |
   v
OutputProcessor[] (registration order)

   - AgentProcessor (tool-calling loop, max 50 iterations)

   - any other OutputProcessor
   |
   v
ResultInterface
```text

The processor pipeline mutates a typed `Input` container before the platform call, then mutates an `Output` container after the platform call. There is no global "tool wiring" parameter on `Agent` : tools enter the pipeline through an `AgentProcessor` that is registered as both an input and an output processor (see [Quick reference](#quick-reference-tool-calling-agent) below).

## Quick reference: tool-calling agent

This compiles against `src/agent/`. Tools are objects decorated with `#[AsTool]` on the **class**, the `Toolbox` is wrapped in an `AgentProcessor`, and the processor is registered in **both** the input and output processor lists:

```php
use Symfony\AI\Agent\Agent;
use Symfony\AI\Agent\Toolbox\AgentProcessor;
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
$toolProcessor = new AgentProcessor($toolbox);

$agent = new Agent($platform, 'gpt-4o-mini',
    [$toolProcessor],   // inputProcessors
    [$toolProcessor],   // outputProcessors
);

$result = $agent->call("What's the weather in Paris?");
echo $result->getContent();
```

Notes:

- `#[AsTool]` is `TARGET_CLASS | IS_REPEATABLE`. Place it on the class, not on a method. The default method is `__invoke`.

- `new Toolbox([new WeatherService()])` : the constructor takes an iterable of services, **not** variadic services.

- `Agent::call()` accepts `string|MessageBag|UserMessage`.

## Key gotchas

- **`Agent::__construct` has no `$toolboxes` parameter.** Tools are wired through an `AgentProcessor` placed in both the input and output processor lists. Passing the toolbox directly to the third constructor argument will fail with a type error.

- **`Toolbox` is not variadic.** The constructor is `(iterable $tools, ...)`. Pass `[new WeatherService()]` : an array, not a splat.

- **`#[AsTool]` is class-targeted, not method-targeted.** Put it on the class; the positional args are `(string $name, string $description, string $method = '__invoke', array $metadata = [])`. For multiple methods on the same class, repeat the attribute.

- **Processors run in registration order for BOTH input and output.** The previous "output processors in reverse order" guidance is wrong : see `src/Agent.php`.

- **`Memory` is read-only retrieval.** `MemoryProviderInterface::load(Input)` returns `list<Memory>`; it never writes. `StaticMemoryProvider` ships pre-seeded; "my name is Alice then ask" only works if you pre-seed the array.

See `references/gotchas.md` for the full list (processor order, idempotence, recursion depth, `FaultTolerantToolbox` semantics, etc.).

## Common tasks

| Task                               | Building blocks                                                               |
| ---------------------------------- | ----------------------------------------------------------------------------- |
| Tool-calling agent                 | `Toolbox([services])` + `AgentProcessor` in input and output lists            |
| Tool idempotence / fault tolerance | `FaultTolerantToolbox` wraps a `Toolbox` (converts errors to `ToolResult`)    |
| Static memory (pre-seeded)         | `StaticMemoryProvider(['Alice likes pizza'])` + `MemoryInputProcessor`        |
| Embedding-based memory             | `EmbeddingProvider($platform, $model, $vectorStore)` + `MemoryInputProcessor` |
| Multi-agent routing                | `MultiAgent($orchestrator, [Handoff, ...], $fallback)`                        |
| Speech + chat                      | `SpeechAgent($agent, SpeechConfiguration, $stt, $tts)`                        |

## References

- **Full API surface** (namespaces, classes, methods, exceptions): [references/api.md](references/api.md)

- **Patterns** (5 copy-paste recipes): [references/patterns.md](references/patterns.md)

- **Gotchas** (10 common mistakes): [references/gotchas.md](references/gotchas.md)

- **Validation**: run `bash scripts/check-snippets.sh` to lint every PHP code block.

## See also

- `platform` skill : for raw LLM invocation (Agent wraps it).

- `store` skill : for vector storage used by `EmbeddingProvider`.

- `chat` skill : for stateful chat sessions wrapping an Agent.
