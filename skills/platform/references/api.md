# Platform : API Reference

Strict source-of-truth dump of the namespaces and method signatures that exist
under `https://github.com/symfony/ai/tree/main/src/platform/src/`. Anything not in this tree
is not documented here.

## Contents

- Core namespaces
- `PlatformInterface`
- `Platform` (concrete)
- `Provider` (one inference backend)
- `DeferredResult` (the real one)
- Asynchronous jobs (`Job\`)
- Batches (`BatchResult`)
- `Result\Stream\ListenerInterface`
- `TokenUsage`
- `FinishReason` (final class wrapping an enum)
- `Vector`
- `Message` named constructors
- `MessageBag`
- Content parts
- `Tool` (raw Platform : not Agent)
- `Model`
- `Contract`
- `TraceablePlatform`
- Bridge factory pattern

## Core namespaces

```php
Symfony\AI\Platform\
├── Capability                      (enum: INPUT_*, OUTPUT_*, TOOL_CALLING, EMBEDDINGS, …)
├── Contract                        (Symfony Serializer normalizers wired together)
├── JsonBodyEncodingTrait
├── Model                           (name + Capability[] + default options)
├── ModelClientInterface            (transport + request)
├── ModelRouterInterface
├── Platform                        (concrete; routes via ModelRouter)
├── PlatformInterface               (invoke, getModelCatalog)
├── PlainConverter
├── Provider                        (concrete; one inference backend)
├── ProviderInterface
├── ResultConverterInterface
├── TraceablePlatform               (decorator; records calls)
├── Bridge\…                        (43 bridge packages — see bridges.md)
│
├── Event\                          (InvocationEvent, ResultEvent, …)
├── EventListener\                  (StringToMessageBagListener, TemplateRendererListener)
├── Exception\                      (18 exceptions + ExceptionInterface — see gotchas.md)
├── FinishReason\                   (FinishReason class + FinishReasonCase enum)
├── Job\                            (JobHandle, JobRunner, JobClientInterface, JobStatus,
│                                   JobStateCase — asynchronous provider jobs, since 0.14)
├── Message\
│   ├── Message                     (named constructors)
│   ├── MessageBag                  (mutable + immutable helpers)
│   ├── MessageInterface
│   ├── Role                        (enum: System, Assistant, User, ToolCall)
│   ├── SystemMessage
│   ├── UserMessage
│   ├── AssistantMessage
│   ├── ToolCallMessage
│   ├── Template                    (string or expression renderer)
│   ├── TemplateRenderer\
│   └── Content\                    (Text, File, Image, ImageUrl, Audio, Video, Document, DocumentUrl, Collection, plus response-content helpers)
├── Metadata\                       (Metadata, MetadataAwareTrait, MergeableMetadataInterface)
├── ModelCatalog\                   (ModelCatalogInterface + AbstractModelCatalog, CompositeModelCatalog, FallbackModelCatalog, MockModelCatalog)
├── ModelRouter\                    (CatalogBasedModelRouter, RoutingDecision)
├── Reranking\RerankingEntry
├── Result\
│   ├── ResultInterface             (getContent, getRawResult, setRawResult)
│   ├── DeferredResult              (asText, asObject, asStream, …)
│   ├── BaseResult
│   ├── TextResult, ObjectResult, BinaryResult, VectorResult, StreamResult,
│   │   ToolCallResult, RerankingResult, ChoiceResult, MultiPartResult,
│   │   ThinkingResult, InMemoryRawResult, RawResultInterface, RawHttpResult,
│   │   + ResultCode executors (CodeExecutionResult, ComputerCallResult,
│   │     ExecutableCodeResult, FileSearchResult, LocalShellCallResult,
│   │     McpCallResult, McpApprovalRequestResult, McpListToolsResult,
│   │     WebSearchResult)
│   ├── JobResult, BatchResult, BatchItem, BatchItemCase, RealtimeSessionResult  (0.14)
│   ├── Stream\                     (NdjsonStream, RawSseStream, SseStream, ListenerInterface,
│   │   StartEvent, DeltaEvent, CompleteEvent, ErrorEvent, AbstractStreamListener, HttpStreamInterface)
│   ├── Stream\Delta\               (TextDelta, PartialObjectDelta, ToolInputDelta,
│   │   ToolCallStart, ToolCallComplete, BinaryDelta, ChoiceDelta, MetadataDelta,
│   │   ThinkingStart, ThinkingDelta, ThinkingComplete, ThinkingSignature, DeltaInterface)
│   ├── Exception\RawResultAlreadySetException
│   ├── InMemoryRawResult, RawHttpResult, HttpStatusErrorHandlingTrait,
│   │   RawResultAwareTrait
├── StructuredOutput\               (PlatformSubscriber, ResponseFormatFactory,
│   ├── Validator\                  (ValidatorSubscriber, ValidatorResultConverter)
│   └── Streaming\                  (PartialJsonParser, PartialObjectStreamListener)
├── Test\                           (InMemoryPlatform, MockModelCatalog, MockModelClient,
│                                   MockPlatformFactory, MockResultConverter,
│                                   ModelCatalogTestCase, ScriptedResponse)
├── TokenUsage\                     (TokenUsage, TokenUsageInterface, TokenUsageAggregation,
│                                   StreamListener, TokenUsageExtractorInterface)
├── Tool\                           (Tool, ExecutionReference)
└── Vector\                         (Vector, VectorInterface, NullVector)
```

## `PlatformInterface`

```php
namespace Symfony\AI\Platform;

interface PlatformInterface
{
    /**
     * @param non-empty-string|Model     $model
     * @param array<mixed>|string|object $input   MessageBag OR raw string OR array
     * @param array<string, mixed>       $options tools, response_format, stream, prompt_cache_key, …
     */
    public function invoke(string|Model $model, array|string|object $input, array $options = []): DeferredResult;

    public function getModelCatalog(): ModelCatalogInterface;
}
```

The second argument is intentionally permissive, and `Contract` normalises
`MessageBag`, single messages, raw arrays, and serializable objects alike.

`StringToMessageBagListener` upcasts a bare `string` into a `MessageBag` holding
one `UserMessage`, but it is **not** intrinsic to `invoke()`: it is an event
listener on `InvocationEvent`, so it runs only when a dispatcher was passed to
`Platform` (third constructor argument, `null` by default) *and* the listener is
registered on it. In the monorepo, only `ai-bundle` does that
(service `ai.platform.string_to_message_bag_listener` in `config/services.php`). Standalone snippets built with
`Factory::createPlatform($apiKey)` pass no dispatcher and get no upcasting.

## `Platform` (concrete)

```php
final class Platform implements PlatformInterface
{
    /**
     * @param ProviderInterface[] $providers
     */
    public function __construct(
        array $providers,
        ModelRouterInterface $modelRouter = new CatalogBasedModelRouter(),
        ?EventDispatcherInterface $eventDispatcher = null,
    );

    public function invoke(string|Model $model, array|string|object $input, array $options = []): DeferredResult;
    public function getModelCatalog(): ModelCatalogInterface;
}
```

`Platform` throws `InvalidArgumentException` if `$providers` is empty.

## `Provider` (one inference backend)

```php
final class Provider implements ProviderInterface
{
    /**
     * @param iterable<ModelClientInterface>     $modelClients
     * @param iterable<ResultConverterInterface> $resultConverters
     */
    public function __construct(
        string $name,
        iterable $modelClients,
        iterable $resultConverters,
        ModelCatalogInterface $modelCatalog,
        ?Contract $contract = null,
        ?EventDispatcherInterface $eventDispatcher = null,
    );

    public function getName(): string;
    public function supports(string|Model $model): bool;
    public function invoke(string|Model $model, array|string|object $input, array $options = []): DeferredResult;
    public function getModelCatalog(): ModelCatalogInterface;
}
```

## `DeferredResult` (the real one)

`final class DeferredResult` lives at
`Symfony\AI\Platform\Result\DeferredResult`. All `as*()` accessors live here :
not on `ResultInterface`.

```php
final class DeferredResult
{
    public function __construct(
        ResultConverterInterface $resultConverter,
        RawResultInterface $rawResult,
        array $options = [],
    );

    // Conversion lifecycle
    public function getResult(): ResultInterface;
    public function getResultConverter(): ResultConverterInterface;
    public function getRawResult(): RawResultInterface;
    public function onConvert(\Closure(ResultInterface): ResultInterface $cb): void;
    public function onError(\Closure(\Throwable): void $cb): void;

    // Asynchronous job (JobResult) — see "Asynchronous jobs" below
    public function asJob(): JobHandle;

    // Typed accessors — each throws UnexpectedResultTypeException on mismatch
    public function asText(): string;
    public function asObject(): object;
    public function asBinary(): string;
    public function asFile(string $path): void;
    public function asDataUri(?string $mimeType = null): string;

    /** @return ResultInterface[] parts of a MultiPartResult */
    public function asMultiPart(): array;

    /** @return iterable<BatchItem> */
    public function asBatch(): iterable;

    /** @return Vector[] */
    public function asVectors(): array;

    /** @return list<RerankingEntry> */
    public function asReranking(): array;

    /** @return ToolCall[] */
    public function asToolCalls(): array;

    /** @return \Generator<DeltaInterface> */
    public function asStream(): \Generator;

    /** @return \Generator<TextDelta> */
    public function asTextStream(): \Generator;

    /** @return \Generator<object> progressively populated typed objects */
    public function asStreamedObject(): \Generator;

    /** @return \Generator<mixed> largest valid JSON snapshot recoverable so far */
    public function asPartialJsonStream(): \Generator;
}
```

The underlying `ResultInterface` is intentionally minimal:

```php
interface ResultInterface extends MetadataAwareInterface
{
    public function getContent(): string|iterable|object|null;
    public function getRawResult(): ?RawResultInterface;
    public function setRawResult(RawResultInterface $rawResult): void;
}
```

There is no `asText()` / `asObject()` on the interface : those are on
`DeferredResult`. Concrete result types you will see after conversion:

| Concrete result        | `getContent()` returns                       |
|------------------------|----------------------------------------------|
| `TextResult`           | `string` (+ optional `getSignature()`)       |
| `ObjectResult`         | `object\|array<string, mixed>`               |
| `BinaryResult`         | `string` (+ `getMimeType()`, `toDataUri()`, `asFile()`) |
| `VectorResult`         | `Vector[]`                                   |
| `RerankingResult`      | `list<RerankingEntry>`                       |
| `ToolCallResult`       | `ToolCall[]` (constructor rejects empty list)|
| `StreamResult`         | `\Generator<DeltaInterface>` (via `getContent()`) |
| `ChoiceResult`         | `ResultInterface[]` (≥ 2 required)           |
| `MultiPartResult`      | non-empty `ResultInterface[]`, iterable      |
| `ThinkingResult`       | `?string` (text content only, nullable)      |
| `JobResult`            | `Job\JobHandle` (read it with `asJob()`)     |
| `BatchResult`          | `iterable<BatchItem>` (read it with `asBatch()`) |
| `RealtimeSessionResult`| `array` (+ `getId()`, `getClientSecret()`, `getExpiresAt()`, `getModel()`, `getVoice()`, `getModalities()`) |
| `WebSearchResult`      | `?string` (+ `getQuery()`, `getQueries()`, `getId()`, `getStatus()`) |

`RealtimeSessionResult` is returned for models with `Capability::REALTIME_SESSION`
(OpenAI `gpt-realtime`): the platform creates the session server side and hands
back an **ephemeral client secret** for a browser/mobile client to open the
WebRTC/WebSocket connection itself. Never log `getClientSecret()`.

## Asynchronous jobs (`Job\`)

Since 0.14, a provider that answers with a job identifier instead of a result
(video/image generation, async speech, batches, every Replicate prediction)
returns a `Result\JobResult`. **The platform never waits**: read the handle with
`asJob()` and resolve it explicitly. Calling `asText()` / `asBinary()` /
`asFile()` on it throws `UnexpectedResultTypeException`.

```php
namespace Symfony\AI\Platform\Job;

final class JobHandle implements \JsonSerializable   // serializable: store it, send it via Messenger
{
    public function __construct(string $id, array $data = [], ?string $provider = null,
        ?int $maxDuration = null, ?float $pollInterval = null);
    public function getId(): string;
    public function getProvider(): ?string;          // set by the bridge that started the job
    public function getMaxDuration(): ?int;          // how long this kind of job may take (s)
    public function getPollInterval(): ?float;       // how often it is worth polling (s)
    public function toString(): string;
    public static function fromString(string $handle): self;
    public function toArray(): array;
    public static function fromArray(array $handle): self;
}

interface JobClientInterface
{
    public function supports(JobHandle $handle): bool;
    public function getStatus(JobHandle $handle): JobStatus;
    public function getResult(JobHandle $handle): ResultInterface;
}

final class JobStatus implements \JsonSerializable, \Stringable
{
    public function getCase(): JobStateCase;
    public function getRaw(): string;               // provider's own status string
    public function getError(): ?string;
    public function is(JobStateCase ...$cases): bool;
    public function isTerminal(): bool;
}

enum JobStateCase: string
{
    case QUEUED = 'queued';
    case RUNNING = 'running';
    case SUCCEEDED = 'succeeded';
    case FAILED = 'failed';
    case EXPIRED = 'expired';
    case CANCELED = 'canceled';
    case UNKNOWN = 'unknown';
}

final class JobRunner
{
    public function __construct(ClockInterface $clock = new MonotonicClock(),
        ?float $pollInterval = null, ?int $maxDuration = null, ?int $maxPolls = null);

    // Polls until SUCCEEDED, returns a DeferredResult with the usual as*() accessors
    public function wait(JobClientInterface $jobClient, JobHandle $handle,
        ?int $maxDuration = null, ?float $pollInterval = null, ?int $maxPolls = null): DeferredResult;
}
```

Job clients come from the bridge factory (`Factory::createJobClient($apiKey, $httpClient)`):
`MiniMax`, `Replicate`, `OpenAi` (batches), `EdenAi`, `Higgsfield`, `Venice`.

```php
use Symfony\AI\Platform\Bridge\Replicate\Factory;
use Symfony\AI\Platform\Job\JobRunner;

$platform = Factory::createPlatform($apiKey);
$handle = $platform->invoke('llama-3-8b-instruct', $messages)->asJob();

$result = (new JobRunner())->wait(Factory::createJobClient($apiKey), $handle);
echo $result->asText();
```

- Timing precedence: `wait()` argument → `JobRunner` constructor → handle hint → default (120 s budget).
- `wait()` throws `Exception\JobFailedException` when the job ends FAILED/EXPIRED/CANCELED,
  `Exception\JobTimeoutException` when the duration or `maxPolls` budget runs out
  (the job may still be running : keep the handle and wait again later), and
  `InvalidArgumentException` when the client does not `supports()` the handle.
- Long jobs belong in a worker: persist `$handle->toString()`, rebuild with
  `JobHandle::fromString()`, check `$jobClient->getStatus($handle)`, then `wait()`.
  In a Symfony app, `ai-bundle` registers `ai.platform.job_runner` (autowired as
  `JobRunner`) and one `ai.platform.job_client.<platform>` per async-capable platform.

## Batches (`BatchResult`)

The OpenAI bridge submits a batch when `$input` is an array of inputs keyed by id
and `['batch' => true]` is passed. It returns a job; the job client exposes
`getProgress($handle)` (`status`, `completed`, `total`, `failed`) and its result
is a `BatchResult`:

```php
$handle = $platform->invoke('gpt-4o-mini', ['q1' => $bag1, 'q2' => $bag2], ['batch' => true])->asJob();

// OpenAI may take up to 24 h: persist $handle->toString() and resume in a worker.
$jobClient = OpenAi\Factory::createJobClient($apiKey);
if ($jobClient->getStatus($handle)->isTerminal()) {
    foreach ($jobClient->getResult($handle)->getContent() as $item) {   // BatchResult
        echo $item->getId(), ': ', $item->isSuccess() ? $item->getResult()->getContent() : $item->getError();
    }
}
```

`JobRunner::wait()` works too and returns a `DeferredResult` whose `asBatch()`
yields the items : only use it when the batch is known to be (almost) done.

`BatchItem`: `getId()`, `getCase(): BatchItemCase` (`SUCCEEDED`, `ERRORED`,
`CANCELED`, `EXPIRED`, `UNKNOWN`), `is(...)`, `isSuccess()`, `getResult()`
(the result the request would have produced synchronously), `getError()`,
`getRaw()`. A canceled or expired batch still yields the items it got through.

## `Result\Stream\ListenerInterface`

```php
namespace Symfony\AI\Platform\Result\Stream;

interface ListenerInterface
{
    public function onStart(StartEvent $event): void;      // once, before the first delta

    public function onDelta(DeltaEvent $event): void;       // per delta, before it reaches the consumer;
                                                              // can rewrite or skip the delta via the event

    public function onComplete(CompleteEvent $event): void; // terminal; stream drained without error

    public function onError(ErrorEvent $event): void;       // terminal; draining threw, right before rethrow
}
```

`onComplete()` and `onError()` are mutually exclusive terminal events; a stream the consumer abandons mid-iteration reaches neither. A custom listener implementing `ListenerInterface` directly (not extending `AbstractStreamListener`) must add `onError()` — it did not exist before `onComplete()`-only listeners were the whole contract. `ErrorEvent::getError(): \Throwable` exposes the exception that will be rethrown to the caller.

A finalizing side effect that must run regardless of outcome (cost accounting, quota debit, audit logging) has to be implemented in **both** `onComplete()` and `onError()` — there is no single "stream ended" hook.

The Gemini and VertexAI bridges yield a single `ToolCallComplete` delta at the end of a stream, carrying every function call of the response, instead of one per streamed `functionCall` part — a listener collecting tool calls across deltas can take the last batch instead of merging every occurrence. The exception is a multi-candidate response (`candidateCount` > 1): its deltas stay wrapped in `ChoiceDelta`, each carrying one `ToolCallComplete` per function call, without a terminal batch — a consumer walking `ChoiceDelta::getDeltas()` still has to merge those itself.

## `TokenUsage`

`final class TokenUsage` at `Symfony\AI\Platform\TokenUsage\TokenUsage`.
All eleven properties are `private readonly ?int`; you must use the getters.

```php
final class TokenUsage implements MergeableMetadataInterface, TokenUsageInterface, DeltaInterface
{
    public function __construct(
        ?int $promptTokens = null,
        ?int $completionTokens = null,
        ?int $thinkingTokens = null,
        ?int $toolTokens = null,
        ?int $cachedTokens = null,
        ?int $cacheCreationTokens = null,
        ?int $cacheReadTokens = null,
        ?int $remainingTokens = null,
        ?int $remainingTokensMinute = null,
        ?int $remainingTokensMonth = null,
        ?int $totalTokens = null,
        ?string $model = null,          // since 0.14
    );

    public function getPromptTokens(): ?int;
    public function getCompletionTokens(): ?int;
    public function getThinkingTokens(): ?int;
    public function getToolTokens(): ?int;
    public function getCachedTokens(): ?int;
    public function getCacheCreationTokens(): ?int;
    public function getCacheReadTokens(): ?int;
    public function getRemainingTokens(): ?int;
    public function getRemainingTokensMinute(): ?int;
    public function getRemainingTokensMonth(): ?int;
    public function getTotalTokens(): ?int;
    public function getModel(): ?string;   // model the provider reports as consuming the tokens
    public function merge(MergeableMetadataInterface $metadata): TokenUsageAggregation;
}
```

`TokenUsageAggregation` (also final) implements the same `TokenUsageInterface`
and sums numeric fields; `remaining*` are min()ed across sources. Use
`TokenUsageInterface` when accepting either.

`getModel()` (on `TokenUsageInterface` since 0.14) is `null` when the provider
does not name a model. `TokenUsageAggregation::getModel()` answers only when
every usage it sums agrees on one model and returns `null` otherwise : to price
a run that mixed models (chat + embeddings, say), iterate `getTokenUsages()`
and price each usage by its own `getModel()`.

## `FinishReason` (final class wrapping an enum)

`FinishReason` is **not** an enum. It is a `final class` implementing
`\JsonSerializable` and `\Stringable`, wrapping a `FinishReasonCase` plus the
raw provider string.

```php
namespace Symfony\AI\Platform\FinishReason;

final class FinishReason implements \JsonSerializable, \Stringable
{
    public function __construct(FinishReasonCase $case, string $raw);

    public function __toString(): string;          // returns $raw
    public function getCase(): FinishReasonCase;
    public function getRaw(): string;
    public function is(FinishReasonCase ...$cases): bool;
    public function jsonSerialize(): array;         // ['case' => <value>, 'raw' => <raw>]

    /** Usage in code:
     *  $finishReason = $result->getMetadata()->get('finish_reason');
     *  if ($finishReason?->is(FinishReasonCase::LENGTH)) { … }
     */
}

enum FinishReasonCase: string
{
    case STOP            = 'stop';            // model finished on its own
    case LENGTH          = 'length';          // output truncated by max tokens
    case TOOL_CALL       = 'tool-call';       // stopped to call one or more tools
    case CONTENT_FILTER  = 'content-filter';  // safety filter or guardrail
    case STOP_SEQUENCE   = 'stop-sequence';   // hit a caller-supplied stop sequence
    case OTHER           = 'other';           // provider reported something unmapped
}
```

No `ERROR` case exists; a provider error is an exception (e.g. `ServerException`,
`RateLimitExceededException`), not a `FinishReasonCase`.

## `Vector`

```php
namespace Symfony\AI\Platform\Vector;

final class Vector implements VectorInterface
{
    /**
     * @param list<float> $data
     * @throws InvalidArgumentException if $data is empty, or if $dimensions != count($data)
     */
    public function __construct(array $data, ?int $dimensions = null);

    /** @return list<float> */
    public function getData(): array;
    public function getDimensions(): int;
}
```

There is no public field access. `NullVector` (also final) exists for empty
embeddings.

## `Message` named constructors

`final class Message` (private constructor) lives at
`Symfony\AI\Platform\Message\Message`. It is the safe way to build messages :
use it instead of `new UserMessage(...)`.

```php
final class Message
{
    /** Returns SystemMessage. $content can be string | \Stringable | Template. */
    public static function forSystem(\Stringable|string|Template $content): SystemMessage;

    /** Returns UserMessage. Each arg is string | \Stringable | ContentInterface. */
    public static function ofUser(\Stringable|string|ContentInterface ...$content): UserMessage;

    /** Returns AssistantMessage. Parts can be string | ContentInterface | ResultInterface
     *  (TextResult, ThinkingResult, ToolCallResult, MultiPartResult, …). */
    public static function ofAssistant(string|ContentInterface|ResultInterface ...$parts): AssistantMessage;

    /** Returns ToolCallMessage. Extra content after the ToolCall is response text. */
    public static function ofToolCall(ToolCall $toolCall, \Stringable|string|ContentInterface ...$content): ToolCallMessage;
}
```

There is **no** `Message::ofSystem` (use `forSystem`), **no** `Message::ofToolResult`
(tool-call responses are modelled by `ToolCallMessage`, with results passed back
as content parts).

## `MessageBag`

`class MessageBag` (not final) implements `\Countable` and `\IteratorAggregate`.
It has a v7 UUID identity (`getId()`) and supports both mutable and immutable
operations.

```php
class MessageBag implements \Countable, \IteratorAggregate
{
    /** @param MessageInterface ...$messages */
    public function __construct(MessageInterface ...$messages);

    public function getId(): AbstractUid&TimeBasedUidInterface;

    // Mutable operations (in place)
    public function add(MessageInterface $message): void;
    public function prepend(MessageInterface $message): void;
    public function removeSystemMessage(): void;

    // Read-only helpers
    /** @return list<MessageInterface> */
    public function getMessages(): array;
    public function getSystemMessage(string $separator = \PHP_EOL.\PHP_EOL): ?SystemMessage;
    public function getUserMessage(): ?UserMessage;
    public function count(): int;

    // Immutable operations (return a clone)
    public function with(MessageInterface $message): self;
    public function merge(self $messageBag): self;
    public function replace(AbstractUid&TimeBasedUidInterface $uuid, MessageInterface $newMessage): self;
    public function withoutSystemMessage(): self;
    public function withoutToolMessages(): self;
    public function withSystemMessage(SystemMessage $message): self;
    public function latestAs(Role $role): MessageInterface;       // throws if no match
    public function isLastMessageFrom(Role $role): bool;
    public function containsAudio(): bool;
    public function containsImage(): bool;
}
```

`Role` is an enum: `System = 'system'`, `Assistant = 'assistant'`,
`User = 'user'`, `ToolCall = 'tool'`.

## Content parts

```php
namespace Symfony\AI\Platform\Message\Content;

final class Text           implements ContentInterface { __construct(string $text, ?string $signature = null); }
final class Image          extends File { }      // image MIME, inherited static factories
final class Audio          extends File { }
final class Video          extends File { }
final class Document       extends File { }
final class ImageUrl       implements ContentInterface { __construct(string $url); }
final class DocumentUrl    implements ContentInterface { __construct(string $url); }
final class Collection     implements ContentInterface { __construct(ContentInterface ...$content); }

class File implements ContentInterface
{
    final public function __construct(string|\Closure $data, string $format, ?string $path = null);
    public static function fromFile(string $path): static;     // reads disk
    public static function fromDataUrl(string $dataUrl): static;
    public function getFormat(): string;
    public function asBinary(): string;
    public function asBase64(): string;
    public function asDataUrl(): string;
    public function asPath(): ?string;
    /** @return resource|false */
    public function asResource();
    public function getFilename(): ?string;
}
```

`Image` inherits `File::fromFile()` and `File::fromDataUrl()` : there is **no**
`Image::fromUrl()` / `Image::fromBinary()`. For remote URLs use
`ImageUrl(string $url)` instead.

## `Tool` (raw Platform : not Agent)

```php
namespace Symfony\AI\Platform\Tool;

final class ExecutionReference
{
    public function __construct(private string $class, private string $method = '__invoke');
    public function getClass(): string;
    public function getMethod(): string;
}

final class Tool
{
    /**
     * @param JsonSchema|null      $parameters
     * @param array<string, mixed> $metadata
     */
    public function __construct(
        ExecutionReference $reference,
        string $name,
        string $description,
        ?array $parameters = null,
        array $metadata = [],
    );

    public function getReference(): ExecutionReference;
    public function getName(): string;
    public function getDescription(): string;
    /** @return JsonSchema|null */
    public function getParameters(): ?array;
    /** @return array<string, mixed> */
    public function getMetadata(): array;
    public function getMetadataValue(string $key, mixed $default = null): mixed;
}
```

There is **no** `ToolDefinition` class under `src/platform/src/Tool/`. The
schema is the `Tool` itself. The Agent component has `#[AsTool]` at
`src/agent/src/Toolbox/Attribute/AsTool.php`; only use it when you are inside
the Agent skill.

## `Model`

```php
class Model
{
    /**
     * @param non-empty-string     $name
     * @param Capability[]         $capabilities
     * @param array<string, mixed> $options  Default options merged into every invoke()
     */
    public function __construct(string $name, array $capabilities = [], array $options = []);

    public function getName(): string;
    /** @return Capability[] */
    public function getCapabilities(): array;
    public function supports(Capability $capability): bool;
    /** @return array<string, mixed> */
    public function getOptions(): array;
}
```

`Capability` is an enum covering `INPUT_*` (text, image, audio, video, pdf,
messages, multimodal, multiple), `OUTPUT_*` (text, image, audio, streaming,
structured), `TOOL_CALLING`, voice (`TEXT_TO_SPEECH`, `SPEECH_TO_TEXT` …),
image (`TEXT_TO_IMAGE`, `IMAGE_TO_IMAGE`), video (`TEXT_TO_VIDEO`,
`IMAGE_TO_VIDEO`, `VIDEO_TO_VIDEO`, `VIDEO_FRAME_TO_FRAME`, `VIDEO_WITH_SUBJECT`),
`EMBEDDINGS`, `RERANKING`, `THINKING`, `FILL_IN_THE_MIDDLE`, `MUSIC`.

## `Contract`

```php
class Contract
{
    public const CONTEXT_MODEL = 'model';
    public const CONTEXT_OPTIONS = 'options';

    final public function __construct(NormalizerInterface $normalizer);

    /** Builds a Contract pre-loaded with Message/Content/Tool normalizers. */
    public static function create(array $normalizers = []): self;

    /** @return array<string, mixed>|string */
    public function createRequestPayload(Model $model, object|array|string $input, array $options = []): string|array;

    /** @param Tool[] $tools
     *  @return array<string, mixed> */
    public function createToolOption(array $tools, Model $model): array;
}
```

The `Contract` normalises `MessageBag`, individual messages, raw arrays, and
serializable objects into the wire format the bridge's `ModelClient` expects.

## `TraceablePlatform`

```php
final class TraceablePlatform implements PlatformInterface, ResetInterface
{
    public function __construct(PlatformInterface $platform, ?Stopwatch $stopwatch = null);

    public function invoke(string|Model $model, array|string|object $input, array $options = []): DeferredResult;
    public function getModelCatalog(): ModelCatalogInterface;

    /** @return PlatformCallData[] */
    public function getCalls(): array;
    /** @return \WeakMap<ResultInterface, string> */
    public function getResultCache(): \WeakMap;

    public function reset(): void;  // clears calls and result cache
}
```

If `$options['stream']` is true, `TraceablePlatform` wraps the resulting
`StreamResult` so each `TextDelta` is accumulated into a per-result string
buffer in `getResultCache()`. With a `Stopwatch` (since 0.14) each invocation
is timed until its result is converted or its stream consumed : this is what
feeds the profiler's performance timeline. Since 0.14.1 a stream consumed
across a `reset()` keeps writing to the cache it started with.

## Bridge factory pattern

Every provider bridge exposes a `final class Factory` with static
`createProvider()` and `createPlatform()` (some bridges omit one or the other:
see `references/bridges.md`). The OpenAI shape is canonical:

```php
namespace Symfony\AI\Platform\Bridge\OpenAi;

final class Factory
{
    public const REGION_EU = 'EU';
    public const REGION_US = 'US';

    public static function createProvider(
        #[\SensitiveParameter] string $apiKey,
        ?HttpClientInterface $httpClient = null,
        ModelCatalogInterface $modelCatalog = new ModelCatalog(),
        ?Contract $contract = null,
        ?string $region = null,
        ?EventDispatcherInterface $eventDispatcher = null,
        string $name = 'openai',
    ): ProviderInterface;

    public static function createPlatform(
        #[\SensitiveParameter] string $apiKey,
        ?HttpClientInterface $httpClient = null,
        ModelCatalogInterface $modelCatalog = new ModelCatalog(),
        ?Contract $contract = null,
        ?string $region = null,
        ?EventDispatcherInterface $eventDispatcher = null,
        string $name = 'openai',
        ?ModelRouterInterface $modelRouter = null,
    ): Platform;
}
```

There is no `PlatformFactory` class : it was renamed to `Factory` in 0.12.
