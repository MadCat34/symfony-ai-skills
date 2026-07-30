---
name: chat
description: Use when building a stateful chat session that wraps an Agent and persists the conversation via a `MessageStoreInterface`. Triggers on `Chat`, `ChatInterface`, `MessageStoreInterface`, `MessageStore`, `ManagedStoreInterface`, `MessageNormalizer`, `InMemory\Store`, `ChatStreamListener`, `setup()` / `drop()` console commands, or messages persisting across requests. Do NOT trigger for raw LLM invocation (use `platform`), a stateless tool-calling agent (use `agent`), or vector storage (use `store`).
license: MIT
metadata:
  author: MadCat34
  email: madcat34@gmail.com
  url: https://github.com/MadCat34
  version: "0.1.0"
---

# Chat

> ⚠️ **Symfony AI is experimental** : APIs may break between releases. Always check `UPGRADE.md` in the [symfony/ai monorepo](https://github.com/symfony/ai) before upgrading.

The `symfony/ai-chat` component wraps an `Agent` with a `MessageStoreInterface` so that a conversation survives across requests. The agent stays stateless; persistence is delegated to a pluggable store (in-memory, Doctrine DBAL, Redis, MongoDB, Meilisearch, Cache, Session, Cloudflare KV, SurrealDB, Pogocache).

## When to use Chat vs raw Agent

Use **Chat** when you want:

- The conversation history to be loaded from a store and saved back after every turn.
- One Agent instance reused across multiple users/sessions, with each session identified by its own `MessageStore` instance.
- Streaming responses (`Chat::stream()`) that persist the final assistant message into the store.
- A swap-out infrastructure (in-memory in tests, Redis in dev, DBAL in prod) without touching call sites.

Use **raw Agent** when:

- You want a one-shot completion with no history.
- You build the `MessageBag` yourself and don't need persistence.
- You're calling a tool-agent that owns its own memory (see `agent` skill : `MemoryInputProcessor`).

## Installation

```bash
composer require symfony/ai-chat
composer require symfony/ai-agent
composer require symfony/ai-platform
composer require symfony/ai-open-ai-platform
# Pick a bridge for persistence:
composer require symfony/ai-chat-doctrine       # DBAL
composer require symfony/ai-chat-redis          # Redis
composer require symfony/ai-chat-mongodb        # MongoDB
composer require symfony/ai-chat-cache          # PSR-6 cache
composer require symfony/ai-chat-session        # Symfony HttpFoundation session
composer require symfony/ai-chat-meilisearch    # Meilisearch
composer require symfony/ai-chat-cloudflare     # Cloudflare KV
composer require symfony/ai-chat-surrealdb      # SurrealDB
composer require symfony/ai-chat-pogocache      # Pogocache
```text

## Architecture

```
UserMessage  --->  Chat::submit(UserMessage)
                       |
                       v
        store->load()  -->  MessageBag (history)
                       |
                       v
        agent->call(messages)  -->  AssistantMessage
                       |
                       v
        messages->add(assistant)  -- mutated in place
                       |
                       v
        store->save(messages)
                       |
                       v
                  return AssistantMessage
```text

`Chat::stream()` follows the same shape but attaches a `ChatStreamListener` to the `StreamResult` so the assembled assistant message is appended and persisted on `CompleteEvent`.

## Quick reference: in-memory chat

```php
use Symfony\AI\Agent\Agent;
use Symfony\AI\Chat\Chat;
use Symfony\AI\Chat\InMemory\Store;
use Symfony\AI\Chat\MessageNormalizer;
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;
use Symfony\AI\Platform\Message\Message;
use Symfony\AI\Platform\Message\MessageBag;

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);
$agent = new Agent($platform, 'gpt-4o-mini');
$store = new InMemory\Store(); // implements both ManagedStoreInterface and MessageStoreInterface

$chat = new Chat($agent, $store);

// Optional: seed with a system + history bag (drops existing content first).
$chat->initiate(new MessageBag(Message::forSystem('You are a helpful assistant.')));

// One turn.
$reply = $chat->submit(Message::ofUser('Hello!'));
echo $reply->asText();

// Streaming turn.
foreach ($chat->stream(Message::ofUser('Tell me a joke.')) as $delta) {
    echo $delta;
}
```

The constructor requires `MessageStoreInterface&ManagedStoreInterface` : an intersection type. Every built-in store (`InMemory\Store` and every bridge) implements both.

## Bridge packages

| Bridge | Class | Requires | `setup()` behaviour |
|---|---|---|---|
| Doctrine | `Symfony\AI\Chat\Bridge\Doctrine\DoctrineDbalMessageStore` | `Doctrine\DBAL\Connection` | Creates `chat_messages` table (or custom name) via schema introspection. |
| Redis | `Symfony\AI\Chat\Bridge\Redis\MessageStore` | `\Redis` | `SET`s an empty JSON array at the key. |
| MongoDB | `Symfony\AI\Chat\Bridge\MongoDb\MessageStore` | `MongoDB\Client` | `createCollection` on the database. |
| Cache | `Symfony\AI\Chat\Bridge\Cache\MessageStore` | `Psr\Cache\CacheItemPoolInterface` | Seeds an empty `MessageBag` cache item. |
| Session | `Symfony\AI\Chat\Bridge\Session\MessageStore` | `Symfony\Component\HttpFoundation\RequestStack` | Initialises the session key. |
| Meilisearch | `Symfony\AI\Chat\Bridge\Meilisearch\MessageStore` | `HttpClientInterface`, `symfony/clock` | Creates the index with `addedAt` sortable. |
| Cloudflare | `Symfony\AI\Chat\Bridge\Cloudflare\MessageStore` | `HttpClientInterface` | Creates the KV namespace. |
| SurrealDB | `Symfony\AI\Chat\Bridge\SurrealDb\MessageStore` | `HttpClientInterface` | No-op (table is created on first write). |
| Pogocache | `Symfony\AI\Chat\Bridge\Pogocache\MessageStore` | `HttpClientInterface` | `PUT` against the key. |

The Doctrine bridge uses **Doctrine DBAL**, not the ORM. There is no `ChatMessage` entity : the bridge creates a flat table with `(id BIGINT, messages TEXT, added_at INTEGER)`.

## Console commands

```bash
# Run this once per environment to create the backing infrastructure.
php bin/console ai:message-store:setup <store>

# Wipe the store (requires --force).
php bin/console ai:message-store:drop <store> --force
```

Both commands accept a store service-id and delegate to `ManagedStoreInterface::setup()` / `drop()`. They only work against services that implement `ManagedStoreInterface`.

## Observability

Two decorators wrap the core types:

- `TraceableChat` implements `ChatInterface` and records every `initiate`, `submit`, `stream` call (with the `MessageBag` and a `ClockInterface` timestamp) in `getCalls()`. It also implements `ResetInterface`.
- `TraceableMessageStore` implements both `MessageStoreInterface` and `ManagedStoreInterface`; it records every `save()` (with `MessageBag` and timestamp) and delegates `setup()` / `drop()` only when the wrapped store implements `ManagedStoreInterface`.

Both are useful for tests and profiler wiring.

## Key gotchas

- **The method is `submit()`, not `send()`.** `ChatInterface::submit(UserMessage)` returns an `AssistantMessage`.
- **There is no `chatId` concept.** `MessageStoreInterface::save()` and `load()` take no identifier. Each conversation gets its own store instance; if you want parallel sessions, instantiate one `Store` per session.
- **`MessageBag` IS mutated.** `Chat::submit()` calls `$messages->add(...)` before delegating and `ChatStreamListener` appends the assembled assistant message. Do not rely on the bag being immutable.
- **Constructor is an intersection type.** `Chat::__construct(AgentInterface $agent, MessageStoreInterface&ManagedStoreInterface $store)`. The store must implement both interfaces.
- **Doctrine means DBAL, not ORM.** The bridge takes a `Doctrine\DBAL\Connection` and creates the table via `Schema::createTable` : no entity manager, no `ChatMessage` class.
- **Per-instance state.** Channels like Redis, MongoDB, Cache, and Session are singletons keyed by `$indexName` / `$cacheKey` / `$sessionKey` / `$tableName`. The default keys are not random : override them per session to avoid collisions.
- **Every bridge implements `setup()`.** Including `Cache` and `Session`. The current assumption that "in-memory and cache need no setup" is wrong.
- **Streaming persists on completion.** If the consumer breaks out of the `foreach` early, `ChatStreamListener::onComplete()` never fires and the partial message is lost.
- **Meilisearch bridge requires `symfony/clock`.** The constructor throws `RuntimeException` at instantiation if `Psr\Clock\ClockInterface` is missing.

## Common tasks

- **In-memory chat for tests**: `new Chat($agent, new InMemory\Store())`. See [references/patterns.md#in-memory](references/patterns.md#in-memory).
- **Doctrine DBAL chat**: `new Chat($agent, new DoctrineDbalMessageStore($connection, 'chat_messages'))` after running `ai:message-store:setup`. See [references/patterns.md#doctrine-dbal](references/patterns.md#doctrine-dbal).
- **Wrap an Agent with tools**: build the agent the usual way (see `agent` skill), then pass it to `Chat`. See [references/patterns.md#chat-with-tools](references/patterns.md#chat-with-tools).
- **Streaming reply**: `foreach ($chat->stream(Message::ofUser('...')) as $delta) { ... }`. The final message is persisted automatically.
- **Inspect recorded calls**: wrap the chat in `TraceableChat` and call `getCalls()`.

## References

- **Full API surface** (Chat, ChatInterface, MessageStoreInterface, ManagedStoreInterface, InMemory\Store, ChatStreamListener, TraceableChat, TraceableMessageStore, MessageNormalizer, every bridge): [references/api.md](references/api.md)
- **Patterns** (in-memory, DBAL, agent-with-tools, streaming, traceable): [references/patterns.md](references/patterns.md)
- **Gotchas** (submit vs send, intersection type, DBAL not ORM, mutated MessageBag, per-instance state): [references/gotchas.md](references/gotchas.md)

## See also

- `agent` skill : for the underlying tool-calling agent that `Chat` wraps.
- `platform` skill : for raw LLM invocation (Agent wraps it).
- `ai-bundle` skill : for Symfony DI wiring of `Chat`, stores, and console commands.
- `skills/recipes/chat-with-memory-doctrine.md` : end-to-end recipe with Doctrine DBAL persistence.
