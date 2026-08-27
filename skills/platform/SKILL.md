---
name: platform
description: 'Use when invoking any LLM through Symfony AI''s unified abstraction : chat, completions, structured output, tool/function calling, embeddings, or multi-provider failover. Also trigger when the user asks "how do I call OpenAI / Anthropic / Gemini from PHP", "how to switch LLM providers without rewriting code", "how to get structured JSON out of an LLM", "how to call an LLM tool/function", "how to embed text with an AI model", or "how to build an embeddings pipeline". Triggers on `PlatformInterface`, `Platform`, `Model`, `Message`, `MessageBag`, `Tool`, `FailoverPlatform`, `embeddings`. Do NOT trigger when the user is asking specifically about Chat sessions, Agent orchestration, or vector DBs : those have their own skills (`chat`, `agent`, `store`).'
license: MIT
metadata:
  author: MadCat34
  email: madcat34@gmail.com
  url: https://github.com/MadCat34
  version: "0.13.0-dev"
---

# Platform

> **Symfony AI is experimental** : APIs may break between releases. Always check `UPGRADE.md` in the [symfony/ai monorepo](https://github.com/symfony/ai) before upgrading.

Unified abstraction over 37 LLM / multimodal providers living under
`Symfony\AI\Platform\Bridge\*`. One `Platform` service, one `invoke()` call site,
many providers.

## When to use Platform vs a vendor SDK directly

Use **Platform** when you want:

- A single call site that can switch providers by changing one factory line
- Tool / function calling normalised across providers
- Structured output (JSON schema validation, optional Validator integration)
- Embeddings + vector search behind one interface
- Multi-provider failover with rate-limited retries
- Cross-provider observability via `TraceablePlatform`

**Skip Platform** when you need a provider-specific feature that the bridge does
not yet expose (an unusual streaming protocol, a private beta endpoint, etc.).
In that case call the vendor's PHP SDK directly : but read `references/gotchas.md`
first to know what you lose.

## Installation

The core package plus one bridge per provider:

```bash
composer require symfony/ai-platform
composer require symfony/ai-open-ai-platform   # pick one or many
# OPENAI_API_KEY=sk-...
```

For failover (rate-limited, multi-platform):

```bash
composer require symfony/ai-failover-platform
```

For caching prompt-cache-keyed responses:

```bash
composer require symfony/ai-cache-platform
```

## Quick reference (5 lines)

The minimal end-to-end call. Note that `Message::forSystem`, `Message::ofUser`,
the `Bridge\OpenAi\Factory` (renamed from `PlatformFactory` in 0.12), and
`$result->asText()` are the real names in this source tree.

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

- `Platform::invoke()` fires `ModelRoutingEvent`, lets a `ModelRouter` (default
  `CatalogBasedModelRouter`) pick the right `Provider`, dispatches
  `InvocationEvent`, then `ResultEvent`. A subscriber can rewrite the
  `DeferredResult` between conversion and consumption : that is how
  `PlatformSubscriber` (structured output) and `ValidatorSubscriber` plug in.
- `Provider::invoke()` normalises input via `Contract::createRequestPayload()`,
  sends through a `ModelClientInterface`, and wraps the `RawResultInterface`
  in a `DeferredResult` that runs its `ResultConverter` lazily on first access.
- `DeferredResult::asText()`, `asObject()`, `asStream()`, etc. are the
  one-stop accessor : see `references/api.md`.

## Key gotchas

These bite the moment you go beyond the trivial example. Full list and
explanations in `references/gotchas.md`.

- **`DeferredResult`, not `Result\Result`.** All `asText()` / `asObject()` /
  `asVectors()` / `asStream()` methods hang off `DeferredResult`. The interface
  `ResultInterface` only exposes `getContent()`, `getRawResult()`, `setRawResult()`.
- **Tool calls need `Tool` + `ExecutionReference` in raw Platform.** There is no
  `ToolDefinition` class in `src/platform/src/Tool/`. The agent's `#[AsTool]`
  attribute lives at `src/agent/src/Toolbox/Attribute/AsTool.php` and only kicks
  in when you are inside the Agent component.
- **`CachePlatform` is opt-in.** Caching only activates when
  `options['prompt_cache_key']` is set; without it, `CachePlatform` is a
  pass-through.
- **`FailoverPlatform` is a separate package** (`symfony/ai-failover-platform`)
  and requires a `RateLimiterFactoryInterface`. It is **not** bundled with
  `symfony/ai-platform`.
- **`MiniMax` is its own provider.** `Bridge\MiniMax\Factory` ships in
  `symfony/ai-mini-max-platform`; it is **not** an Anthropic alias.

## Common tasks

- **Switch provider**: change `OpenAiFactory::createPlatform(...)` to e.g.
  `Anthropic\Factory::createPlatform(...)`. Read `references/bridges.md` for
  the catalogue of 37 packages.
- **Get structured JSON back**: pass `'response_format' => MyDto::class` (or an
  instance) in `$options`. Read `references/patterns.md#structured-output`.
- **Call a tool from raw Platform**: define a `Tool` with an
  `ExecutionReference`, pass it via `'tools' => [$tool]`. Read
  `references/patterns.md#tool-calling`.
- **Stream tokens**: pass `'stream' => true`, then iterate
  `$result->asStream()` yielding `TextDelta` (or `asStreamedObject()` for typed
  partials). Read `references/patterns.md#streaming`.
- **Multi-provider failover**: wrap your `Platform`s in `FailoverPlatform([...])`
  together with a `RateLimiterFactoryInterface`. Read
  `references/patterns.md#failover`.
- **Multimodal (image, audio, PDF)**: use `File::fromFile()`, `Image::fromFile()`,
  or `ImageUrl` / `DocumentUrl`. Read `references/patterns.md#multimodal`.

## References

Read these when the matching situation applies. They are not a guided tour :
pick the one that fits the question.

- **Full API surface (namespaces, method signatures, `DeferredResult`,
  `TokenUsage`, `FinishReason`, `Vector`, `MessageBag`): read
  [`references/api.md`](references/api.md) when the user wants the full
  namespace tree, real method signatures, or how `ResultInterface` differs
  from `DeferredResult`.**
- **All 37 bridges, grouped by category, with real package names: read
  [`references/bridges.md`](references/bridges.md) when the user picks a
  provider or asks "which packages exist for X?".**
- **Embeddings, Vector, reranking contracts and a working RAG skeleton:
  read [`references/embeddings.md`](references/embeddings.md) when the user
  asks for embeddings, vector search, or RAG.**
- **Patterns that compile: structured output, tool calling, failover,
  streaming, multimodal: read [`references/patterns.md`](references/patterns.md)
  when the user wants runnable code for one of these five jobs.**
- **Provider quirks, edge cases, exception classes, finish-reason cases:
  read [`references/gotchas.md`](references/gotchas.md) when something is
  misbehaving and you need the trap list.**
- **Validation**: run `bash skills/platform/scripts/check-snippets.sh` to
  lint every PHP code block in this skill with `php -l`.
