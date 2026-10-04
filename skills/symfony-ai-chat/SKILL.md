---
name: symfony-ai-chat
description: 'Use when a chatbot or assistant must remember the conversation across HTTP requests, even when the question does not name Symfony AI: Symfony AI Chat wraps an agent and saves history to Doctrine DBAL, Redis, MongoDB, a cache or the session, streamed replies included. Triggers on `Chat`, `ChatInterface`, `MessageStoreInterface`, `ai:message-store:setup`. Not for stateless LLM calls (`symfony-ai-platform`), tool loops (`symfony-ai-agent`) or vector search (`symfony-ai-store`).'
license: MIT
metadata:
  author: Romain Bastide <madcat34@gmail.com>
  url: https://github.com/MadCat34
  version: 0.14.1
  tags: symfony, php, ai, chat, chatbot, conversation-history, message-store, doctrine, redis
---

# Symfony AI Chat

## Purpose

`symfony/ai-chat` wraps an `Agent` with a `MessageStoreInterface` so that a
conversation survives across requests. The agent stays stateless; the history
lives in a pluggable store (in-memory, Doctrine DBAL, Redis, MongoDB,
Meilisearch, Cache, Session, Cloudflare KV, SurrealDB, Pogocache).

## When to use

- The history must be loaded from a store and saved back after every turn.
- One `Agent` serves many users or sessions, each with its own store instance.
- Streamed replies (`Chat::stream()`) whose final assistant message must be persisted.
- The backend should change per environment (in-memory in tests, Redis in dev,
  DBAL in prod) without touching call sites.
- Conversation state is currently hand-rolled in session files or ad hoc tables.

## When not to use

- A one-shot completion with no history: use `symfony-ai-platform`.
- A tool-calling agent whose `MessageBag` is built by hand each time: use `symfony-ai-agent`.
- Retrieving facts or documents by similarity: use `symfony-ai-store` (or agent
  memory from `symfony-ai-agent`); a message store only replays the conversation.
- Declaring chats and message stores in `config/packages/ai.yaml`: use `symfony-ai-bundle`.

## Prerequisites

PHP 8.2+, the chat, agent and platform packages, a platform bridge, and one
message-store bridge. Store packages are named after the backend:
`symfony/ai-<backend>-message-store`.

```bash
composer require symfony/ai-chat symfony/ai-agent symfony/ai-platform
composer require symfony/ai-open-ai-platform
# OPENAI_API_KEY=sk-...
composer require symfony/ai-doctrine-message-store      # DBAL
composer require symfony/ai-redis-message-store         # Redis
composer require symfony/ai-mongo-db-message-store      # MongoDB
composer require symfony/ai-cache-message-store         # PSR-6 cache
composer require symfony/ai-session-message-store       # Symfony HttpFoundation session
composer require symfony/ai-meilisearch-message-store   # Meilisearch
composer require symfony/ai-cloudflare-message-store    # Cloudflare KV
composer require symfony/ai-surreal-db-message-store    # SurrealDB
composer require symfony/ai-pogocache-message-store     # Pogocache
```

## Examples

An in-memory chat with one plain turn and one streamed turn:

```php
use Symfony\AI\Agent\Agent;
use Symfony\AI\Chat\Chat;
use Symfony\AI\Chat\InMemory\Store;
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;
use Symfony\AI\Platform\Message\Message;
use Symfony\AI\Platform\Message\MessageBag;
use Symfony\AI\Platform\Result\Stream\Delta\TextDelta;

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);
$agent = new Agent($platform, 'gpt-4o-mini');
$store = new Store(); // implements both ManagedStoreInterface and MessageStoreInterface

$chat = new Chat($agent, $store);

// Optional: seed with a system + history bag (drops existing content first).
$chat->initiate(new MessageBag(Message::forSystem('You are a helpful assistant.')));

// One turn.
$reply = $chat->submit(Message::ofUser('Hello!'));
echo $reply->asText();

// Streamed turn: DeltaInterface is an empty marker, filter for TextDelta.
foreach ($chat->stream(Message::ofUser('Tell me a joke.')) as $delta) {
    if ($delta instanceof TextDelta) {
        echo $delta->getText();
    }
}
```

## Architecture

```text
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
```

`Chat::stream()` follows the same shape but yields from the agent's lazy
`Execution::asStream()`; there is no `ChatStreamListener`. Once the stream is
drained, `stream()` builds the assistant message from `$execution->getResult()`,
merges `$execution->getMetadata()`, appends it, and persists it. A `Thinking`
part survives in the persisted history.

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

Two decorators help in tests and profiler wiring: `TraceableChat` records every
`initiate`, `submit` and `stream` call (`getCalls()`), and
`TraceableMessageStore` records every `save()` and delegates `setup()` /
`drop()` when the wrapped store is managed.

## Key gotchas

- **The method is `submit()`, not `send()`.** `ChatInterface::submit(UserMessage)`
  returns an `AssistantMessage`.
- **There is no `chatId`.** `MessageStoreInterface::save()` and `load()` take no
  identifier: each conversation needs its own store instance. Redis, MongoDB,
  Cache and Session stores are keyed by `$indexName` / `$cacheKey` /
  `$sessionKey` / `$tableName`, and the defaults are not random: override them
  per session to avoid collisions.
- **The `MessageBag` is mutated.** `submit()` adds to it before delegating;
  `stream()` appends the assembled assistant message once drained.
- **Streaming persists on completion.** Breaking out of the `foreach` early skips
  the persistence code after the `yield from`: the partial reply is lost.
- **Doctrine means DBAL, not ORM.** The bridge takes a `Doctrine\DBAL\Connection`
  and creates a flat table `(id BIGINT, messages TEXT, added_at INTEGER)`; there
  is no `ChatMessage` entity.
- **Every bridge implements `setup()`**, Cache and Session included: run
  `ai:message-store:setup` once per environment.

## Troubleshooting

| Error | Cause | Fix |
| --- | --- | --- |
| `Chat::__construct(): Argument #2 ($store) must be of type …MessageStoreInterface&…ManagedStoreInterface` (`TypeError`) | The store implements only one of the two interfaces. | Use a built-in store (all implement both) or implement `ManagedStoreInterface` too. |
| `For using Meilisearch as a message store , symfony/clock is required. Try running "composer require symfony/clock".` | The Meilisearch bridge needs a clock at construction. | `composer require symfony/clock`. |
| `The "…" message store does not exist.` (`ai:message-store:setup` / `drop`) | The argument is not a registered store id. | Pass the full service id, `ai.message_store.<type>.<name>`; shell completion lists them. |
| `The "…" message store does not support setup.` | The service does not implement `ManagedStoreInterface`. | Point the command at a managed store. |
| `No supported options.` (`InvalidArgumentException`) | `setup()` / `drop()` received options this store does not take. | Call them without options. |
| The same messages appear several times in MongoDB | `MongoDb\MessageStore::save()` inserts the whole bag again on every save. | `drop()` before saving, or keep one collection per conversation. |

## Limitations

- The component is experimental: APIs change between minor versions. Pin
  `symfony/ai-chat` and read `UPGRADE.md` in the monorepo before upgrading.
- No store serialises concurrent writers: two workers saving the same
  conversation interleave (Doctrine) or overwrite each other (Redis, last
  writer wins). Lock per conversation (Symfony Lock, a Redis mutex) when order
  matters.
- Streaming through the Session store is not recommended (`docs/components/chat.rst`):
  PHP session handling does not cope with a streamed response.
- The store replays the full history on every turn; trimming or summarising
  long conversations is left to the application.

## Usage

- **In-memory chat for tests**: `new Chat($agent, new Store())`, with
  `use Symfony\AI\Chat\InMemory\Store;`.
- **Doctrine DBAL chat**: `new Chat($agent, new DoctrineDbalMessageStore('chat_messages', $connection))`
  after running `ai:message-store:setup`.
- **Chat with tools**: build the agent with a `toolbox` (see `symfony-ai-agent`),
  then pass it to `Chat`.
- **Streamed reply**: `foreach ($chat->stream(Message::ofUser('...')) as $delta) { ... }`;
  the final message is persisted once the loop completes.
- **Set up or wipe the backend**: `php bin/console ai:message-store:setup <store>`,
  `php bin/console ai:message-store:drop <store> --force`.
- **Inspect recorded calls**: wrap the chat in `TraceableChat` and call `getCalls()`.

## References

- Read [`references/api-reference.md`](references/api-reference.md) when the
  user needs exact signatures: `Chat`, `ChatInterface`, the store interfaces,
  `InMemory\Store`, the traceable decorators, `MessageNormalizer`, every bridge.
- Read [`references/patterns.md`](references/patterns.md) when the user wants
  runnable code: in-memory, DBAL, agent with tools, streaming, traceable, or the
  choice between a message store, agent memory and a vector store.
- Read [`references/gotchas.md`](references/gotchas.md) when a chat misbehaves
  and the cause is not above: `initiate()` semantics, `drop()` on Doctrine,
  normaliser identifiers, race conditions.

## See also

- `symfony-ai-agent`: the agent that `Chat` wraps.
- `symfony-ai-platform`: raw LLM invocation underneath the agent.
- `symfony-ai-bundle`: `ai.chat` and `ai.message_store` wiring in `ai.yaml`.
