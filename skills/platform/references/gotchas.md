# Platform : Gotchas

The exhaustive version of the gotchas in `SKILL.md`. Read this when the user
hits a specific failure mode.

## 1. `TokenUsage` is `final`, fields are `private readonly ?int`

`Symfony\AI\Platform\TokenUsage\TokenUsage` is `final`. The eleven fields
(`promptTokens`, `completionTokens`, `thinkingTokens`, `toolTokens`,
`cachedTokens`, `cacheCreationTokens`, `cacheReadTokens`, `remainingTokens`,
`remainingTokensMinute`, `remainingTokensMonth`, `totalTokens`) are all
`private readonly ?int`. **No public properties, no public setters.** Use the
getters (`getPromptTokens(): ?int` etc.). All getters return `?int` : a
provider that does not report a given counter returns `null`, not `0`.

`TokenUsageInterface` is the right type to type-hint against when accepting
either a single `TokenUsage` or a `TokenUsageAggregation` (sums numeric
fields, min()es `remaining*`).

## 2. `FinishReason` is a `final class`, not an enum : and cases differ

```text
final class FinishReason implements \JsonSerializable, \Stringable
{
    public function __construct(FinishReasonCase $case, string $raw);
}
```

Cases in the source (`Symfony\AI\Platform\FinishReason\FinishReasonCase`):

| Case                | Value             | Meaning                                       |
|---------------------|-------------------|-----------------------------------------------|
| `STOP`              | `'stop'`          | model finished on its own                     |
| `LENGTH`            | `'length'`        | output truncated by max tokens                |
| `TOOL_CALL`         | `'tool-call'`     | stopped to call one or more tools (singular!) |
| `CONTENT_FILTER`    | `'content-filter'`| refused by safety filter / guardrail          |
| `STOP_SEQUENCE`     | `'stop-sequence'` | hit a caller-supplied stop sequence           |
| `OTHER`             | `'other'`         | provider reported something unmapped          |

There is **no** `ERROR` case. Provider errors are exceptions
(`ServerException`, `RateLimitExceededException`, …), not finish reasons.

Access via `$result->getMetadata()->get('finish_reason')` : the bridge
normalises the provider's wording. Inspect `FinishReason::getRaw()` to see
the original string. Compare via `FinishReason::is(FinishReasonCase::LENGTH)`.

## 3. `Vector` has no public fields

```text
final class Vector implements VectorInterface
{
    public function __construct(array $data, ?int $dimensions = null);
    public function getData(): array;      // list<float>
    public function getDimensions(): int;
}
```

`$data` must be non-empty (`InvalidArgumentException` otherwise).
`$dimensions` must match `count($data)` when supplied. Use `NullVector` if
you need a stand-in for an empty embedding.

## 4. `ResultInterface` has only three methods : not `asText()`

```php
interface ResultInterface extends MetadataAwareInterface
{
    public function getContent(): string|iterable|object|null;
    public function getRawResult(): ?RawResultInterface;
    public function setRawResult(RawResultInterface $rawResult): void;
}
```

All `asText()`, `asObject()`, `asVectors()`, `asToolCalls()`, `asStream()`
etc. live on `DeferredResult`. Reading `$result->getContent()` directly is
fine if you want to introspect, but to get a typed value go through
`DeferredResult` and its accessors. There is **no** `asVector()` (singular) :
use `asVectors()[0]`.

## 5. Streaming requires `'stream' => true`

There is no `Platform::stream()` method. Opt in via `$options['stream']`,
then iterate `$result->asStream()`. The shared underlying `\Generator` is
driven exactly once across `asStream()`, `asStreamedObject()`, and
`asObject()` : calling `asObject()` after a partial `asStreamedObject()`
will pump the remainder. If a stream ends without a terminal event, bridges
raise `IncompleteStreamException`.

## 6. `CachePlatform` only kicks in with `prompt_cache_key`

`symfony/ai-cache-platform` is a separate package. `CachePlatform`
short-circuits to a pass-through when:

```text
null === $cache
|| !array_key_exists('prompt_cache_key', $options)
|| '' === $options['prompt_cache_key']
```

Set both `options['prompt_cache_key']` and (optionally)
`options['prompt_cache_ttl']` to activate caching. Without
`prompt_cache_key`, every call hits the underlying platform.

`CachePlatform::__construct()` defaults to a built-in Symfony Serializer
but you can pass your own `(SerializerInterface&NormalizerInterface&DenormalizerInterface)`.

## 7. `FailoverPlatform` requires a `RateLimiterFactoryInterface`

The decorator lives in `symfony/ai-failover-platform` (separate package,
**not** bundled with `symfony/ai-platform`).

```text
final class FailoverPlatform implements PlatformInterface
{
    public function __construct(
        iterable $platforms,
        RateLimiterFactoryInterface $rateLimiterFactory,
        ClockInterface $clock = new MonotonicClock(),
        LoggerInterface $logger = new NullLogger(),
    );
}
```

It throws `InvalidArgumentException` if `$platforms` is empty and a generic
`RuntimeException('All platforms failed.')` when every platform throws.
Each platform needs its own model identifier : there is no
model-name translation between providers.

## 8. There is no `RetryPlatform` bridge

The current code has no `Bridge/Retry/RetryPlatform` : it was removed (do
not look for it). For retry behaviour use:

- `FailoverPlatform` for cross-provider failover on any throwable.
- Symfony HttpClient retry plugin (or your own loop) for same-platform
  retries of transient HTTP errors.
- The platform's own `ClockInterface` and `RateLimiterFactoryInterface` to
  bound the retry budget.

## 9. Message factory: `forSystem`, not `ofSystem`

The named constructors in `Symfony\AI\Platform\Message\Message` are:

| Method                          | Returns          |
|---------------------------------|------------------|
| `Message::forSystem(...)`       | `SystemMessage`  |
| `Message::ofUser(...)`          | `UserMessage`    |
| `Message::ofAssistant(...)`     | `AssistantMessage`|
| `Message::ofToolCall(...)`      | `ToolCallMessage`|

There is **no** `Message::ofSystem` and **no** `Message::ofToolResult` :
tool-call responses are modelled as `ToolCallMessage` carrying the
`ToolCall` plus the response content parts.

## 10. Multimodal content blocks

- `Image`, `Audio`, `Video`, `Document` all extend `File` and inherit
  `File::fromFile()` and `File::fromDataUrl()`.
- `Image::fromUrl()` does **not** exist. Use `ImageUrl(string $url)` for
  remote URLs (some providers do not fetch URLs : Anthropic notably
  requires base64).
- `Image::fromBinary()` does **not** exist. Build the `Image` (or any
  `File` subclass) with `new File(string|\Closure $data, string $format, ?string $path = null)`.
  `$format` **is** the MIME type: `File::fromFile()` fills it with
  `mime_content_type($path)` and `File::fromDataUrl()` with the substring
  between `data:` and `;base64,` (`File.php:55-64`). Pass `'image/png'`.
- Provider size limits differ (OpenAI 20 MB images, Anthropic 5 MB,
  Gemini 20 MB), but **nothing in `src/platform/` enforces them**. There is
  no local size check: an oversized file is sent and the provider's API
  rejects it, surfacing as an HTTP error, not as a local
  `InvalidArgumentException`.

## 11. Tool-call ID access

`Result\ToolCall` carries `id`, `name`, `arguments`, and a provider-scoped
`signature` (only Google Gemini / Vertex AI emit signatures on function
call parts). The id is needed when replying with
`Message::ofToolCall($call, ...)`. To get them all in one shot use
`DeferredResult::asToolCalls(): ToolCall[]`. If the bridge emits parallel
tool calls as a `MultiPartResult` with one `ToolCallResult` part per call,
use `MultiPartResult::asToolCallResult()` to flatten.

## 12. The actual exception catalogue

All exceptions under `Symfony\AI\Platform\Exception\`:

| Exception                       | Notes                                               |
|---------------------------------|------------------------------------------------------|
| `ExceptionInterface`            | marker for everything below                         |
| `RuntimeException`              | platform base, extends `\RuntimeException`           |
| `LogicException`                | final, extends `\LogicException`                     |
| `InvalidArgumentException`      | extends `\InvalidArgumentException`                  |
| `InvalidRequestException`       | extends `InvalidArgumentException`                   |
| `IOException`                   | extends `RuntimeException`                           |
| `ModelNotFoundException`        | extends `\InvalidArgumentException` **and implements `ExceptionInterface`** |
| `AuthenticationException`       | HTTP 401                                            |
| `BadRequestException`           | HTTP 4xx (not 401/403/429)                           |
| `ContentFilterException`        | extends `InvalidArgumentException`                   |
| `ExceedContextSizeException`    | extends `InvalidArgumentException`                   |
| `IncompleteStreamException`     | provider stream ended without terminal event : retry |
| `MaxOutputTokensException`      | output hit the token ceiling : surface, don't retry  |
| `MalformedToolCallException`    | provider returned malformed tool-call JSON           |
| `MissingModelSupportException`  | final, has `forToolCalling()`, `forAudioInput()`, `forImageInput()`, `forStructuredOutput()` |
| `RateLimitExceededException`    | final, `getRetryAfter(): ?int`                       |
| `ServerException`               | NOT final (subclassable); HTTP 5xx or mid-stream server error : `getStatusCode(): ?int` |
| `UnexpectedResultTypeException` | `as*()` typed accessor saw the wrong subtype         |
| `ValidationException`           | final, structured-output Validator raised violations; `getViolations(): object` (returns the wrapped `ConstraintViolationListInterface` but the public signature is `: object`) |

Names that **do not exist** in this codebase (hallucinated in the previous
skill revision): `UnsupportedModelOperationException`,
`ResultTypeMismatchException`, `StreamUnsupportedException`,
`MissingPropertyException`, `TypeMismatchException`.

## 13. `template_vars` edge case

`Template::string('Hello {name}')` is **not rendered** unless
`template_vars` is passed in `$options`:

```php
// Wrong — leaves literal `{name}` in prompt
$platform->invoke($model, new MessageBag(Message::ofUser(Template::string('Hello {name}'))));

// Right
$platform->invoke(
    $model,
    new MessageBag(Message::ofUser(Template::string('Hello {name}'))),
    ['template_vars' => ['name' => 'Alice']],
);
```

Templates work with most bridges but not all (some local Ollama builds
ignore them).

## 14. Bridge factories need API keys at construction time

There is no `Factory::create()` anywhere — the OpenAI factory exposes
`createPlatform()` and `createProvider()`, and the other bridges follow the
same naming. The key check lives one level down, in
`Bridge\OpenAi\RegionAwareTrait::validateApiKey()`, called by each
`ModelClient` constructor: it rejects an empty string, and rejects any key
not starting with `sk-`. If you need lazy key resolution, defer construction
until first call (Symfony service factories support this) or wrap the factory
call in a service.

## 15. PII / request logging

`Platform::invoke()` does not log message bodies. The Symfony HttpClient
may log request bodies if you enable that channel. **Disable the
`symfony.http_client` Monolog channel in production** : prompts and
completions routinely contain PII.

## 16. Embedding vs completion share NO method signatures

`asText()` on a `VectorResult` throws `UnexpectedResultTypeException`. Use
`asVectors()` (note the plural). The bridge registers an embedding model
in its `ModelCatalog`; the provider returns raw vectors, the
`ResultConverter` produces a `VectorResult`. Calling the wrong typed
accessor is the most common "the model returned nothing" confusion.

## 17. Reusing Platform instances

`Platform` instances are stateless wrappers around an HTTP client. Reuse
them across requests : they are designed for connection pooling. In
Symfony, register the Platform as a service and inject it everywhere.
Don't `new Factory::createPlatform(...)` per HTTP request : that creates a
new HTTP client per request and defeats pooling.

## 18. Stream consumers and intermediate validity

`DeferredResult::asStreamedObject()` and `DeferredResult::asPartialJsonStream()`
are best-effort render helpers, not validated view models. Document this in
any business-logic review:

- `asStreamedObject()` yields progressively populated instances of the
  target class on every `PartialObjectDelta` whose recovered JSON has
  changed. The yielded objects are constructed from partial JSON and **may
  carry default / unset fields**. They are not safe to pass to your domain
  layer; only the final object : equivalent to `asObject()` : is.
- `asPartialJsonStream()` yields the largest valid JSON snapshot
  recoverable from the cumulative text buffer. A snapshot is "valid" in the
  `PartialJsonParser` sense (syntactically parseable JSON), not "complete"
  in the schema sense. Consumers must keep rendering until stream exhaustion
  and run business validation on the last yielded value, never on an
  intermediate one.
- The shared `\Generator` in `DeferredResult::$stream` is driven exactly once
  across `asStream()`, `asStreamedObject()`, and `asObject()`. Pick a
  primary accessor; reaching for a second one will only see the remaining
  deltas. `DeferredResult::asObject()` will pump the remainder if
  `asStreamedObject()` stopped early, but the intermediate yields you saw
  before the stop are not replayable.
- Metadata is **not** complete before the stream is exhausted.
  `Symfony\AI\Platform\Metadata\StreamListener` and
  `Symfony\AI\Platform\TokenUsage\StreamListener` push deltas as
  they arrive, and the `finally` blocks in `asStream()` /
  `asTextStream()` / `asStreamedObject()` flush the aggregated metadata
  into `DeferredResult::$metadata` only after iteration ends. Do not branch
  on `$result->getMetadata()->get('finish_reason')` mid-stream.

## 19. `FailoverPlatform` does not retry, map models, or resume streams

The decorator iterates platforms in order, consumes one rate-limit token per
attempt, and on any `\Throwable` records the platform as failed (via a
`\WeakMap`) and moves on. Read the actual `FailoverPlatform.php` before
relying on any feature beyond that.

- **Same model argument is forwarded verbatim.** `'gpt-4o-mini'` is passed
  to every underlying platform, including a Claude or Gemini one. There is
  no model-name mapping. Wrap each platform with its own `Model` object if
  you want per-provider model names.
- **No option translation.** `$options` is forwarded as-is. Provider
  options differ (`response_format` vs `tools` keys are not uniform across
  bridges). A wrong option key for one provider surfaces as a bridge-level
  exception, not as a normalised error.
- **No universal retry / backoff.** A failure on platform A moves directly
  to platform B; there is no per-call retry, no exponential delay, no
  jitter. There is no `RetryPlatform` bridge : it has been removed (see
  gotcha #8).
- **No circuit breaker.** The `\WeakMap` records failures but does not
  open / half-open / close like a circuit breaker. The only gating is the
  `RateLimiterFactoryInterface` you inject; a saturated limiter is the
  closest analogue.
- **No stream-resume guarantee.** The shared `\Generator` inside
  `DeferredResult` is single-shot. A mid-stream failure on one platform
  starts a brand new invocation on the next; deltas already yielded are
  not replayed. If you need resumable streaming, buffer at the application
  layer.
- After every platform fails, `FailoverPlatform` throws a bare
  `RuntimeException('All platforms failed.')` constructed without a
  previous throwable; the original failures are reachable only via
  `$logger` output from per-platform attempts. Catch this and inspect the
  `LoggerInterface` you passed in (it only logs per-platform throwables;
  the final "All platforms failed." carries nothing).

## 20. Capability guards: exact cases, no invention

`Capability` is a string-backed enum at
`Symfony\AI\Platform\Capability`. `Model::supports()` returns `bool` via
`Capability::equalsOneOf()`. Only the cases enumerated in `Capability.php`
exist : do not invent a case for a capability you "expect" to be there.

Cases most relevant to the `DeferredResult` surface:

- `Capability::OUTPUT_STRUCTURED` : gates
  `options['response_format']`; the `StructuredOutput\PlatformSubscriber`
  throws `MissingModelSupportException::forStructuredOutput($model)` if the
  model lacks it.
- `Capability::OUTPUT_STREAMING` : model advertises SSE / chunked deltas.
  Not centrally guarded; check `Model::supports()` before passing
  `'stream' => true` or calling `asTextStream()` /
  `asStreamedObject()`.
- `Capability::TOOL_CALLING` : model accepts `Tool[]` in
  `options['tools']`. Not centrally guarded; check before adding tools.

Capability names that **do not exist** in this codebase (do not invent):
`STREAMING` (use `OUTPUT_STREAMING`), `STRUCTURED_OUTPUT` (use
`OUTPUT_STRUCTURED`), `FUNCTION_CALLING` (use `TOOL_CALLING`),
`TEXT_COMPLETION`, `CHAT`. The complete list is the enum body in
`https://github.com/symfony/ai/tree/main/src/platform/src/Capability.php`.
