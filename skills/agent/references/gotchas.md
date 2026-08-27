# Agent : Gotchas

Cross-checked against `src/agent/src/`. The top 5 are in `SKILL.md`; this is the rest.

## 1. Tools are wired via the `toolbox` named argument, not `$inputProcessors`/`$outputProcessors`

Read `src/Agent.php` : the signature is `(PlatformInterface $platform, string $model, iterable $inputProcessors = [], iterable $outputProcessors = [], string $name = 'agent', ?ToolboxInterface $toolbox = null, ?ToolExecutorInterface $toolExecutor = null, ?int $maxToolCalls = 50, bool $excludeToolMessages = false, bool $includeSources = false, ?EventDispatcherInterface $eventDispatcher = null)`. `toolbox` is the 6th parameter, so pass it by name; the agent drives the tool-calling loop itself instead of wiring it through a processor.

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

`src/Toolbox/Attribute/AsTool.php`: `#[\Attribute(\Attribute::TARGET_CLASS | \Attribute::IS_REPEATABLE)]`. The constructor is `(string $name, string $description, string $method = '__invoke', array $metadata = [])`. For multiple methods on the same class, **repeat the attribute** on the class.

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

If you want the agent to "remember" a turn, you must write that turn into your backing storage yourself (typically by adding a custom output processor in your application code) and read it back through `EmbeddingProvider` or your own `MemoryProviderInterface` implementation.

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

`src/Agent.php`: the default is `50` (`?int $maxToolCalls = 50`). Past that, `MaxIterationsExceededException` is thrown. Set `maxToolCalls: null` to disable the guard. `Agent` also accepts `excludeToolMessages` (don't add tool/assistant messages back to the bag) and `includeSources` (collect `Source` objects from tool results that implement `HasSourcesInterface`) as constructor arguments alongside `toolbox`.

## 9. `ToolException` (config) ≠ `ToolExecutionExceptionInterface` (runtime)

`ToolException` (`src/Toolbox/Exception/ToolException.php`) extends `InvalidArgumentException` : it is raised during tool **metadata extraction** (e.g. missing `#[AsTool]` attribute, invalid reference). `ToolExecutionExceptionInterface` (`src/Toolbox/Exception/ToolExecutionExceptionInterface.php`) is the runtime contract for failures inside tool bodies. `Toolbox::execute()` wraps any `Throwable` from a tool body in `ToolExecutionException`. `FaultTolerantToolbox` only catches the runtime interface : config errors still propagate.

## 10. `SpeechAgent` requires the wrapped agent to exist

`src/SpeechAgent.php`: the first constructor argument is the wrapped `AgentInterface` (chat). The STT and TTS platforms are optional but the speech configuration has no effect without them. If you pass neither, `SpeechAgent` is just a passthrough wrapper.

## 11. `EmbeddingProvider` needs a `Model`, not a string

`src/Memory/EmbeddingProvider.php`: `__construct(PlatformInterface $platform, Model $model, StoreInterface $vectorStore)`. The `$model` argument is `Symfony\AI\Platform\Model` : instantiate with `new Model('text-embedding-3-small')`. Passing the model name as a plain string is a type error.

## 12. Lifecycle and streaming boundaries

- **Use one dispatcher for the whole lifecycle.** Passing different `EventDispatcherInterface` instances to `Toolbox` and `Agent` splits request/resolution/success/failure events from the batch event. Pass the same instance to both.
- **Do not validate typed arguments in `ToolCallRequested`.** That event fires before `ToolCallArgumentResolverInterface::resolveArguments()` runs. Validate denormalized arguments in `ToolCallArgumentsResolved`, whose `getArguments()` contains the resolved array.
- **Exhaust streams before reading final metadata.** `Agent` attaches a `StreamListener` internally when tool calling is active; source collections and result metadata can be updated while tool calls are consumed. Do not assume the `sources` metadata entry is final before stream exhaustion.
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

Symfony AI is experimental and BC breaks are possible; re-check `UPGRADE.md` when changing versions.
