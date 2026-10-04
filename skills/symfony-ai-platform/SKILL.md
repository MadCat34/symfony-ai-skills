---
name: symfony-ai-platform
description: 'Use when PHP code calls an LLM or embedding model through Symfony AI Platform: completions, streaming, structured JSON output, tool calling, multimodal input, async jobs, or switching and failing over between OpenAI, Anthropic, Gemini, Ollama and other providers, even when Symfony AI is not named. Triggers on `PlatformInterface`, `MessageBag`, `DeferredResult`, `FailoverPlatform`. Not for agent loops, chat history or vector stores (`symfony-ai-agent`, `symfony-ai-chat`, `symfony-ai-store`).'
license: MIT
metadata:
  author: Romain Bastide <madcat34@gmail.com>
  url: https://github.com/MadCat34
  version: 0.14.1
  tags: symfony, php, ai, llm, openai, anthropic, gemini, embeddings, structured-output, tool-calling
---

# Symfony AI Platform

## Purpose

One PHP abstraction over the 43 bridges living under
`Symfony\AI\Platform\Bridge\*` (LLM and multimodal providers, plus the
`Failover` and `Cache` decorators): one `Platform` service, one `invoke()` call
site. Switching provider means changing the factory line, not the call sites.

## When to use

- Calling an LLM or an embedding model from PHP, with or without the Symfony framework.
- Keeping one call site that can move between OpenAI, Anthropic, Gemini, Mistral, Ollama and the other bridges.
- Tool calling, structured output (JSON schema to PHP object, optional Validator), streaming and multimodal input, normalised across providers.
- Generating embeddings for RAG.
- Failing over between providers with rate limiting, running async or batch jobs, tracing calls with `TraceablePlatform`.

## When not to use

- An automatic tool-calling loop, memory or sub-agents: use `symfony-ai-agent`.
- Conversation history persisted between requests: use `symfony-ai-chat`.
- Storing or searching vectors: use `symfony-ai-store`.
- Declaring platforms in `config/packages/ai.yaml`: use `symfony-ai-bundle`.
- A provider feature no bridge exposes yet (an unusual streaming protocol, a
  private beta endpoint): call the vendor SDK directly, after reading
  `references/gotchas.md` to see what is lost. Reaching for `openai-php/client`
  by default, without such a reason, gives up unified tool calling, structured
  output, failover, and message templates.

## Prerequisites

PHP 8.2+, the core package, one bridge per provider, and that provider's API key:

```bash
composer require symfony/ai-platform
composer require symfony/ai-open-ai-platform   # pick one or many
# OPENAI_API_KEY=sk-...
```

Optional packages: `symfony/ai-failover-platform` (multi-provider failover) and
`symfony/ai-cache-platform` (responses cached by prompt-cache key).

## Examples

The minimal end-to-end call. The factory class is `Bridge\OpenAi\Factory`
(there is no `PlatformFactory`), messages come from `Message::forSystem()` /
`Message::ofUser()`, and `asText()` reads the answer:

```php
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;
use Symfony\AI\Platform\Message\Message;
use Symfony\AI\Platform\Message\MessageBag;

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);

$result = $platform->invoke('gpt-4o-mini', new MessageBag(
    Message::forSystem('You are a helpful assistant.'),
    Message::ofUser('What is the capital of France?'),
));

echo $result->asText();
```

## Architecture

```text
Platform (Symfony\AI\Platform\Platform)
 └── ProviderInterface[]
      ├── Provider "openai"        (Bridge\OpenAi\Factory::createProvider)
      │    ├── ModelClient         (HTTP transport, request serialisation)
      │    ├── ResultConverter     (raw → Result\TextResult / VectorResult / …)
      │    ├── ModelCatalog        (name → Model)
      │    └── Contract            (Symfony Serializer normalizers)
      └── Provider "anthropic"     (Bridge\Anthropic\Factory::createProvider)
           └── …
```

- `Platform::invoke()` fires `ModelRoutingEvent`, lets a `ModelRouterInterface`
  (default `CatalogBasedModelRouter`) pick the right `Provider`, dispatches
  `InvocationEvent`, then `ResultEvent`. A subscriber can rewrite the
  `DeferredResult` between conversion and consumption : that is how
  `PlatformSubscriber` (structured output) and `ValidatorSubscriber` plug in.
- `Provider::invoke()` normalises input via `Contract::createRequestPayload()`,
  sends through a `ModelClientInterface`, and wraps the `RawResultInterface`
  in a `DeferredResult` that runs its `ResultConverter` lazily on first access.

## Key gotchas

- **`DeferredResult`, not `Result\Result`.** All `asText()` / `asObject()` /
  `asVectors()` / `asStream()` methods hang off `DeferredResult`. The interface
  `ResultInterface` only exposes `getContent()`, `getRawResult()`, `setRawResult()`.
- **Raw tool calls need `Tool` + `ExecutionReference`.** There is no
  `ToolDefinition` class. `#[AsTool]` belongs to the Agent component
  (`symfony-ai-agent`) and does nothing in raw Platform calls.
- **`CachePlatform` is opt-in.** Caching only activates when
  `options['prompt_cache_key']` is set; without it, `CachePlatform` is a
  pass-through.
- **`FailoverPlatform` is a separate package** (`symfony/ai-failover-platform`)
  and requires a `RateLimiterFactoryInterface`.
- **`MiniMax` is its own provider.** `Bridge\MiniMax\Factory` ships in
  `symfony/ai-mini-max-platform`; it is **not** an Anthropic alias.

## Troubleshooting

| Error | Cause | Fix |
| --- | --- | --- |
| `Unexpected response type: expected "…\TextResult", got "…\JobResult".` (`UnexpectedResultTypeException`) | The provider runs asynchronously and returned a job: Replicate (every call), MiniMax video and `async: true` speech, Higgsfield, Venice video, Eden AI speech-to-text, OpenAI batches. | `$handle = $result->asJob();` then `(new JobRunner())->wait(Factory::createJobClient($apiKey), $handle)`. See `references/api-reference.md` → *Asynchronous jobs*. |
| `No provider found for model "…".` (`ModelNotFoundException`) | No registered provider's catalog knows that model name: a typo, or the bridge for that provider is not installed. | Check the exact name in the bridge's `ModelCatalog`, install the bridge, or register the model on the catalog. |
| `Model "…" (…) does not support "structured output".` (`MissingModelSupportException`) | A `response_format` was passed to a model without `Capability::OUTPUT_STRUCTURED`. | Pick a model that has it; guard other capabilities with `Model::supports()` (`references/patterns.md` → *Capability guards*). |
| `All platforms failed.` (`RuntimeException` from `FailoverPlatform`) | Every wrapped platform threw; each failure is logged as "The {platform} platform failed due to an error/exception". | Read the logged causes; check API keys and the rate limiter policy. |
| `RateLimitExceededException` | The provider answered HTTP 429. | Retry after `getRetryAfter()` seconds, or put several platforms behind `FailoverPlatform`. |
| `ValidationException` from `asObject()` | Structured output broke the Validator constraints (`ValidatorSubscriber`). | Inspect the violations; tighten the prompt or relax the constraints. |

## Limitations

- The component is experimental: APIs change between minor versions. Pin
  `symfony/ai-platform` and read `UPGRADE.md` in the monorepo before upgrading.
- Bridges normalise a common subset; a provider-only feature may be missing
  until its bridge adds it.
- Capabilities belong to the model, not the provider: check `Model::supports()`
  before sending images, audio, tools or a response format.
- There is no `RetryPlatform`. `FailoverPlatform` moves on to the next
  platform; retrying the same provider is up to the caller.

## Usage

- **Switch provider**: replace `OpenAiFactory::createPlatform(...)` with e.g.
  `Anthropic\Factory::createPlatform(...)`; the call sites stay the same.
- **Get structured JSON back**: pass `'response_format' => MyDto::class` (or an
  instance) in `$options`, then call `asObject()`.
- **Call a tool from raw Platform**: define a `Tool` with an
  `ExecutionReference`, pass it via `'tools' => [$tool]`.
- **Stream tokens**: pass `'stream' => true`, then iterate
  `$result->asStream()` yielding `TextDelta` (or `asStreamedObject()` for typed
  partials).
- **Fail over between providers**: wrap the platforms in `FailoverPlatform([...])`
  together with a `RateLimiterFactoryInterface`.
- **Send an image, audio or PDF**: use `File::fromFile()`, `Image::fromFile()`,
  `ImageUrl` or `DocumentUrl` content parts.

## References

- Read [`references/api-reference.md`](references/api-reference.md) when the
  user needs the namespace tree, exact method signatures, `DeferredResult`,
  `TokenUsage`, `FinishReason`, `Vector`, `MessageBag`, async jobs or batches.
- Read [`references/bridges.md`](references/bridges.md) when the user picks a
  provider or asks which packages exist for it (all 43 bridges, by category).
- Read [`references/embeddings.md`](references/embeddings.md) when the user
  generates embeddings, reranks, or wires a RAG skeleton.
- Read [`references/patterns.md`](references/patterns.md) when the user wants
  runnable code for structured output, tool calling, failover, streaming or
  multimodal input.
- Read [`references/gotchas.md`](references/gotchas.md) when a call misbehaves
  and the cause is not in the tables above: provider quirks, the exception
  catalogue, finish-reason cases.

## See also

- `symfony-ai-agent`: a tool-calling agent built on top of Platform.
- `symfony-ai-store`: storing and searching the vectors Platform generates.
- `symfony-ai-chat`: conversation history across requests.
- `symfony-ai-bundle`: declaring platforms in `config/packages/ai.yaml`.
