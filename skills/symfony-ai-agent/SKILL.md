---
name: symfony-ai-agent
description: 'Use when building an AI agent with Symfony AI Agent: letting an LLM call PHP services as tools, running the tool-calling loop, keeping a chatbot conversation across HTTP requests, injecting memory or routing between sub-agents, even when the question does not name Symfony or PHP. Triggers on `Agent`, `Toolbox`, `#[AsTool]` without the bundle, `MessageStoreInterface`. Not for one-shot LLM calls (`symfony-ai-platform`), vector search (`symfony-ai-store`) or `ai.yaml` (`symfony-ai-bundle`).'
license: MIT
metadata:
  author: Romain Bastide <madcat34@gmail.com>
  url: https://github.com/MadCat34
  version: 1.0.0-BETA1
  tags: symfony, php, ai, agent, tool-calling, function-calling, memory, multi-agent, mcp, chatbot, conversation-history, message-store
---

# Symfony AI Agent

## Purpose

The agent framework on top of `symfony/ai-platform`. An `Agent` wraps a
`PlatformInterface` with a typed input/output processor pipeline, an optional
tool-calling loop, optional memory, an optional message store that keeps each
conversation across requests, and, on top, a `MultiAgent` router or a
`SpeechAgent` wrapper. Since 1.0 it replaces the removed Chat component.

## When to use

- The LLM must call PHP code as tools, in a loop, until it has an answer.
- Services exposed as tools with `#[AsTool]` on the class, in plain PHP.
- A chatbot must remember the conversation between HTTP requests or workers:
  pass a `messageStore` and identify the conversation by the `MessageBag` id.
- The history backend should change per environment (in memory in tests,
  Redis in dev, Doctrine DBAL in prod) without touching call sites.
- Memory injected before each call (`MemoryInputProcessor` + providers).
- Routing between specialised sub-agents (`MultiAgent`) or speech in and out (`SpeechAgent`).
- Tools from a remote MCP server handed to an agent without the bundle (`McpToolbox`).

## When not to use

- A one-shot completion, or a tool loop driven by hand: use `symfony-ai-platform`.
- Retrieving facts or documents by similarity: use `symfony-ai-store`; a
  message store only replays the conversation.
- Agents, tools, processors and message stores declared in
  `config/packages/ai.yaml`: use `symfony-ai-bundle`.
- Code written for `symfony/ai-chat` (`Chat`, `submit()`): the component is gone
  in 1.0, migrate to `Agent` + `messageStore` as shown below.

## Prerequisites

PHP 8.2+, the agent and platform packages, a bridge, and its API key. A
persisted conversation also needs one message-store bridge, named
`symfony/ai-<backend>-message-store`:

```bash
composer require symfony/ai-agent symfony/ai-platform
composer require symfony/ai-open-ai-platform
# OPENAI_API_KEY=sk-...
composer require symfony/ai-redis-message-store   # or doctrine, cache, session, mongo-db, …
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

A conversation kept across requests. The agent loads the stored messages by
the bag id, adds the new ones and saves the answer:

```php
use Symfony\AI\Agent\Agent;
use Symfony\AI\Agent\Bridge\Redis\MessageStore;
use Symfony\AI\Agent\InputProcessor\SystemPromptInputProcessor;
use Symfony\AI\Platform\Message\MessageBag;
use Symfony\Component\Uid\Uuid;

$store = new MessageStore(new \Redis(['host' => 'localhost']), 'conversations');
$agent = new Agent($platform, 'gpt-4o-mini', [
    new SystemPromptInputProcessor('You are a helpful assistant.'),
], messageStore: $store);

$id = Uuid::fromString($conversationIdFromYourApp); // a UUID v7 (time-based)
$agent->call(MessageBag::forId($id, 'My name is Alice.'))->getResult();
echo $agent->call(MessageBag::forId($id, 'What is my name?'))->asText(); // "Alice"
```

`Agent::call()` accepts `string|MessageBag|UserMessage` and returns a lazy
`ExecutionInterface`.

## Architecture

```text
User input (string|MessageBag|UserMessage)
   |
   v
MessageStore::load(bag id) + new messages, saved   (only with messageStore)
   |
   v
InputProcessor[] (registration order, each replaces the immutable bag)
   - SystemPromptInputProcessor, MemoryInputProcessor,
     ModelOverrideInputProcessor, ...
   |
   v
PlatformInterface::invoke(model, messages, options)
   |
   v
Tool-calling loop (if a `toolbox` was passed, max 50 iterations; saved per round)
   |
   v
OutputProcessor[] (registration order)
   |
   v
Execution (lazy) -> answer saved to the store, getMessages() for the new bag
```

Tool calling is **not** a processor: `Agent` runs its own loop once a `toolbox`
is passed. Nothing runs until the `Execution` is consumed (`->getContent()`,
`->getResult()`, `->asText()`, or a `foreach`). The system prompt and memory are
added on every call and never stored.

## Key gotchas

- **`Toolbox` is not variadic.** The constructor is `(iterable $tools, ...)`:
  pass `[new WeatherService()]`, an array, not a splat.
- **`#[AsTool]` targets the class, not a method.** Repeat the attribute to
  expose several methods of one class.
- **The agent never changes the `MessageBag` you pass** (1.0). Continue with
  `$messages = $agent->call($messages)->getMessages()`, or pass a message store.
- **The conversation is the bag id.** A plain string or `UserMessage` input gets
  a fresh bag, hence a new conversation each call: use `MessageBag::forId($id, …)`.
- **Messages are matched by message id.** Passing the whole history or only the
  new message is the same, but a message rebuilt from its text is stored twice.
- **Memory is read-only retrieval**, not history: `MemoryProviderInterface::load(Input)`
  returns `list<Memory>` and never writes; history belongs in a message store.
- **An `Execution` is single-use and lazy.** Breaking out of a stream early
  skips saving the answer (the input and tool rounds are already saved).
- **Match progress stages with `Progress::STAGE_*`**, not raw strings.

## Troubleshooting

| Error | Cause | Fix |
| --- | --- | --- |
| `Agent::__construct(): Argument #3 ($inputProcessors) must be of type …, Toolbox given` (`TypeError`) | The toolbox was passed positionally, into the input-processor slot. | `new Agent($platform, $model, toolbox: $toolbox)`. |
| `The class "…" is not a tool, please add Symfony\AI\Agent\Toolbox\Attribute\AsTool attribute.` | A service in the `Toolbox` has no `#[AsTool]`. | Add `#[AsTool(name, description)]` on the class. |
| `Method "…" not found in tool "…".` | `#[AsTool(method: …)]` names a method the class does not have. | Fix the method name; the default is `__invoke`. |
| `Maximum number of tool calling iterations (50) exceeded.` (`MaxIterationsExceededException`) | The model keeps calling tools without concluding. | Make tool results conclusive or the prompt clearer; raise `maxToolCalls` only if the task needs it. |
| `Tool "…" is offered by more than one toolbox …` (`ToolConfigurationException`) | Two toolboxes in a `ChainToolbox` expose the same tool name. | Rename one of the tools. |
| `The messages "…" were changed in the meantime, load them again before saving.` (`ConflictException`) | Another request saved the same conversation while this run was going. | Retry the turn, or lock per conversation id. |
| `Could not normalize object of type "…", no supporting normalizer found.` (`NotNormalizableValueException`) | Message metadata holds an object the store's serializer cannot normalize, e.g. a `DateTimeImmutable`. | Pass the store a serializer with that normalizer (`references/bridges.md` → *Serializer*). |
| `The agent did not provide the messages of its execution.` (`LogicException`) | `getMessages()` on an execution from a custom agent that yields no messages. | Build the `Update\Result` with its `$messages` argument. |
| `The agent execution was canceled.` (`RuntimeException`) | The `Execution` was consumed after `cancel()`. | Stop consuming a cancelled execution. |
| `The execution was already consumed. Call the agent again for a new execution.` (`LogicException`) | The same `Execution` was iterated twice. | Keep the first result, or call the agent again. |

## Limitations

- The component is experimental: APIs change between minor versions. Pin
  `symfony/ai-agent` and read `UPGRADE.md` in the monorepo before upgrading.
- The tool loop stops after `maxToolCalls` iterations (50 by default).
- Only the Doctrine DBAL, MongoDB, SurrealDB and Redis stores detect a
  concurrent save atomically; the others check then write.
- The store replays the full history on every turn; trimming or summarising
  long conversations is left to the application.
- Message stores do not read conversations saved by `symfony/ai-chat` 0.x.
- A `MultiAgent` routes each request to one handoff target; it does not run
  sub-agents in parallel.

## Usage

Pick the building blocks for the task, then pass them to `Agent` (named
arguments for `toolbox:`, `toolExecutor:` and `messageStore:`).

| Task                               | Building blocks                                                               |
| ---------------------------------- | ----------------------------------------------------------------------------- |
| Tool-calling agent                 | `Toolbox([services])` passed as `Agent`'s `toolbox` argument                  |
| Tool idempotence / fault tolerance | `FaultTolerantToolbox` wraps a `Toolbox` (converts errors to `ToolResult`)    |
| Conversation across requests       | `messageStore: new Bridge\Redis\MessageStore(...)` + `MessageBag::forId($id)` |
| Conversation without a store       | `$messages = $agent->call($messages)->getMessages()`                          |
| Conversation in tests              | `messageStore: new InMemoryMessageStore()`                                    |
| Static memory (pre-seeded)         | `StaticMemoryProvider(['Alice likes pizza'])` + `MemoryInputProcessor`        |
| Embedding-based memory             | `EmbeddingProvider($platform, $model, $vectorStore)` + `MemoryInputProcessor` |
| Multi-agent routing                | `MultiAgent($orchestrator, [Handoff, ...], $fallback)`                        |
| Speech + chat                      | `SpeechAgent($agent, SpeechConfiguration, $stt, $tts)`                        |
| Concurrent I/O-bound tool calls    | `toolExecutor: new FiberToolExecutor($toolbox)` + `SuspendableTrait` in tools |
| Tools from several toolboxes       | `ChainToolbox([$localToolbox, $mcpToolbox])` (duplicate names throw)          |
| RAG tool with cited documents      | `SimilaritySearch($retriever)` + `includeSources: true`                       |
| Stop a running agent               | `$execution->cancel()` (then consuming it throws `RuntimeException`)          |

## References

- Read [`references/api-reference.md`](references/api-reference.md) when the
  user needs exact signatures: `Agent`, `ExecutionInterface`, processors,
  `Toolbox`, tool executors, `#[AsTool]`, memory providers, the message-store
  interfaces, `MultiAgent`.
- Read [`references/bridges.md`](references/bridges.md) when the user picks or
  configures a message store (Redis, Doctrine DBAL, MongoDB, cache, session, …)
  or a ready-made tool (`SimilaritySearch`, `McpToolbox`, Tavily, Filesystem, …).
- Read [`references/patterns.md`](references/patterns.md) when the user wants
  runnable code: tools, persisted conversations, memory, fault tolerance,
  multi-agent, speech, or a migration from `symfony/ai-chat`.
- Read [`references/gotchas.md`](references/gotchas.md) when an agent
  misbehaves and the cause is not above: processor order, the immutable bag,
  conversation ids, store conflicts, recursion depth.

## See also

- `symfony-ai-platform`: raw LLM invocation and `MessageBag`, which `Agent` wraps.
- `symfony-ai-store`: the vector store behind `EmbeddingProvider` and `SimilaritySearch`.
- `symfony-ai-bundle`: agents, tools, processors and message stores declared in `ai.yaml`.
