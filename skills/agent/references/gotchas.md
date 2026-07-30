# Agent : Gotchas

Cross-checked against `src/agent/src/`. The top 5 are in `SKILL.md`; this is the rest.

## 1. `Agent::__construct` has no `$toolboxes` parameter

Read `src/Agent.php` : the signature is `(PlatformInterface $platform, string $model, iterable $inputProcessors = [], iterable $outputProcessors = [], string $name = 'agent')`. Tools are wired through an `AgentProcessor` placed in both the input and output processor lists.

```php
// WRONG — TypeError, Agent has no third argument for toolboxes
$agent = new Agent($platform, 'gpt-4o-mini', [$toolbox]);

// CORRECT
$toolProcessor = new AgentProcessor($toolbox);
$agent = new Agent($platform, 'gpt-4o-mini', [$toolProcessor], [$toolProcessor]);
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

```php
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

## 8. `AgentProcessor::$maxToolCalls` guards the loop

`src/Toolbox/AgentProcessor.php`: the default is `50`. Past that, `MaxIterationsExceededException` is thrown. Set `maxToolCalls: null` to disable the guard. The processor also accepts `excludeToolMessages` (don't add tool/assistant messages back to the bag) and `includeSources` (collect `Source` objects from tool results that implement `HasSourcesInterface`).

## 9. `ToolException` (config) ≠ `ToolExecutionExceptionInterface` (runtime)

`ToolException` (`src/Toolbox/Exception/ToolException.php`) extends `InvalidArgumentException` : it is raised during tool **metadata extraction** (e.g. missing `#[AsTool]` attribute, invalid reference). `ToolExecutionExceptionInterface` (`src/Toolbox/Exception/ToolExecutionExceptionInterface.php`) is the runtime contract for failures inside tool bodies. `Toolbox::execute()` wraps any `Throwable` from a tool body in `ToolExecutionException`. `FaultTolerantToolbox` only catches the runtime interface : config errors still propagate.

## 10. `SpeechAgent` requires the wrapped agent to exist

`src/SpeechAgent.php`: the first constructor argument is the wrapped `AgentInterface` (chat). The STT and TTS platforms are optional but the speech configuration has no effect without them. If you pass neither, `SpeechAgent` is just a passthrough wrapper.

## 11. `EmbeddingProvider` needs a `Model`, not a string

`src/Memory/EmbeddingProvider.php`: `__construct(PlatformInterface $platform, Model $model, StoreInterface $vectorStore)`. The `$model` argument is `Symfony\AI\Platform\Model` : instantiate with `new Model('text-embedding-3-small')`. Passing the model name as a plain string is a type error.

## 12. Lifecycle and streaming boundaries

- **Use one dispatcher for the whole lifecycle.** Passing different `EventDispatcherInterface` instances to `Toolbox` and `AgentProcessor` splits request/resolution/success/failure events from the batch event. Pass the same instance to both.
- **Do not validate typed arguments in `ToolCallRequested`.** That event fires before `ToolCallArgumentResolverInterface::resolveArguments()` runs. Validate denormalized arguments in `ToolCallArgumentsResolved`, whose `getArguments()` contains the resolved array.
- **Exhaust streams before reading final metadata.** `AgentProcessor` attaches a `StreamListener`; source collections and result metadata can be updated while tool calls are consumed. Do not assume the `sources` metadata entry is final before stream exhaustion.
- **Provenance is not citation.** `Source` and `SourceCollection` preserve tool-reported metadata. They do not prove phrase-level attribution or that the source or generated claim is true.
- **`maxToolCalls` is constructor-only.** It bounds the processor loop, not an individual `Agent::call()` option. Configure it when constructing the processor, for example `new AgentProcessor($toolbox, maxToolCalls: 8)`; use `null` to disable the guard.

Symfony AI is experimental and BC breaks are possible; re-check `UPGRADE.md` when changing versions.

The processor reads `$input->getOptions()['use_memory']`, removes it from the options bag, and short-circuits to `return` when the value is `false` (or when no providers are registered). Pass `['use_memory' => false]` from your caller to disable memory for a specific call without changing the agent's processor list.
