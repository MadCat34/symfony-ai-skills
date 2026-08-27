# Platform : Patterns

Five patterns that compile against the source under
`https://github.com/symfony/ai/tree/main/src/platform/src/`. Each one shows the real
classes and method names; anything that does not exist in the source is
omitted.

## 1. Structured output (typed JSON via `response_format`)

There is no `StructuredOutput\Object` or `StructuredOutput\Property` class.
Structured output is configured by passing a class name (or an instance of it)
via `options['response_format']`. The `PlatformSubscriber` (an
`EventSubscriberInterface`) auto-rewires the deferred result to deserialize
JSON into that class, then hands you a typed object via
`DeferredResult::asObject()`.

```php
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;
use Symfony\AI\Platform\Message\Message;
use Symfony\AI\Platform\Message\MessageBag;

final class WeatherReport
{
    public function __construct(
        public readonly string $city,
        public readonly float $tempC,
    ) {
    }
}

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);

$result = $platform->invoke(
    'gpt-4o-mini',
    new MessageBag(Message::ofUser('Weather in Paris?')),
    ['response_format' => WeatherReport::class],
);

/** @var WeatherReport $weather */
$weather = $result->asObject();
echo $weather->city . ': ' . $weather->tempC;
```

The subscriber checks `Capability::OUTPUT_STRUCTURED` first and throws
`MissingModelSupportException::forStructuredOutput($model)` if the model
does not advertise the capability. Passing an instance populates that object
instead of creating a fresh one (`AbstractNormalizer::OBJECT_TO_POPULATE`
under the hood).

For validation, also wire `ValidatorSubscriber` (priority `-10`) so the
typed object is checked against Symfony Validator constraints before being
returned.

## 2. Tool calling from raw Platform

There is **no** `ToolDefinition` class in `src/platform/src/Tool/`. The
`Tool` final class bundles reference + name + description + JSON schema +
metadata in one. The reference is `ExecutionReference`, which points at a
class + method on the PHP side; the JSON schema is the
`Contract\Normalizer\ToolNormalizer` representation of those PHP types.

```php
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;
use Symfony\AI\Platform\FinishReason\FinishReasonCase;
use Symfony\AI\Platform\Message\Message;
use Symfony\AI\Platform\Message\MessageBag;
use Symfony\AI\Platform\Tool\ExecutionReference;
use Symfony\AI\Platform\Tool\Tool;

class Weather
{
    public function getWeather(array $args): string
    {
        return sprintf('Weather in %s: sunny, 22°C', $args['city'] ?? 'unknown');
    }
}

$tool = new Tool(
    new ExecutionReference(Weather::class, 'getWeather'),
    'get_weather',
    'Get current weather for a city.',
    [
        'type' => 'object',
        'properties' => ['city' => ['type' => 'string']],
        'required' => ['city'],
    ],
);

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);
$bag = new MessageBag(Message::ofUser("What's the weather in Paris?"));

do {
    $deferred = $platform->invoke('gpt-4o-mini', $bag, ['tools' => [$tool]]);
    $result = $deferred->getResult();

    $reason = $result->getMetadata()->get('finish_reason');

    if ($reason?->is(FinishReasonCase::TOOL_CALL)) {
        $calls = $deferred->asToolCalls();

        foreach ($calls as $call) {
            // Resolve the method on the reference class. `new $ref->getClass()`
            // is not valid PHP — the class name has to land in a variable first.
            $ref = $tool->getReference();
            $class = $ref->getClass();
            $method = $ref->getMethod();
            $output = (new $class())->$method(...$call->getArguments());

            // ofToolCall() is variadic over Stringable|string|ContentInterface.
            // A UserMessage is none of those; pass the raw string.
            $bag = $bag->with(Message::ofToolCall($call, $output));
        }

        continue;
    }

    break;
} while (true);

echo $deferred->asText();
```

For high-level orchestration (tool loop, memory, fault tolerance) use the
`agent` skill. The agent component exposes its own `#[AsTool]` attribute at
`src/agent/src/Toolbox/Attribute/AsTool.php` : only available inside the
Agent skill.

## 3. Multi-provider failover with rate limiting

`FailoverPlatform` lives at
`Symfony\AI\Platform\Bridge\Failover\FailoverPlatform`, in its **own
Composer package** `symfony/ai-failover-platform` — the monorepo directory
`Bridge/Failover/` is split out at release time and is not part of
`symfony/ai-platform`. Install it explicitly. Its constructor requires a
`RateLimiterFactoryInterface` as the second argument.

```php
use Symfony\AI\Platform\Bridge\Anthropic\Factory as AnthropicFactory;
use Symfony\AI\Platform\Bridge\Failover\FailoverPlatform;
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;
use Symfony\Component\RateLimiter\RateLimiterFactory;
use Symfony\Component\RateLimiter\Storage\InMemoryStorage;

$openai    = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);
$anthropic = AnthropicFactory::createPlatform($_ENV['ANTHROPIC_API_KEY']);

$rateLimiterFactory = new RateLimiterFactory(
    ['id' => 'failover', 'policy' => 'sliding_window', 'limit' => 10, 'interval' => '1 minute'],
    new InMemoryStorage(),
);

$failover = new FailoverPlatform([$openai, $anthropic], $rateLimiterFactory);

$result = $failover->invoke('gpt-4o-mini', $bag);
echo $result->asText();
```

`FailoverPlatform` iterates platforms in order, consumes one rate-limit
token per attempt, and on any `\Throwable` from the underlying call
records the platform as failed (via a `\WeakMap`) and moves on. After all
platforms fail it throws a generic
`Symfony\AI\Platform\Exception\RuntimeException('All platforms failed.')`.

Each platform needs its own model identifier. `FailoverPlatform` does **not**
translate `gpt-4o-mini` to a Claude equivalent : it calls the same model
name on every provider. Use `Model` wrappers with `Capability` metadata if
you want capability-based dispatch.

## 4. Streaming responses

There is **no** `Platform::stream()` method. You opt in by passing
`'stream' => true` in `$options`, then iterate `$result->asStream()`.

```php
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;
use Symfony\AI\Platform\Message\Message;
use Symfony\AI\Platform\Message\MessageBag;
use Symfony\AI\Platform\Result\Stream\Delta\TextDelta;

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);

$result = $platform->invoke(
    'gpt-4o-mini',
    new MessageBag(Message::ofUser('Tell me a story.')),
    ['stream' => true],
);

foreach ($result->asTextStream() as $delta) {
    /* @var TextDelta $delta */
    echo $delta->getText();
}
```

`DeferredResult::asStream()` yields `\Generator<DeltaInterface>`. The
narrower `asTextStream()` filters to `TextDelta` only. For typed partials
during a structured-output stream, use `asStreamedObject()` which yields
`PartialObjectDelta::getObject()` typed instances per changed snapshot.
`asPartialJsonStream()` yields the largest valid JSON snapshot recoverable
so far (uses `PartialJsonParser` internally).

The stream is single-shot: `asStream()`, `asStreamedObject()`, and
`asObject()` share a `\Generator` so the underlying stream is only driven
once across all three consumers.

## 5. Multi-modal input (image + text)

There is **no** `Image::fromUrl()` or `Image::fromBinary()`. `Image`
inherits `File::fromFile()` and `File::fromDataUrl()`. For URL inputs use
the separate `ImageUrl` (or `DocumentUrl`) class.

```php
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;
use Symfony\AI\Platform\Message\Content\Document;
use Symfony\AI\Platform\Message\Content\Image;
use Symfony\AI\Platform\Message\Content\ImageUrl;
use Symfony\AI\Platform\Message\Message;
use Symfony\AI\Platform\Message\MessageBag;

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);

// Inline image + text
$inline = Message::ofUser(
    'What is in this picture?',
    Image::fromFile('/path/to/cat.png'),
);

// Remote image + text
$remote = Message::ofUser(
    'Describe this picture.',
    new ImageUrl('https://example.com/cat.jpg'),
);

// PDF (Anthropic / Gemini accept direct PDF input)
$pdf = Message::ofUser(
    'Summarise the attached PDF.',
    Document::fromFile('/path/to/doc.pdf'),
);

foreach ([$inline, $remote, $pdf] as $message) {
    $result = $platform->invoke('gpt-4o-mini', new MessageBag($message));
    echo $result->asText() . PHP_EOL;
}
```

For audio: `Audio::fromFile($path)` (also a `File` subclass). For video:
`Video::fromFile($path)`. To batch several content parts under one message,
wrap them in `Collection(ContentInterface ...$content)`.

Provider limits differ (size, MIME, supported formats). Per-bridge details
in `references/bridges.md`; quirks in `references/gotchas.md`.

## 6. Streaming decision table, capability guards, FailoverPlatform boundaries

This section compiles three orthogonal reference tables that the rest of the
skill builds on. Each row is grounded in the public surface verified against
`https://github.com/symfony/ai/tree/main/src/platform/src/`.

### 6.1 Streaming accessor decision table

`DeferredResult` exposes three narrow stream consumers on top of `asStream()`.
All three are driven by the same internal `\Generator`, so the underlying
stream is consumed exactly once across `asStream()`, `asStreamedObject()`, and
`asObject()` (see `DeferredResult::$stream`).

| Method                  | Returns                     | What is yielded                                       | Single-consumer? | Safe for business validation when…                                                   |
|-------------------------|-----------------------------|-------------------------------------------------------|------------------|--------------------------------------------------------------------------------------|
| `asTextStream()`        | `\Generator<TextDelta>`      | `TextDelta` only; other deltas (tool, metadata, …) skipped | yes (via shared generator) | stream is exhausted; the final value matches `asText()`                              |
| `asStreamedObject()`    | `\Generator<object>`        | progressively populated typed object per `PartialObjectDelta` (only when changed) | yes (via shared generator) | stream is exhausted; final yielded object matches `asObject()`                       |
| `asPartialJsonStream()` | `\Generator<mixed>`         | largest valid JSON snapshot recoverable from the text buffer (filtered, deduplicated) | yes (via shared generator) | stream is exhausted; the last yielded snapshot is the parsed final buffer            |

Important caveats drawn straight from the source:

- All three iterators **filter non-text / non-object deltas silently**. If you
  need tool calls, metadata, or thinking tokens interleaved with text, fall
  back to `asStream()` and inspect `DeltaInterface` subclasses yourself
  (`TextDelta`, `ToolInputDelta`, `ThinkingDelta`, `BinaryDelta`, …).
- `asPartialJsonStream()` accumulates text deltas into a buffer, runs
  `PartialJsonParser::parse()`, and yields only when the parsed value differs
  from the previously yielded one. Intermediate snapshots may be
  syntactically valid JSON but **semantically incomplete** (missing fields,
  default values, truncated arrays). Do not run business validation on any
  yielded value before the stream finishes.
- `asStreamedObject()` yields `PartialObjectDelta::getObject()` per changed
  snapshot. The same rule applies: only the final yielded value matches what
  `asObject()` would return.

### 6.2 Stream validity and consumption contract

- The shared `\Generator` is single-shot. Pick **one** of `asStream()`,
  `asStreamedObject()`, or `asObject()` for the typed view, then optionally
  one of the narrow consumers on top. Mixing them is allowed but the
  underlying stream is driven exactly once; subsequent calls observe the
  remaining deltas only.
- Intermediate typed objects (`asStreamedObject()`) and JSON snapshots
  (`asPartialJsonStream()`) are **not** guaranteed business-valid. Treat them
  as best-effort render hints. Final validation belongs at the end of the
  stream, where the recovered object matches what `asObject()` returns
  (see `DeferredResult::asObject()` which pumps the remainder if
  `asStreamedObject()` stopped early).
- Metadata (`token_usage`, `finish_reason`, provider-specific fields) is only
  fully populated after stream exhaustion. Do not read
  `$result->getMetadata()` mid-stream and assume it is complete; the
  `Metadata\StreamListener` and `TokenUsage\StreamListener` push deltas as they
  arrive.
- Calling `asObject()` after a partial `asStreamedObject()` iteration drains
  the remaining deltas internally and returns the final typed object. If the
  stream never produced a final object, it throws
  `UnexpectedResultTypeException`.

### 6.3 Capability guards via `Model::supports()`

`Symfony\AI\Platform\Capability` is a string-backed enum. `Model::supports()`
delegates to `Capability::equalsOneOf()` and returns `bool`. Use the exact
enum cases from `Capability.php` : do not invent cases.

The cases that gate behaviour at the `DeferredResult` / `PlatformSubscriber`
level are:

| Capability                          | Gate purpose                                                         |
|-------------------------------------|----------------------------------------------------------------------|
| `Capability::OUTPUT_STRUCTURED`     | Required for `options['response_format']` (throws `MissingModelSupportException::forStructuredOutput()`). |
| `Capability::OUTPUT_STREAMING`      | Model advertises SSE / chunked deltas; required before passing `'stream' => true`. |
| `Capability::TOOL_CALLING`          | Model accepts `Tool[]` in `options['tools']`. |

Guarding code follows the same shape used by `StringToMessageBagListener` and
`StructuredOutput\PlatformSubscriber`:

```php
use Symfony\AI\Platform\Capability;
use Symfony\AI\Platform\Model;

$model = new Model(
    name: 'gpt-4o-mini',
    capabilities: [
        Capability::OUTPUT_TEXT,
        Capability::OUTPUT_STREAMING,
        Capability::OUTPUT_STRUCTURED,
        Capability::TOOL_CALLING,
    ],
);

if (!$model->supports(Capability::OUTPUT_STREAMING)) {
    throw new \LogicException('Pick a streaming-capable model before opting into stream: true.');
}

if (!$model->supports(Capability::OUTPUT_STRUCTURED)) {
    throw new \LogicException('response_format is unavailable on this model.');
}

if (!$model->supports(Capability::TOOL_CALLING) && [] !== ($options['tools'] ?? [])) {
    throw new \LogicException('Tools are not supported by this model.');
}
```

Guard before `Platform::invoke()` : the structured-output subscriber throws
`MissingModelSupportException` for `OUTPUT_STRUCTURED`, but streaming and
tool calling are not centrally guarded; checking `Model::supports()` is the
only portable way to fail fast.

### 6.4 `FailoverPlatform` boundaries

> See also section 3 above for the constructor wiring pattern; this section
> focuses on the boundaries the implementation does NOT cover.

`FailoverPlatform` (`Symfony\AI\Platform\Bridge\Failover\FailoverPlatform`,
shipped as the separate package `symfony/ai-failover-platform`) is a
thin decorator over a list of `PlatformInterface` instances. Its
`invoke()` calls `$platform->invoke($model, $input, $options)` on each
candidate. The contract is intentionally narrow:

What it **does**:

- forwards the **same `$model` argument** (string or `Model`) to every
  underlying platform;
- creates a rate limiter per platform class, but **never skips a platform
  because of it**: `FailoverPlatform.php:68-72` uses
  `$limiter->consume()->isAccepted()` only as one half of the condition that
  *clears* an entry from the failed map, and calls the platform unconditionally
  afterwards. A saturated platform is still invoked;
- tracks failed platforms in a `\WeakMap` keyed by platform instance and
  unmarks them once the rate limiter accepts them again — the map is
  bookkeeping only, nothing reads it to skip a candidate;
- consumes a second token when a call throws, so a failure costs two;
- logs every per-platform failure through `Psr\Log\LoggerInterface`;
- after the loop, throws `RuntimeException('All platforms failed.')` if every
  platform threw.

What it **does not** provide:

- **no model mapping** : `'gpt-4o-mini'` is forwarded verbatim to an
  Anthropic platform. Provide your own `Model` wrappers with matching
  capabilities per provider if you want model-name translation.
- **no option translation guarantee** : `$options` is forwarded as-is. Each
  provider accepts its own option names; there is no shared whitelist.
- **no universal retry / backoff** : there is no per-call retry, no
  exponential backoff, no jitter. A single failure moves on to the next
  platform. There is no `RetryPlatform` bridge (see gotcha #8).
- **no circuit breaker** : the `\WeakMap` records failed platforms but does
  not open / half-open / close like a circuit breaker. The only gate is the
  `RateLimiterFactoryInterface` you pass in; a saturated limiter is the
  closest thing to a breaker.
- **no stream-resume guarantee** : the shared `\Generator` on `DeferredResult`
  is single-shot. A mid-stream `FailoverPlatform` failure aborts the partial
  stream and starts a brand new invocation on the next platform; consumers
  that already yielded some deltas do not get them replayed.

Treat `FailoverPlatform` as an ordered, rate-limited fallback list : nothing
more. Anything that requires model translation, retry budgets, or stream
resume must be layered on top by your application code (or the agent
component, which exposes its own loop / fault-tolerance machinery).

## See also

- `references/api.md` : full signature catalogue (`DeferredResult`,
  `TokenUsage`, `FinishReason`, `Vector`, `MessageBag`)
- `references/bridges.md` : all 37 bridges with Composer package names
- `references/embeddings.md` : embeddings contract (different from text
  generation)
- `references/gotchas.md` : provider quirks and exception catalogue
