# Agent : API Reference

Read this when the user asks for the full signature catalogue of the Agent framework. Every signature below is taken verbatim from `src/agent/src/` : re-verify against the source if you change anything.

## Contents

- Namespace tree
- `Agent`
- `AgentInterface`
- `Input` / `Output` / `InputNormalizer`
- `AgentAwareInterface` / `AgentAwareTrait`
- Processor attributes
- Built-in input processors
- `Toolbox`
- `ToolExecutorInterface` / `SequentialToolExecutor` / `FiberToolExecutor`
- `FaultTolerantToolbox`
- `ChainToolbox` / `AbstractToolbox`
- `TraceableToolbox`
- `#[AsTool]`
- `Tool` factory chain
- `ToolResult`, `ToolResultConverter`
- `ExecutionInterface` / `Execution` / `ExecutionStatus`
- `ToolCallArgumentResolver` (+ `#[MapToolArguments]`)
- `Subagent`
- Toolbox exceptions
- Memory
- Message stores
- `MultiAgent`
- `SpeechAgent` + `SpeechConfiguration`
- Testing & observability agents
- Tool-call lifecycle events

## Namespace tree

```text
Symfony\AI\Agent\
  Agent                                  (final)
  AgentInterface                         (call, getName)
  AgentAwareInterface + AgentAwareTrait  (setAgent)
  Input                                  (final, mutable)
  Output                                 (final)
  InputNormalizer                        (@internal, static toMessageBag)
  Execution\ExecutionInterface           (1.0: returned by AgentInterface::call())
  Execution\Execution                    (final, lazy, the implementation)
  Execution\ExecutionStatus              (1.0: enum Pending | Running | WaitingForInput | Completed | Failed | Cancelled)
  Execution\UpdateInterface              (getType(): UpdateType)
  Execution\UpdateType                   (enum: Progress, Result)
  Execution\Update\Progress              (final, non-blocking progress update)
  Execution\Update\Result                (final, terminal update wrapping the ResultInterface and, since 1.0, the messages of the run)
  Execution\Runner                       (@internal, drives the tool-calling loop and enforces maxToolCalls; exposeTools() applies the per-call `tools` option)
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
  MessageStore\MessageStoreInterface     (1.0: load(id), save(bag), delete(id))
  MessageStore\ManagedMessageStoreInterface (1.0: setup(), drop())
  MessageStore\InMemoryMessageStore      (1.0)
  MessageStore\TraceableMessageStore     (1.0, moved from Chat)
  MessageStore\ConflictDetector          (1.0, for custom stores)
  Command\SetupMessageStoreCommand       (1.0: ai:message-store:setup)
  Command\DropMessageStoreCommand        (1.0: ai:message-store:drop)
  Bridge\<Backend>\MessageStore          (1.0: 9 message-store bridges, see references/bridges.md)
  Toolbox\Toolbox                        (final, extends AbstractToolbox)
  Toolbox\ToolboxInterface
  Toolbox\AbstractToolbox                (0.14: shared lookup/events/error handling)
  Toolbox\ChainToolbox                   (0.14: several toolboxes as one)
  Toolbox\ToolExecutorInterface
  Toolbox\SequentialToolExecutor         (default ToolExecutorInterface)
  Toolbox\FiberToolExecutor              (0.14: concurrent tool calls via Fibers)
  Toolbox\SuspendableTrait               (0.14: cooperative yield point for tools)
  Toolbox\FaultTolerantToolbox
  Toolbox\TraceableToolbox
  Toolbox\Attribute\AsTool               (TARGET_CLASS | IS_REPEATABLE)
  Toolbox\Attribute\MapToolArguments     (0.14: TARGET_PARAMETER, flat payload → DTO)
  Toolbox\Tool\Subagent                  (wraps an Agent as a tool)
  Toolbox\ToolResult
  Toolbox\ToolResultConverter
  Toolbox\ToolCallArgumentResolver       + Interface
  Toolbox\ToolFactoryInterface
  Toolbox\ToolFactory\ChainFactory
  Toolbox\ToolFactory\ReflectionToolFactory
  Toolbox\ToolFactory\MemoryToolFactory
  Toolbox\Exception\ToolException              (config error)
  Toolbox\Exception\ToolConfigurationException
  Toolbox\Exception\ToolExecutionException
  Toolbox\Exception\ToolExecutionExceptionInterface
  Toolbox\Exception\ToolNotFoundException
  Toolbox\Exception\InvalidToolCallArgumentsException
  Toolbox\Exception\ExceptionInterface
  Toolbox\Source\Source + SourceCollection + HasSourcesInterface + HasSourcesTrait
  Toolbox\Source\SourceCollectionNormalizer  (1.0: keeps the sources of an answer when its messages are serialized)
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
    MaxIterationsExceededException,
    ConflictException                    (1.0, extends RuntimeException)
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
     * @param bool                                $includeSources      exposes the sources collected during tool calling as `sources` result metadata
     */
    public function __construct(
        PlatformInterface $platform,
        private readonly string $model,
        private readonly iterable $inputProcessors = [],
        private readonly iterable $outputProcessors = [],
        private readonly string $name = 'agent',
        ?ToolboxInterface $toolbox = null,
        ?ToolExecutorInterface $toolExecutor = null,
        ?int $maxToolCalls = 50,
        bool $includeSources = false,
        ?EventDispatcherInterface $eventDispatcher = null,
        ToolResultConverter $toolResultConverter = new ToolResultConverter(),   // 1.0
        private readonly ?MessageStoreInterface $messageStore = null,          // 1.0
    );

    public function getModel(): string;
    public function getName(): string;

    /**
     * @param array<string, mixed> $options
     */
    public function call(string|MessageBag|UserMessage $input, array $options = []): ExecutionInterface;
}
```

`toolbox` is the 6th constructor parameter (pass it by name). When set and no `toolExecutor` is given, `Agent` defaults to `SequentialToolExecutor`. `Agent` drives the tool-calling loop itself; tools no longer enter the pipeline via a processor.

1.0 removed `excludeToolMessages` (tool messages never reach the caller's bag any more), so every argument after `maxToolCalls` moved up by one: pass them by name. `toolResultConverter` customises how a `ToolResult` becomes the text the model reads. With a `messageStore`, `call()` loads the conversation stored under the bag id, appends the given messages it does not know yet (matched by message id), saves it, and saves again after each round of tool calls and with the answer.

## `AgentInterface`

```php
namespace Symfony\AI\Agent;

interface AgentInterface
{
    /**
     * Starts the agent and returns a lazy {@see ExecutionInterface} : nothing runs until it is consumed.
     */
    public function call(string|MessageBag|UserMessage $input, array $options = []): ExecutionInterface;
    public function getName(): string;
}
```

Implemented by `Agent`, `MultiAgent`, `SpeechAgent`, `MockAgent`, `TraceableAgent` : all return an `ExecutionInterface` (the `Execution` class implements it), not a `ResultInterface` directly. Since 1.0 a custom `AgentInterface` and any code type-hinting the result of `call()` must use `ExecutionInterface`.

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
```

`InputProcessorInterface::processInput(Input): void` mutates the `Input`, not the bag: `MessageBag` is immutable since 1.0, so a processor builds a new bag and sets it back. `OutputProcessorInterface::processOutput(Output): void` replaces the result with `setResult()`.

```php
// 0.x: $input->getMessageBag()->add($message);
$input->setMessageBag($input->getMessageBag()->with($message));
```

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

`Agent::call()` injects `$this` into any processor that implements `AgentAwareInterface`. No built-in processor implements it since the tool-calling loop moved out of the processor pipeline and into `Agent` itself; it remains a hook point for custom processors. `SystemPromptInputProcessor` does **not**: it is declared `final class SystemPromptInputProcessor implements InputProcessorInterface` and implements no agent-aware contract, so it never receives the agent.

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
```

Used by the `ai-bundle` to auto-discover and tag processors.

## Built-in input processors

```php
namespace Symfony\AI\Agent\InputProcessor;

final class SystemPromptInputProcessor implements InputProcessorInterface
{
    /**
     * @param \Stringable|TranslatableInterface|string|File|Template $systemPrompt
     */
    public function __construct(
        \Stringable|TranslatableInterface|string|File|Template $systemPrompt,
        ?ToolboxInterface $toolbox = null,
        ?TranslatorInterface $translator = null,
        LoggerInterface $logger = new NullLogger(),
    );

    public function getSystemPrompt(): \Stringable|TranslatableInterface|string|File|Template;
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

final class Toolbox extends AbstractToolbox   // AbstractToolbox implements ToolboxInterface
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
```

## `ToolExecutorInterface` / `SequentialToolExecutor` / `FiberToolExecutor`

```php
namespace Symfony\AI\Agent\Toolbox;

interface ToolExecutorInterface
{
    /**
     * @param ToolCall[] $toolCalls
     *
     * @return \Generator<int, UpdateInterface, mixed, ToolResult[]> yields progress updates while the calls run,
     *                                                                returns one result per call, same order as given
     */
    public function execute(array $toolCalls): \Generator;
}

// FiberToolExecutor (since 0.14) has the identical shape
final class SequentialToolExecutor implements ToolExecutorInterface
{
    public function __construct(
        private readonly ToolboxInterface $toolbox,
    );

    public function execute(array $toolCalls): \Generator;
}
```

`FiberToolExecutor` starts one PHP Fiber per tool call before collecting any result and round-robins the suspended fibers; results come back in the order of the calls. This is **cooperative concurrency, not parallelism**: a tool only yields when it calls `\Fiber::suspend()`, typically through `SuspendableTrait::suspend()` placed between sending an HTTP request and reading its response (a no-op outside a Fiber, so safe under `SequentialToolExecutor` and in tests):

```php
use Symfony\AI\Agent\Toolbox\Attribute\AsTool;
use Symfony\AI\Agent\Toolbox\SuspendableTrait;

#[AsTool('weather', 'Fetches current weather data')]
final class WeatherTool
{
    use SuspendableTrait;

    public function __construct(private HttpClientInterface $httpClient) {}

    public function __invoke(string $city): string
    {
        $response = $this->httpClient->request('GET', 'https://api.example.com/weather', ['query' => ['q' => $city]]);
        $this->suspend();                   // let the other tool calls send their requests
        return $response->getContent();     // blocks, but every request is already on the wire
    }
}

$agent = new Agent($platform, 'gpt-4o-mini', toolbox: $toolbox, toolExecutor: new FiberToolExecutor($toolbox));
```

In `ai-bundle`, pick it per agent with `tools: { execution_strategy: fiber }`.

There is no more `AgentProcessor` : tool calling is driven by `Agent` itself, delegating to `Symfony\AI\Agent\Execution\Runner` (`@internal`), which enforces `maxToolCalls` directly (a counter incremented per iteration, throwing `MaxIterationsExceededException` once it exceeds the limit) and drives the loop via `ToolExecutorInterface` (default `SequentialToolExecutor`, one call after another) until a non-`ToolCallResult` is returned. Default `maxToolCalls` is **50**. A custom `ToolExecutorInterface` (e.g. concurrent execution) can be passed via the `toolExecutor` constructor argument. `Runner::exposeTools()` also honors a per-call `tools` option (see `references/gotchas.md` #13) to restrict, for one `Agent::call()` only, which tools are exposed.

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
```

Catches `ToolExecutionExceptionInterface` and converts it to a `ToolResult` carrying the exception's `getToolCallResult()` message. Catches `ToolNotFoundException` and returns a `ToolResult` with the list of valid tool names. **It does NOT retry and does NOT open a circuit.**

## `ChainToolbox` / `AbstractToolbox`

```php
namespace Symfony\AI\Agent\Toolbox;

final class ChainToolbox implements ToolboxInterface   // since 0.14
{
    /** @param iterable<ToolboxInterface> $toolboxes */
    public function __construct(private readonly iterable $toolboxes);

    public function getTools(): array;
    public function execute(ToolCall $toolCall): ToolResult;   // runs on the toolbox advertising the tool
}

abstract class AbstractToolbox implements ToolboxInterface      // since 0.14
{
    public function __construct(LoggerInterface $logger = new NullLogger(), ?EventDispatcherInterface $eventDispatcher = null);

    final public function execute(ToolCall $toolCall): ToolResult;   // lookup + tool-call events + error handling

    abstract protected function getExecutable(Tool $metadata): object;
    abstract protected function resolveArguments(object $tool, Tool $metadata, ToolCall $toolCall): array;
    abstract protected function invoke(object $tool, Tool $metadata, array $arguments): mixed;
    protected function prepareSources(object $tool): ?SourceCollection;
}
```

`ChainToolbox` offers the tools of several toolboxes (e.g. local `#[AsTool]` services plus a remote MCP server) to one agent. A tool name advertised by **more than one** toolbox throws `ToolConfigurationException` instead of silently picking one. Extend `AbstractToolbox` for a toolbox in front of a remote tool protocol: only say how a call becomes a value, the events and error handling stay identical to `Toolbox`.

## `TraceableToolbox`

```php
namespace Symfony\AI\Agent\Toolbox;

final class TraceableToolbox implements ToolboxInterface, ResetInterface
{
    public function __construct(private readonly ToolboxInterface $toolbox, private readonly ?Stopwatch $stopwatch = null);

    public function getTools(): array;
    public function execute(ToolCall $toolCall): ToolResult;

    /** @return ToolResult[] */
    public function getCalls(): array;
    public function reset(): void;
}
```

Records every `execute()` call. Useful for assertions in tests. With a `Stopwatch` (since 0.14) each tool execution is timed : this feeds the profiler's performance timeline.

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
        public readonly ToolEffectHints $effectHints = new ToolEffectHints(),   // 1.0
    );
}
```

- `TARGET_CLASS | IS_REPEATABLE` : place on the class, repeat for each exposed method.
- Positional: `(name, description, method, metadata, effectHints)`. Use named args if order is unclear.
- `effectHints` (1.0) takes a `Symfony\AI\Platform\Tool\ToolEffectHints(?bool $readOnlyHint, ?bool $destructiveHint, ?bool $idempotentHint, ?bool $openWorldHint)`, the MCP tool annotations. The hints that are set are merged into `Tool::getMetadata()` under their spec names, and `Tool` answers `isReadOnly()`, `isDestructive()`, `isIdempotent()`, `isOpenWorld()` with the MCP defaults: a tool without hints counts as destructive and open-world. Nothing in the agent enforces them; a `ToolCallRequested` listener can, e.g. `if ($event->getDefinition()->isDestructive()) { $event->deny('Needs a confirmation.'); }`. `MemoryToolFactory::addTool()` takes the same trailing `effectHints` argument.
- For multiple methods on the same class (e.g. `Filesystem`, `Firecrawl`, `Tavily`, `Wikipedia`, `Mapbox`, `OpenMeteo`, `Ollama`), repeat the attribute : each repetition is one registered tool.

## `Tool` factory chain

```php
namespace Symfony\AI\Agent\Toolbox;

interface ToolFactoryInterface
{
    /** @return iterable<Tool> */
    public function getTool(object|string $reference): iterable;
}

namespace Symfony\AI\Agent\Toolbox\ToolFactory;

final class ReflectionToolFactory implements ToolFactoryInterface;   // default — reads #[AsTool]
final class MemoryToolFactory   implements ToolFactoryInterface;   // pre-registered tools
final class ChainFactory        implements ToolFactoryInterface;   // first-factory wins
```

## `ToolResult`, `ToolResultConverter`

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
```

There is no more `Toolbox\StreamListener` : it was removed. `Execution` (below) now handles streaming and observation natively.

## `ExecutionInterface` / `Execution` / `ExecutionStatus`

```php
namespace Symfony\AI\Agent\Execution;

interface ExecutionInterface extends \IteratorAggregate, ResultInterface   // 1.0
{
    public function getId(): AbstractUid&TimeBasedUidInterface;  // 1.0: identifies the run; the conversation is the MessageBag id
    public function getStatus(): ExecutionStatus;                // 1.0
    public function isSuspended(): bool;                         // 1.0: status is WaitingForInput
    /** @return list<ToolCall> */
    public function getPendingToolCalls(): array;                // 1.0: tool calls of the final result left unanswered
    public function getError(): ?string;                         // 1.0: message of a failed execution
    public function getMessages(): MessageBag;                   // 1.0: drives to completion, given messages + those of the run, ending with the answer
    public function onProgress(callable $callback): self;        // callback(Update\Progress): void
    public function onResult(callable $callback): self;          // callback(Update\Result): void
    public function isStreamed(): bool;                          // getContent() yields deltas
    public function cancel(): void;                              // stops it and cancels the active HTTP response
    public function getResult(): ResultInterface;                // drives the execution to completion
    public function asStream(): \Generator;                      // yields DeltaInterface; throws LogicException when not streamed
    public function asText(): string;
    public function asObject(?string $class = null): object|array; // asserts and types the structured output (T when $class is given)
    // plus asBinary(), asFile(), asDataUri(), asMultiPart(), asBatch(), asToolCalls(),
    // asTextStream(), asStreamedObject(), asPartialJsonStream()
    // and, from ResultInterface: getContent(), getMetadata(), getRawResult()
}

final class Execution implements ExecutionInterface { /* the only implementation; uses Platform's TypedResultTrait */ }

enum ExecutionStatus: string   // 1.0
{
    case Pending = 'pending';                    // not consumed yet
    case Running = 'running';
    case WaitingForInput = 'waiting_for_input';  // the final result holds tool calls nobody answered
    case Completed = 'completed';
    case Failed = 'failed';
    case Cancelled = 'cancelled';

    public function isFinished(): bool;          // Completed, Failed or Cancelled
}
```

`AgentInterface::call()` returns an `ExecutionInterface` : a lazy execution that is also the `ResultInterface` it produces. Nothing runs until it is consumed, three ways:

- **As a result** : `$execution->getContent()` (or `->getResult()`) drives the agent to completion and returns the answer.
- **As a process** : `foreach ($execution as $update) { ... }` observes every `Update\Progress` (model requests, tool calls, streamed deltas) and the terminal `Update\Result`. Match `Progress::getStage()` against the 0.15 constants instead of raw strings: `Progress::STAGE_MODEL_REQUEST` (`'model_request'`, payload: the model name), `STAGE_DELTA` (`'delta'`, payload: the `DeltaInterface`), `STAGE_TOOL_CALL` (`'tool_call'`, payload: the `ToolCall`) and `STAGE_HANDOFF` (`'handoff'`, payload: the `MultiAgent` handoff `Decision`). A decorator or custom agent may report any other non-empty stage string.
- **With callbacks** : `$execution->onProgress($cb)->onResult($cb)->getResult()`.

Consuming drives the agent, **including its side effects** : exceptions and side effects surface on `getContent()`/`getResult()`/iteration, not on the `call()` line itself. The final result is cached (`getContent()`/`getResult()`/`getMetadata()` are idempotent afterward), but **re-iterating an already-consumed execution throws `LogicException`** : call the agent again for a fresh execution. Code that type-checks the result (e.g. `... instanceof TextResult`) must call `->getResult()` first : `Execution` itself is not the typed result, it produces one.

`cancel()` (since 0.14) is a no-op on a finished execution. Otherwise it stops the tool-calling loop and cancels the in-flight HTTP response; consuming the execution afterwards throws `Symfony\AI\Agent\Exception\RuntimeException` ("The agent execution was canceled."). Use it when a client disconnects mid-stream.

With `['stream' => true]`, `getContent()` returns the same generator as `asStream()`, yielding `Result\Stream\Delta\DeltaInterface` deltas as they arrive; `getMetadata()` returns a `Metadata` populated progressively while the deltas are consumed. Because the tool-calling loop no longer recurses through `call()`, output processors now see the final, fully assembled result, and input processors run once per `Agent::call()` instead of once per tool-calling round.

`getMessages()` (1.0) is how a conversation continues without a store: it returns the caller's messages followed by the assistant and tool messages of the run, ending with the answer, under the **id of the caller's bag**. The system prompt and memory added by input processors are not in it. Each assistant message carries the metadata of its own model request (`token_usage`, finish reason), while `getMetadata()` of the execution aggregates the run; with `includeSources`, the final answer carries the `sources` too. A custom agent whose terminal `Update\Result` was built without its `$messages` argument makes `getMessages()` throw `LogicException` ("The agent did not provide the messages of its execution.").

`WaitingForInput` (`isSuspended()`) means the final result is a `ToolCallResult` nobody answered, e.g. an agent built without a toolbox but given tools through the `tools` option: read `getPendingToolCalls()`, run them yourself, add `Message::ofToolCall($toolCall, $output)` messages to the bag from `getMessages()`, and call the agent again.

## `ToolCallArgumentResolver`

```php
namespace Symfony\AI\Agent\Toolbox;

interface ToolCallArgumentResolverInterface
{
    /** @return array<string, mixed>
     *  @throws InvalidToolCallArgumentsException (since 0.14; was ToolException)
     */
    public function resolveArguments(Tool $metadata, ToolCall $toolCall): array;
}

final class ToolCallArgumentResolver implements ToolCallArgumentResolverInterface
{
    public function __construct(?DenormalizerInterface $denormalizer = null, ?TypeResolver $typeResolver = null);
}
```

Builds the default Symfony Serializer (DateTime / BackedEnum / Object / Array denormalizers) when none is provided. Resolves typed parameters and converts `?nullable` and `CollectionType` (array) dimensions. A missing mandatory parameter or an undenormalizable value throws `InvalidToolCallArgumentsException`, which implements `ToolExecutionExceptionInterface` : `FaultTolerantToolbox` turns it into a tool result the model can react to. Code catching `ToolException` around argument resolution must switch (0.14 BC break).

### `#[MapToolArguments]` (since 0.14)

```php
use Symfony\AI\Agent\Toolbox\Attribute\AsTool;
use Symfony\AI\Agent\Toolbox\Attribute\MapToolArguments;

#[AsTool('create_order', 'Creates an order')]
final class CreateOrderTool
{
    public function __invoke(#[MapToolArguments] OrderRequest $request): string
    {
        // ...
    }
}
```

The DTO's properties become the **root** of the tool's JSON schema (not a nested `request` object), and the whole flat tool-call payload is denormalized into it. Only valid on a method with exactly one non-nullable concrete-class parameter; anything else throws `ToolConfigurationException` when the tool is described.

## `Subagent`

```php
namespace Symfony\AI\Agent\Toolbox\Tool;

final class Subagent implements HasSourcesInterface
{
    public function __construct(private readonly AgentInterface $agent);

    /** @param string $message */
    public function __invoke(string $message): string;
}
```

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
```

There is **no** `MemoryInterface` and **no** `MemoryOutputProcessor` in this version. All providers are read-only retrieval. `MemoryInputProcessor` merges the memories into the system message with `MessageBag::withSystemMessage()`, which replaces every system message of the bag by the combined one.

## Message stores

New in 1.0: they replace the `symfony/ai-chat` stores, keyed by the conversation id instead of one store per conversation.

```php
namespace Symfony\AI\Agent\MessageStore;

interface MessageStoreInterface
{
    /** @return MessageBag the stored messages, or an empty bag with the given id */
    public function load(AbstractUid&TimeBasedUidInterface $id): MessageBag;

    /** @throws ConflictException when the stored messages don't start the given ones */
    public function save(MessageBag $messages): void;

    public function delete(AbstractUid&TimeBasedUidInterface $id): void;
}

interface ManagedMessageStoreInterface   // stores with a table, index or collection to create
{
    public function setup(array $options = []): void;
    public function drop(): void;   // removes every conversation of the store
}

final class InMemoryMessageStore implements MessageStoreInterface, ResetInterface {}   // one process only

final class TraceableMessageStore implements ManagedMessageStoreInterface, MessageStoreInterface, ResetInterface
{
    public function __construct(MessageStoreInterface $messageStore, ClockInterface $clock);
    public function getCalls(): array;   // one entry per save()
    public function reset(): void;
}

final class ConflictDetector   // helpers for a custom store
{
    /** @throws ConflictException if $messages does not start with the messages of $stored */
    public static function assertContinues(MessageBag $stored, MessageBag $messages): void;
    public static function version(MessageBag $messages): string;   // id of the last message, '' without messages
}

namespace Symfony\AI\Agent\Exception;

final class ConflictException extends RuntimeException
{
    public static function forMessages(MessageBag $messages, ?\Throwable $previous = null): self;
}
```

A conversation is a `MessageBag` with a time-based id (`Uuid::v7()`, `Ulid`): build it with `MessageBag::forId($id, ...$messages)` (strings become user messages) or `$bag->withId($id)`, both from `symfony/ai-platform`. `Agent` uses the id as given; resolving it from the current user, and checking that this user may continue that conversation, is the application's job.

A custom backend implements `MessageStoreInterface`; its `save()` must throw `ConflictException` when the stored conversation does not continue in the given messages, which `ConflictDetector::assertContinues()` checks. Storing `ConflictDetector::version()` next to the conversation and updating only where the version is unchanged makes the check atomic, as the Doctrine DBAL, MongoDB and SurrealDB bridges do.

The `ai:message-store:setup <store>` and `ai:message-store:drop <store> --force` commands (`Command\SetupMessageStoreCommand`, `Command\DropMessageStoreCommand`) take a `ServiceProviderInterface` of stores; in the AI bundle it is keyed by service id (`ai.message_store.<type>.<name>`, `ai.message_store.doctrine.dbal.<name>` for Doctrine). Their errors: `The "…" message store does not exist.`, `The "…" message store does not support setup.` / `does not support to be dropped.` (the store is not a `ManagedMessageStoreInterface`), `No supported options.` (`InvalidArgumentException`, from a store whose `setup()` takes none).

`Toolbox\Source\SourceCollectionNormalizer` serializes the `sources` metadata of an answer; the default serializer of every bridge combines it with `Platform\Serializer\MessageBagNormalizer`. The nine bridges and their constructors are in `references/bridges.md`.

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
    public function call(string|MessageBag|UserMessage $input, array $options = []): ExecutionInterface;
}

final class Handoff
{
    /** @param string[] $when */
    public function __construct(private readonly AgentInterface $to, private readonly array $when);
    public function getTo(): AgentInterface;
    /** @return string[] */
    public function getWhen(): array;
}

namespace Symfony\AI\Agent\MultiAgent\Handoff;

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

Since 0.14 `MultiAgent` (and `SpeechAgent`) forward the `Update\Progress` updates of the executions they delegate to, so iterating a `MultiAgent` execution shows the chosen agent's model requests and tool calls. The routing itself is reported as a `Progress` with stage `handoff`, whose `getPayload()` is the `Decision`.

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

    public function call(string|MessageBag|UserMessage $input, array $options = []): ExecutionInterface;
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
```

## Testing & observability agents

```php
namespace Symfony\AI\Agent;

final class MockAgent implements AgentInterface
{
    /** @param array<string, string|MockResponse|StreamResult|\Closure> $responses */
    public function __construct(array $responses = [], string $name = 'mock');
    public function call(string|MessageBag|UserMessage $input, array $options = []): ExecutionInterface;
    public function addResponse(string $input, string|MockResponse|\Closure $response): self;
    public function clearResponses(): self;
    public function getResponses(): array;
    public function getCallCount(): int;
    public function getCalls(): array;
    public function getCall(int $index): array;
    public function getLastCall(): array;
    public function assertCallCount(int $expectedCount): void;
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
        private readonly ?Stopwatch $stopwatch = null,   // since 0.14: times each execution's consumption
    );

    public function call(string|MessageBag|UserMessage $input, array $options = []): ExecutionInterface;
    public function getName(): string;
    /** @return AgentData[] */
    public function getCalls(): array;
    public function reset(): void;
}
```

## Tool-call lifecycle events

`Toolbox::execute()` dispatches the request event before argument resolution; argument resolution is then attempted via `ToolCallArgumentResolverInterface::resolveArguments()`, and on successful resolution the `ToolCallArgumentsResolved` event is dispatched before invocation runs. Any throwable : resolution or invocation : dispatches `ToolCallFailed`. `Agent`'s internal `Runner` dispatches the batch event after each batch of calls.

| Event                       | Constructor                                                                            | Public methods                                                                                                                                                                                                                                                     | Role                                                                                                                                                                                               |
| --------------------------- | -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ToolCallRequested`         | `__construct(ToolCall $toolCall, Tool $definition)`                                    | `getToolCall(): ToolCall`, `getDefinition(): Tool`, `deny(?string $reason = null): void`, `isDenied(): bool`, `getDenialReason(): ?string`, `setResult(ToolResult $result): void`, `hasResult(): bool`, `getResult(): ?ToolResult`, `isPropagationStopped(): bool` | Pre-execution gate. `deny()` refuses execution; `setResult()` substitutes a result and skips execution.                                                                                            |
| `ToolCallArgumentsResolved` | `__construct(object $tool, Tool $definition, array $arguments)`                        | `getTool(): object`, `getDefinition(): Tool`, `getArguments(): array`                                                                                                                                                                                              | Post-denormalization inspection/validation, immediately before invocation.                                                                                                                         |
| `ToolCallSucceeded`         | `__construct(object $tool, Tool $definition, array $arguments, ToolResult $result)`    | `getTool(): object`, `getDefinition(): Tool`, `getArguments(): array`, `getResult(): ToolResult`                                                                                                                                                                   | Published after the tool returns successfully.                                                                                                                                                     |
| `ToolCallFailed`            | `__construct(object $tool, Tool $definition, array $arguments, \Throwable $exception)` | `getTool(): object`, `getDefinition(): Tool`, `getArguments(): array`, `getException(): \Throwable`                                                                                                                                                                | Published when argument resolution or tool invocation fails. `getArguments()` may return an empty array when the failure occurs before resolution completes (`Toolbox` passes `$arguments ?? []`). |
| `ToolCallsExecuted`         | `__construct(array $toolResults)`                                                      | `getToolResults(): array`, `hasResult(): bool`, `setResult(ResultInterface $result): void`, `getResult(): ResultInterface`                                                                                                                                         | Batch hook after execution; `setResult()` can replace the next agent result.                                                                                                                       |

`#[IsGrantedTool]` is Symfony authorization applied to a tool. It is distinct from the runtime `ToolCallRequested::deny()`, which is an event-listener decision for one call. `ToolCallRequested::setResult()` is result substitution without execution. Use `ToolCallArgumentsResolved` when validating the denormalized, typed arguments; the request event still sees the original `ToolCall` payload.

The event dispatcher is optional in both `Toolbox` and `Agent`; to observe one complete lifecycle, pass the same dispatcher instance to both constructors.
