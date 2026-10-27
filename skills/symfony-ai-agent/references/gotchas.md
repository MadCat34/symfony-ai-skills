# Agent : Gotchas

Cross-checked against `src/agent/src/`. The top 5 are in `SKILL.md`; this is the rest.

## Contents

- 1. Tools are wired via the `toolbox` named argument, not `$inputProcessors`/`$outputProcessors`
- 2. `Toolbox` is not variadic : `iterable` only
- 3. `#[AsTool]` is class-targeted, not method-targeted
- 4. `Memory` is read-only retrieval; no `save()` API
- 5. `FaultTolerantToolbox` does NOT retry or open a circuit
- 6. `MultiAgent` requires orchestrator + handoffs + fallback
- 7. Processors run in registration order (NOT reverse for output)
- 8. `Agent`'s `maxToolCalls` guards the tool-calling loop
- 9. `ToolException` (config) ≠ `ToolExecutionExceptionInterface` (runtime)
- 10. `SpeechAgent` requires the wrapped agent to exist
- 11. `EmbeddingProvider` needs a `Model`, not a string
- 12. Lifecycle, `Execution` laziness, and streaming boundaries
- 13. `tools` is a per-call option, not just a construction-time toolbox
- 14. `use_memory: false` disables memory for one call
- 15. The agent no longer changes the caller's `MessageBag`
- 16. Input processors must replace the bag, `add()` is gone
- 17. The conversation is the bag id, messages are matched by message id
- 18. A stored conversation is saved in three steps
- 19. `excludeToolMessages` is gone and the arguments after it moved

## 1. Tools are wired via the `toolbox` named argument, not `$inputProcessors`/`$outputProcessors`

Read `src/Agent.php` : the signature is `(PlatformInterface $platform, string $model, iterable $inputProcessors = [], iterable $outputProcessors = [], string $name = 'agent', ?ToolboxInterface $toolbox = null, ?ToolExecutorInterface $toolExecutor = null, ?int $maxToolCalls = 50, bool $includeSources = false, ?EventDispatcherInterface $eventDispatcher = null, ToolResultConverter $toolResultConverter = new ToolResultConverter(), ?MessageStoreInterface $messageStore = null)`. `toolbox` is the 6th parameter, so pass it by name; the agent drives the tool-calling loop itself instead of wiring it through a processor.

```php
// WRONG — TypeError, third positional argument is $inputProcessors, not a toolbox
$agent = new Agent($platform, 'gpt-4o-mini', [$toolbox]);

// CORRECT
$agent = new Agent($platform, 'gpt-4o-mini', toolbox: $toolbox);
```

## 2. `Toolbox` is not variadic : `iterable` only

`src/Toolbox/Toolbox.php`: `__construct(iterable $tools, ToolFactoryInterface $toolFactory = new ReflectionToolFactory(), ToolCallArgumentResolverInterface $argumentResolver = new ToolCallArgumentResolver(), LoggerInterface $logger = new NullLogger(), ?EventDispatcherInterface $eventDispatcher = null)`.

```php
// WRONG — variadic splat, not the constructor signature
$toolbox = new Toolbox(new WeatherService());

// CORRECT — pass an iterable (array works)
$toolbox = new Toolbox([new WeatherService()]);
```

## 3. `#[AsTool]` is class-targeted, not method-targeted

`src/Toolbox/Attribute/AsTool.php`: `#[\Attribute(\Attribute::TARGET_CLASS | \Attribute::IS_REPEATABLE)]`. The constructor is `(string $name, string $description, string $method = '__invoke', array $metadata = [], ToolEffectHints $effectHints = new ToolEffectHints())`. For multiple methods on the same class, **repeat the attribute** on the class.

```text
// WRONG — placing the attribute on the method
public function getWeather(string $city): string
{
    #[AsTool('get_weather', 'Get current weather.')]
    return ...;
}

// CORRECT — repeat the attribute on the class
#[AsTool('get_weather', 'Get the current weather.', method: 'getWeather')]
final class WeatherService
{
    public function getWeather(string $city): string { ... }
}
```

## 4. `Memory` is read-only retrieval; no `save()` API

`src/Memory/MemoryProviderInterface.php`: the only method is `load(Input): list<Memory>`. There is no `save()` or `append()`. `StaticMemoryProvider` is **pre-seeded** via its constructor and immutable at runtime.

For the agent to remember earlier turns of the conversation, pass a `messageStore` (gotcha 17): that is history, replayed in full. Memory is for facts injected into the system prompt; to build it from past turns, write them into a vector store yourself and read them back through `EmbeddingProvider` or your own `MemoryProviderInterface`.

## 5. `FaultTolerantToolbox` does NOT retry or open a circuit

`src/Toolbox/FaultTolerantToolbox.php`: the constructor takes only `(ToolboxInterface $innerToolbox)`. It catches `ToolExecutionExceptionInterface` and returns a `ToolResult` carrying the exception's `getToolCallResult()` message. It catches `ToolNotFoundException` and returns a `ToolResult` containing the valid tool names.

If you need retries or circuit-breaker behaviour, build your own decorator on top of `ToolboxInterface`.

```php
// The real constructor
final class FaultTolerantToolbox implements ToolboxInterface
{
    public function __construct(private readonly ToolboxInterface $innerToolbox) {}
}
```

## 6. `MultiAgent` requires orchestrator + handoffs + fallback

`src/MultiAgent/MultiAgent.php`: the constructor is `(AgentInterface $orchestrator, array $handoffs, AgentInterface $fallback, string $name = 'multi-agent', LoggerInterface $logger = new NullLogger())`. There is no `setClassifierAgent()` : the orchestrator IS the classifier. The handoff list must not be empty (`InvalidArgumentException` otherwise).

```php
// CORRECT — orchestrator (used to pick), handoffs (targets), fallback (when nothing matches)
$router = new MultiAgent($orchestrator, [new Handoff($target, ['when', 'keywords'])], $fallback);
```

## 7. Processors run in registration order (NOT reverse for output)

`src/Agent.php` iterates `$this->outputProcessors` in `foreach` order : the same as for input processors. There is no reverse-order semantics. The previous "output processors in reverse order" guidance in older docs is wrong.

## 8. `Agent`'s `maxToolCalls` guards the tool-calling loop

`src/Agent.php`: the default is `50` (`?int $maxToolCalls = 50`). Past that, `MaxIterationsExceededException` is thrown. Set `maxToolCalls: null` to disable the guard. `Agent` also accepts `includeSources` (collect `Source` objects from tool results that implement `HasSourcesInterface`) as a constructor argument alongside `toolbox`.

## 9. `ToolException` (config) ≠ `ToolExecutionExceptionInterface` (runtime)

`ToolException` (`src/Toolbox/Exception/ToolException.php`) extends `InvalidArgumentException` : it is raised during tool **metadata extraction** (e.g. missing `#[AsTool]` attribute, invalid reference). `ToolExecutionExceptionInterface` (`src/Toolbox/Exception/ToolExecutionExceptionInterface.php`) is the runtime contract for failures inside tool bodies. `Toolbox::execute()` wraps any `Throwable` from a tool body in `ToolExecutionException`. `FaultTolerantToolbox` only catches the runtime interface : config errors still propagate.

Argument resolution failures (missing mandatory parameter, value that cannot be denormalized) throw `InvalidToolCallArgumentsException` since 0.14 : a runtime `ToolExecutionExceptionInterface`, no longer a `ToolException`. A `catch (ToolException)` written for 0.13 around `ToolCallArgumentResolver` no longer fires.

## 10. `SpeechAgent` requires the wrapped agent to exist

`src/SpeechAgent.php`: the first constructor argument is the wrapped `AgentInterface` (chat). The STT and TTS platforms are optional but the speech configuration has no effect without them. If you pass neither, `SpeechAgent` is just a passthrough wrapper.

## 11. `EmbeddingProvider` needs a `Model`, not a string

`src/Memory/EmbeddingProvider.php`: `__construct(PlatformInterface $platform, Model $model, StoreInterface $vectorStore)`. The `$model` argument is `Symfony\AI\Platform\Model` : instantiate with `new Model('text-embedding-3-small')`. Passing the model name as a plain string is a type error.

## 12. Lifecycle, `Execution` laziness, and streaming boundaries

- **`Agent::call()` does not run the agent.** It returns a lazy `Execution` (`src/Execution/Execution.php`) : nothing happens until you consume it via `getContent()`, `getResult()`, a `foreach`, or `onProgress()`/`onResult()` callbacks. Side effects and exceptions therefore surface at the consumption point, not on the `call()` line. There is no more `Toolbox\StreamListener` : `Execution` handles streaming and observation natively.
- **`instanceof` checks need `->getResult()` first.** `Execution` is not the typed result itself; `$agent->call($input) instanceof TextResult` is always false. Call `->getResult()` (or `->getContent()`) before type-checking.
- **An `Execution` cannot be re-iterated.** It caches its final result once consumed, but consuming it a second time (a second `foreach`, or calling `getResult()` after the generator was already drained by iteration) throws `LogicException`. Call the agent again for a fresh execution.
- **Exhaust streams before reading final metadata.** With `['stream' => true]`, `getContent()`/`asStream()` yield deltas as they arrive; source collections and result metadata (via `getMetadata()`) are populated progressively while they are consumed. Do not assume the `sources` metadata entry is final before stream exhaustion.
- **Input processors now run once per `Agent::call()`, not once per tool-calling round.** The loop no longer recurses through `call()`, so output processors only ever see the final, fully assembled result.
- **A tool-calling round adds one assistant message per turn.** Text, thinking blocks, and tool calls are appended together as a single `AssistantMessage`, not split across several. Code asserting on the shape of `getMessages()` or of a stored conversation needs to account for this.
- **Use one dispatcher for the whole lifecycle.** Passing different `EventDispatcherInterface` instances to `Toolbox` and `Agent` splits request/resolution/success/failure events from the batch event. Pass the same instance to both.
- **Do not validate typed arguments in `ToolCallRequested`.** That event fires before `ToolCallArgumentResolverInterface::resolveArguments()` runs. Validate denormalized arguments in `ToolCallArgumentsResolved`, whose `getArguments()` contains the resolved array.
- **Provenance is not citation.** `Source` and `SourceCollection` preserve tool-reported metadata. They do not prove phrase-level attribution or that the source or generated claim is true.
- **`maxToolCalls` is constructor-only.** It bounds `Agent`'s internal tool-calling loop, not an individual `Agent::call()` option. Configure it when constructing the agent, for example `new Agent($platform, $model, toolbox: $toolbox, maxToolCalls: 8)`; use `null` to disable the guard.

## 13. `tools` is a per-call option, not just a construction-time toolbox

`src/Execution/Runner.php` (`exposeTools()`): passing `['tools' => ['tavily_search']]` as the second argument of `Agent::call()` restricts, for that one call only, which tools from the constructed `toolbox` are exposed to the model — the filter only applies when the option is a flat array of strings (tool names); anything else leaves the full toolbox exposed. This does not remove tools from the `Toolbox` itself, just from what that call advertises to the platform.

```php
// Only "tavily_search" is exposed to the model for this call; the rest of the
// toolbox is untouched and still available on the next call.
$agent->call($input, ['tools' => ['tavily_search']]);
```

## 14. `use_memory: false` disables memory for one call

`MemoryInputProcessor::processInput()` reads `$input->getOptions()['use_memory']`, removes it from the options bag, and short-circuits to `return` when the value is `false` (or when no providers are registered). Pass `['use_memory' => false]` from your caller to disable memory for a specific call without changing the agent's processor list.

## 15. The agent no longer changes the caller's `MessageBag`

Since 1.0 the system prompt, the memory and the messages of the tool loop stay out of the bag passed to `call()`; the loop runs on its own copy. Code that kept appending to one bag and expected the answer to show up in it now resends the same question:

```php
// 0.x: $agent->call($messages); $messages->add(Message::ofAssistant($execution->getResult()));
$messages = $agent->call($messages)->getMessages();         // given messages + tool round + answer, same bag id
$messages = $messages->with(Message::ofUser('And in Tokyo?'));
```

`$messages->with(Message::ofAssistant($execution->getResult()))` also works but drops the tool calls and their results.

## 16. Input processors must replace the bag, `add()` is gone

`MessageBag` is immutable (`symfony-ai-platform`): `add()`, `prepend()` and `removeSystemMessage()` no longer exist. A processor builds a new bag and sets it on the `Input`:

```php
$input->setMessageBag($input->getMessageBag()->with($message));
$input->setMessageBag($input->getMessageBag()->withSystemMessage(Message::forSystem('…')));
```

`withSystemMessage()` replaces **every** system message of the bag, where `prepend()` added one in front of the others. `SystemPromptInputProcessor` still skips its prompt when the bag already holds a system message.

## 17. The conversation is the bag id, messages are matched by message id

With a `messageStore`, `call()` loads the conversation stored under `$bag->getId()`. A `string` or `UserMessage` input is wrapped in a **new** bag with a fresh id, so every such call starts a new conversation: pass `MessageBag::forId($conversationId, 'Hello')` instead (the id must be time-based: `Uuid::v7()`, a `Ulid`).

The agent appends the given messages whose **message** id it does not know yet. Passing the whole conversation again or only the new message is therefore the same, but a message rebuilt from its text (`Message::ofUser($text)` on each request) gets a new id and is stored a second time. The id comes straight from the caller: check that the current user owns the conversation before calling the agent with it.

## 18. A stored conversation is saved in three steps

`Agent::call()` saves after adding the input, after each round of tool calls and with the answer, so a failed run keeps its tool results. Consequences:

- A run that throws, is cancelled, or whose stream is abandoned before the end still has its user message (and finished tool rounds) stored, without an answer. The next call sends that dangling question to the model again.
- With `['stream' => true]`, the answer is saved only once the stream is drained: `break` out of the loop and it is lost.
- A concurrent request that saved the same conversation in the meantime makes the next save throw `ConflictException`; retry the turn or lock per conversation id. Whether the check is atomic depends on the bridge (`references/bridges.md`).
- The system prompt and memory are added again on every call and never stored, so changing the system prompt applies to existing conversations.

## 19. `excludeToolMessages` is gone and the arguments after it moved

1.0 removed the `bool $excludeToolMessages` argument (and the bundle's `exclude_tool_messages` option): tool messages never reach the caller's bag. `includeSources`, `eventDispatcher` and the following arguments moved up one slot, so a positional call written for 0.15 now passes a boolean into `includeSources` and the event dispatcher into `toolResultConverter`. Pass them by name:

```php
new Agent($platform, 'gpt-5', toolbox: $toolbox, includeSources: true);
```

Symfony AI is experimental and BC breaks are possible; re-check `UPGRADE.md` when changing versions.
