# Agent : API Reference

Read this when the user asks for the full signature catalogue of the Agent framework. Every signature below is taken verbatim from `src/agent/src/` : re-verify against the source if you change anything.

## Namespace tree

```text
Symfony\AI\Agent\
  Agent                                  (final)
  AgentInterface                         (call, getName)
  AgentAwareInterface + AgentAwareTrait  (setAgent)
  Input                                  (final, mutable)
  Output                                 (final)
  InputNormalizer                        (@internal, static toMessageBag)
  InputProcessorInterface                (processInput(Input): void)
  OutputProcessorInterface               (processOutput(Output): void)
  Attribute\AsInputProcessor             (TARGET_CLASS | IS_REPEATABLE)
  Attribute\AsOutputProcessor            (TARGET_CLASS | IS_REPEATABLE)
  InputProcessor\SystemPromptInputProcessor
  InputProcessor\ModelOverrideInputProcessor
  Memory\Memory
  Memory\MemoryProviderInterface
  Memory\MemoryInputProcessor
  Memory\StaticMemoryProvider
  Memory\EmbeddingProvider
  Toolbox\Toolbox                        (final)
  Toolbox\ToolboxInterface
  Toolbox\AgentProcessor                 (input + output processor)
  Toolbox\FaultTolerantToolbox
  Toolbox\TraceableToolbox
  Toolbox\Attribute\AsTool               (TARGET_CLASS | IS_REPEATABLE)
  Toolbox\Tool\Subagent                  (wraps an Agent as a tool)
  Toolbox\ToolResult
  Toolbox\ToolResultConverter
  Toolbox\ToolCallArgumentResolver       + Interface
  Toolbox\ToolFactoryInterface
  Toolbox\ToolFactory\ChainFactory
  Toolbox\ToolFactory\ReflectionToolFactory
  Toolbox\ToolFactory\MemoryToolFactory
  Toolbox\StreamListener
  Toolbox\Exception\ToolException              (config error)
  Toolbox\Exception\ToolConfigurationException
  Toolbox\Exception\ToolExecutionException
  Toolbox\Exception\ToolExecutionExceptionInterface
  Toolbox\Exception\ToolNotFoundException
  Toolbox\Exception\InvalidToolCallArgumentsException
  Toolbox\Exception\ExceptionInterface
  Toolbox\Source\Source + SourceCollection + HasSourcesInterface + HasSourcesTrait
  MultiAgent\MultiAgent
  MultiAgent\Handoff
  MultiAgent\Handoff\Decision                (@internal)
  SpeechAgent                            (final)
  Speech\SpeechConfiguration
  MockAgent
  MockResponse
  TraceableAgent
  Exception\ExceptionInterface + concrete exceptions
    InvalidArgumentException, LogicException,
    OutOfBoundsException, RuntimeException,
    MaxIterationsExceededException
```

## `Agent`

```php
namespace Symfony\AI\Agent;

final class Agent implements AgentInterface
{
    /**
     * @param iterable<InputProcessorInterface>  $inputProcessors
     * @param iterable<OutputProcessorInterface> $outputProcessors
     * @param non-empty-string                   $model
     */
    public function __construct(
        private readonly PlatformInterface $platform,
        private readonly string $model,
        private readonly iterable $inputProcessors = [],
        private readonly iterable $outputProcessors = [],
        private readonly string $name = 'agent',
    );

    public function getModel(): string;
    public function getName(): string;

    /**
     * @param array<string, mixed> $options
     */
    public function call(string|MessageBag|UserMessage $input, array $options = []): ResultInterface;
}
```text

There is **no** `$toolboxes` constructor argument. Tools enter the pipeline only via processors.

## `AgentInterface`

```php
namespace Symfony\AI\Agent;

interface AgentInterface
{
    public function call(string|MessageBag|UserMessage $input, array $options = []): ResultInterface;
    public function getName(): string;
}
```

Implemented by `Agent`, `MultiAgent`, `SpeechAgent`, `MockAgent`, `TraceableAgent`.

## `Input` / `Output` / `InputNormalizer`

```php
namespace Symfony\AI\Agent;

final class Input
{
    public function __construct(string $model, MessageBag $messageBag, array $options = []);
    public function getModel(): string;
    public function setModel(string $model): void;
    public function getMessageBag(): MessageBag;
    public function setMessageBag(MessageBag $messageBag): void;
    public function getOptions(): array;
    public function setOptions(array $options): void;
}

final class Output
{
    public function __construct(string $model, ResultInterface $result, MessageBag $messageBag, array $options = []);
    public function getModel(): string;
    public function getResult(): ResultInterface;
    public function setResult(ResultInterface $result): void;
    public function getMessageBag(): MessageBag;
    public function getOptions(): array;
}

final class InputNormalizer
{
    public static function toMessageBag(string|MessageBag|UserMessage $input): MessageBag;
}
```text

`InputProcessorInterface::processInput(Input): void` mutates the bag in place. Same for `OutputProcessorInterface::processOutput(Output): void`.

## `AgentAwareInterface` / `AgentAwareTrait`

```php
namespace Symfony\AI\Agent;

interface AgentAwareInterface
{
    public function setAgent(AgentInterface $agent): void;
}

trait AgentAwareTrait
{
    private AgentInterface $agent;
    public function setAgent(AgentInterface $agent): void { $this->agent = $agent; }
}
```

`Agent::call()` injects `$this` into any processor that implements `AgentAwareInterface`. `AgentProcessor` and `SystemPromptInputProcessor` (when paired with a `Toolbox`) use this to recurse into the agent for the next loop iteration.

## Processor attributes

```php
namespace Symfony\AI\Agent\Attribute;

#[\Attribute(\Attribute::TARGET_CLASS | \Attribute::IS_REPEATABLE)]
final class AsInputProcessor
{
    public function __construct(public readonly ?string $agent = null, public readonly int $priority = 0);
}

#[\Attribute(\Attribute::TARGET_CLASS | \Attribute::IS_REPEATABLE)]
final class AsOutputProcessor
{
    public function __construct(public readonly ?string $agent = null, public readonly int $priority = 0);
}
```text

Used by the `ai-bundle` to auto-discover and tag processors.

## Built-in input processors

```php
namespace Symfony\AI\Agent\InputProcessor;

final class SystemPromptInputProcessor implements InputProcessorInterface
{
    /**
     * @param \Stringable|TranslatableInterface|string|File $systemPrompt
     */
    public function __construct(
        \Stringable|TranslatableInterface|string|File $systemPrompt,
        ?ToolboxInterface $toolbox = null,
        ?TranslatorInterface $translator = null,
        LoggerInterface $logger = new NullLogger(),
    );

    public function getSystemPrompt(): \Stringable|TranslatableInterface|string|File;
    public function processInput(Input $input): void;
}

final class ModelOverrideInputProcessor implements InputProcessorInterface
{
    public function processInput(Input $input): void; // reads $input->getOptions()['model']
}
```

## `Toolbox`

```php
namespace Symfony\AI\Agent\Toolbox;

final class Toolbox implements ToolboxInterface
{
    /**
     * @param iterable<object> $tools
     */
    public function __construct(
        iterable $tools,
        ToolFactoryInterface $toolFactory = new ReflectionToolFactory(),
        ToolCallArgumentResolverInterface $argumentResolver = new ToolCallArgumentResolver(),
        LoggerInterface $logger = new NullLogger(),
        ?EventDispatcherInterface $eventDispatcher = null,
    );

    /** @return Tool[] */
    public function getTools(): array;

    /** @throws ToolExecutionExceptionInterface|ToolNotFoundException */
    public function execute(ToolCall $toolCall): ToolResult;
}

interface ToolboxInterface
{
    /** @return Tool[] */
    public function getTools(): array;
    public function execute(ToolCall $toolCall): ToolResult;
}
```php

## `AgentProcessor`

```php
namespace Symfony\AI\Agent\Toolbox;

final class AgentProcessor implements InputProcessorInterface, OutputProcessorInterface, AgentAwareInterface
{
    public function __construct(
        private readonly ToolboxInterface $toolbox,
        private readonly ToolResultConverter $resultConverter = new ToolResultConverter(),
        private readonly ?EventDispatcherInterface $eventDispatcher = null,
        private readonly bool $excludeToolMessages = false,
        private readonly bool $includeSources = false,
        private readonly ?int $maxToolCalls = 50,
    );
}
```

- `processInput()` injects the tool list into `Input::$options['tools']` (optionally filtered by `options['tools']` as a flat string array).
- `processOutput()` checks for `ToolCallResult`, executes the loop, recurses into the agent until a non-`ToolCallResult` is returned.
- Default `maxToolCalls` is **50**; throws `MaxIterationsExceededException` past that.

## `FaultTolerantToolbox`

```php
namespace Symfony\AI\Agent\Toolbox;

final class FaultTolerantToolbox implements ToolboxInterface
{
    public function __construct(
        private readonly ToolboxInterface $innerToolbox,
    );

    public function getTools(): array;
    public function execute(ToolCall $toolCall): ToolResult;
}
```text

Catches `ToolExecutionExceptionInterface` and converts it to a `ToolResult` carrying the exception's `getToolCallResult()` message. Catches `ToolNotFoundException` and returns a `ToolResult` with the list of valid tool names. **It does NOT retry and does NOT open a circuit.**

## `TraceableToolbox`

```php
namespace Symfony\AI\Agent\Toolbox;

final class TraceableToolbox implements ToolboxInterface, ResetInterface
{
    public function __construct(private readonly ToolboxInterface $toolbox);

    public function getTools(): array;
    public function execute(ToolCall $toolCall): ToolResult;

    /** @return ToolResult[] */
    public function getCalls(): array;
    public function reset(): void;
}
```

Records every `execute()` call. Useful for assertions in tests.

## `#[AsTool]`

```php
namespace Symfony\AI\Agent\Toolbox\Attribute;

#[\Attribute(\Attribute::TARGET_CLASS | \Attribute::IS_REPEATABLE)]
final class AsTool
{
    /**
     * @param array<string, mixed> $metadata
     */
    public function __construct(
        public readonly string $name,
        public readonly string $description,
        public readonly string $method = '__invoke',
        public readonly array $metadata = [],
    );
}
```text

- `TARGET_CLASS | IS_REPEATABLE` : place on the class, repeat for each exposed method.
- Positional: `(name, description, method, metadata)`. Use named args if order is unclear.
- For multiple methods on the same class (e.g. `Filesystem`, `Firecrawl`, `Tavily`, `Wikipedia`, `Mapbox`, `OpenMeteo`, `Ollama`), repeat the attribute : each repetition is one registered tool.

## `Tool` factory chain

```php
namespace Symfony\AI\Agent\Toolbox;

interface ToolFactoryInterface
{
    /** @return iterable<Tool> */
    public function getTool(object|string $reference): iterable;
}

final class ReflectionToolFactory implements ToolFactoryInterface;   // default — reads #[AsTool]
final class MemoryToolFactory   implements ToolFactoryInterface;   // pre-registered tools
final class ChainFactory        implements ToolFactoryInterface;   // first-factory wins
```

## `ToolResult`, `ToolResultConverter`, `StreamListener`

```php
namespace Symfony\AI\Agent\Toolbox;

final class ToolResult
{
    public function __construct(ToolCall $toolCall, mixed $result, ?SourceCollection $sources = null);
    public function getToolCall(): ToolCall;
    public function getResult(): mixed;
    public function getSources(): ?SourceCollection;
}

final class ToolResultConverter
{
    public function __construct(SerializerInterface $serializer = new Serializer(...));
    /** @throws RuntimeException */
    public function convert(ToolResult $toolResult): ?string;
}

final class StreamListener extends AbstractStreamListener
{
    public function __construct(\Closure $handleToolCallsCallback);
}
```php

## `ToolCallArgumentResolver`

```php
namespace Symfony\AI\Agent\Toolbox;

interface ToolCallArgumentResolverInterface
{
    /** @return array<string, mixed>
     *  @throws ToolException
     */
    public function resolveArguments(Tool $metadata, ToolCall $toolCall): array;
}

final class ToolCallArgumentResolver implements ToolCallArgumentResolverInterface
{
    public function __construct(?DenormalizerInterface $denormalizer = null, ?TypeResolver $typeResolver = null);
}
```

Builds the default Symfony Serializer (DateTime / BackedEnum / Object / Array denormalizers) when none is provided. Resolves typed parameters and converts `?nullable` and `CollectionType` (array) dimensions.

## `Subagent`

```php
namespace Symfony\AI\Agent\Toolbox\Tool;

final class Subagent implements HasSourcesInterface
{
    public function __construct(private readonly AgentInterface $agent);

    /** @param string $message */
    public function __invoke(string $message): string;
}
```text

Wraps any `AgentInterface` as a tool. Returns the text content of the agent's `TextResult` and propagates sources.

## Toolbox exceptions

```php
namespace Symfony\AI\Agent\Toolbox\Exception;

interface ExceptionInterface extends \Symfony\AI\Agent\Exception\ExceptionInterface {}

final class ToolException extends InvalidArgumentException implements ExceptionInterface
{
    public static function invalidReference(mixed $reference): self;
    public static function missingAttribute(string $className): self;
}

final class ToolConfigurationException extends InvalidArgumentException implements ExceptionInterface
{
    public static function invalidMethod(string $toolClass, string $methodName, \ReflectionException $previous): self;
}

interface ToolExecutionExceptionInterface extends ExceptionInterface
{
    public function getToolCallResult(): mixed;
}

final class ToolExecutionException extends \RuntimeException implements ToolExecutionExceptionInterface
{
    public static function executionFailed(ToolCall $toolCall, \Throwable $previous): self;
    public function getToolCall(): ?ToolCall;
    public function getToolCallResult(): string;
}

final class InvalidToolCallArgumentsException extends \RuntimeException implements ToolExecutionExceptionInterface
{
    public function getToolCallResult(): mixed;
}

final class ToolNotFoundException extends \RuntimeException implements ExceptionInterface
{
    public static function notFoundForToolCall(ToolCall $toolCall): self;
    public static function notFoundForReference(ExecutionReference $reference): self;
    public function getToolCall(): ?ToolCall;
}
```

`ToolException` is the **configuration error** (raised during tool metadata extraction). `ToolExecutionExceptionInterface` is the **runtime error** (wraps any `Throwable` thrown by a tool body).

## Memory

```php
namespace Symfony\AI\Agent\Memory;

final class Memory
{
    public function __construct(private readonly string $content);
    public function getContent(): string;
}

interface MemoryProviderInterface
{
    /** @return list<Memory> */
    public function load(Input $input): array;
}

final class StaticMemoryProvider implements MemoryProviderInterface
{
    /** @param array<string> $memory */
    public function __construct(array $memory = []);
    public function load(Input $input): array;   // returns [Memory] with all items, or [] when empty
}

final class EmbeddingProvider implements MemoryProviderInterface
{
    public function __construct(
        private readonly PlatformInterface $platform,
        private readonly Model $model,                  // Symfony\AI\Platform\Model, NOT a string
        private readonly StoreInterface $vectorStore,
    );
    public function load(Input $input): array;
}

final class MemoryInputProcessor implements InputProcessorInterface
{
    /** @param iterable<MemoryProviderInterface> $memoryProviders */
    public function __construct(private readonly iterable $memoryProviders);
    public function processInput(Input $input): void; // toggle via $options['use_memory'] = false
}
```text

There is **no** `MemoryInterface` and **no** `MemoryOutputProcessor` in this version. All providers are read-only retrieval.

## `MultiAgent`

```php
namespace Symfony\AI\Agent\MultiAgent;

final class MultiAgent implements AgentInterface
{
    /**
     * @param Handoff[] $handoffs
     */
    public function __construct(
        private AgentInterface $orchestrator,
        private array $handoffs,
        private AgentInterface $fallback,
        private string $name = 'multi-agent',
        private LoggerInterface $logger = new NullLogger(),
    );

    public function getName(): string;
    public function call(string|MessageBag|UserMessage $input, array $options = []): ResultInterface;
}

final class Handoff
{
    /** @param string[] $when */
    public function __construct(private readonly AgentInterface $to, private readonly array $when);
    public function getTo(): AgentInterface;
    /** @return string[] */
    public function getWhen(): array;
}

/** @internal */
final class Decision
{
    public function __construct(private readonly string $agentName, private readonly string $reasoning);
    public function hasAgent(): bool;
    public function getAgentName(): string;
    public function getReasoning(): string;
}
```

Routing flow: orchestrator receives a `response_format: Decision::class` call, returns either a `Decision` with an empty `agentName` (fallback) or a `Decision` with one of the registered agent names. If `Decision` parse fails, the orchestrator is called directly with the original messages.

## `SpeechAgent` + `SpeechConfiguration`

```php
namespace Symfony\AI\Agent;

final class SpeechAgent implements AgentInterface
{
    public function __construct(
        private readonly AgentInterface $agent,
        private readonly SpeechConfiguration $configuration,
        private readonly ?PlatformInterface $speechToTextPlatform = null,
        private readonly ?PlatformInterface $textToSpeechPlatform = null,
    );

    public function call(string|MessageBag|UserMessage $input, array $options = []): ResultInterface;
    public function getName(): string;
}

namespace Symfony\AI\Agent\Speech;

final class SpeechConfiguration
{
    /** @param array<string, mixed> $ttsOptions
     *  @param array<string, mixed> $sttOptions
     */
    public function __construct(
        ?string $ttsModel = null,
        array $ttsOptions = [],
        ?string $sttModel = null,
        array $sttOptions = [],
    );

    public function supportsTextToSpeech(): bool;     // ttsModel !== null
    public function supportsSpeechToText(): bool;     // sttModel !== null
    public function getTextToSpeechModel(): ?string;
    public function getSpeechToTextModel(): ?string;
    public function getTextToSpeechOptions(): array;
    public function getSpeechToTextOptions(): array;
}
```php

## Testing & observability agents

```php
namespace Symfony\AI\Agent;

final class MockAgent implements AgentInterface
{
    /** @param array<string, string|MockResponse|StreamResult|\Closure> $responses */
    public function __construct(array $responses = [], string $name = 'mock');
    public function call(string|MessageBag|UserMessage $input, array $options = []): ResultInterface;
    public function addResponse(string $input, string|MockResponse|\Closure $response): self;
    public function clearResponses(): self;
    public function getResponses(): array;
    public function getCallCount(): int;
    public function getCalls(): array;
    public function getCall(int $index): array;
    public function getLastCall(): array;
    public function assertCallCount(int $expected): void;
    public function assertCalled(): void;
    public function assertNotCalled(): void;
    public function assertCalledWith(string $expectedInput): void;
    public function reset(): self;
    public function getName(): string;
}

final class MockResponse
{
    public function __construct(string $content = '');
    public function toResult(): ResultInterface;
    public function getContent(): string;
    public static function create(string $content): self;
}

final class TraceableAgent implements AgentInterface, ResetInterface
{
    /** @phpstan-type AgentData array{
     *     input: string|MessageBag|UserMessage,
     *     options: array<string, mixed>,
     *     called_at: \DateTimeImmutable,
     * }
     */
    public function __construct(
        private readonly AgentInterface $agent,
        private readonly ClockInterface $clock = new MonotonicClock(),
    );

    public function call(string|MessageBag|UserMessage $input, array $options = []): ResultInterface;
    public function getName(): string;
    /** @return AgentData[] */
    public function getCalls(): array;
    public function reset(): void;
}
```

## Tool bridges (13)

Each is a class in `src/agent/src/Bridge/<Name>/` exposing one or more `#[AsTool]` methods. Listed alphabetically:

| Bridge class                        | Tools exposed (per `#[AsTool]`)                                             | Source collection         |
| ----------------------------------- | --------------------------------------------------------------------------- | ------------------------- |
| `Brave\Brave`                       | `brave_search`                                                              | yes (HasSourcesInterface) |
| `Clock\Clock`                       | `clock`                                                                     | yes                       |
| `Filesystem\Filesystem`             | `filesystem_read/write/append/copy/move/delete/mkdir/exists/info/list` (10) | no                        |
| `Filesystem\PathValidator`          | (utility, not a tool)                                                       | :                         |
| `Firecrawl\Firecrawl`               | `firecrawl_scrape / crawl / map`                                            | no                        |
| `Mapbox\Mapbox`                     | `geocode`, `reverse_geocode`                                                | no                        |
| `Ollama\Ollama`                     | `web_search`, `fetch_webpage`                                               | yes                       |
| `OpenMeteo\OpenMeteo`               | `weather_current`, `weather_forecast`                                       | no                        |
| `Scraper\Scraper`                   | `scraper`                                                                   | yes                       |
| `SerpApi\SerpApi`                   | `serpapi`                                                                   | yes                       |
| `SimilaritySearch\SimilaritySearch` | `similarity_search` (also `getUsedDocuments()` accessor)                    | no                        |
| `Tavily\Tavily`                     | `tavily_search`, `tavily_extract`                                           | yes                       |
| `Wikipedia\Wikipedia`               | `wikipedia_search`, `wikipedia_article`                                     | yes                       |
| `Youtube\YoutubeTranscriber`        | `youtube_transcript`                                                        | no                        |

## Tool-call lifecycle events

`Toolbox::execute()` dispatches the request event before argument resolution; argument resolution is then attempted via `ToolCallArgumentResolverInterface::resolveArguments()`, and on successful resolution the `ToolCallArgumentsResolved` event is dispatched before invocation runs. Any throwable : resolution or invocation : dispatches `ToolCallFailed`. `AgentProcessor` dispatches the batch event after each batch of calls.

| Event                       | Constructor                                                                            | Public methods                                                                                                                                                                                                                                                     | Role                                                                                                                                                                                               |
| --------------------------- | -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ToolCallRequested`         | `__construct(ToolCall $toolCall, Tool $definition)`                                    | `getToolCall(): ToolCall`, `getDefinition(): Tool`, `deny(?string $reason = null): void`, `isDenied(): bool`, `getDenialReason(): ?string`, `setResult(ToolResult $result): void`, `hasResult(): bool`, `getResult(): ?ToolResult`, `isPropagationStopped(): bool` | Pre-execution gate. `deny()` refuses execution; `setResult()` substitutes a result and skips execution.                                                                                            |
| `ToolCallArgumentsResolved` | `__construct(object $tool, Tool $definition, array $arguments)`                        | `getTool(): object`, `getDefinition(): Tool`, `getArguments(): array`                                                                                                                                                                                              | Post-denormalization inspection/validation, immediately before invocation.                                                                                                                         |
| `ToolCallSucceeded`         | `__construct(object $tool, Tool $definition, array $arguments, ToolResult $result)`    | `getTool(): object`, `getDefinition(): Tool`, `getArguments(): array`, `getResult(): ToolResult`                                                                                                                                                                   | Published after the tool returns successfully.                                                                                                                                                     |
| `ToolCallFailed`            | `__construct(object $tool, Tool $definition, array $arguments, \Throwable $exception)` | `getTool(): object`, `getDefinition(): Tool`, `getArguments(): array`, `getException(): \Throwable`                                                                                                                                                                | Published when argument resolution or tool invocation fails. `getArguments()` may return an empty array when the failure occurs before resolution completes (`Toolbox` passes `$arguments ?? []`). |
| `ToolCallsExecuted`         | `__construct(array $toolResults)`                                                      | `getToolResults(): array`, `hasResult(): bool`, `setResult(ResultInterface $result): void`, `getResult(): ResultInterface`                                                                                                                                         | Batch hook after execution; `setResult()` can replace the next agent result.                                                                                                                       |

`#[IsGrantedTool]` is Symfony authorization applied to a tool. It is distinct from the runtime `ToolCallRequested::deny()`, which is an event-listener decision for one call. `ToolCallRequested::setResult()` is result substitution without execution. Use `ToolCallArgumentsResolved` when validating the denormalized, typed arguments; the request event still sees the original `ToolCall` payload.

The event dispatcher is optional in both `Toolbox` and `AgentProcessor`; to observe one complete lifecycle, pass the same dispatcher instance to both constructors. Symfony AI is experimental; verify these contracts against the current source and `UPGRADE.md` before upgrading.
