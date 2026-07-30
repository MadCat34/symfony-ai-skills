# Chat : Gotchas

Exhaustive list, grounded in the source files under `src/chat/src/`.

## `submit()`, not `send()`

`ChatInterface` exposes `submit(UserMessage)`, not `send()`. `submit()` returns an `AssistantMessage`. There is no `send()` overload accepting a `string` either : build a `UserMessage` via `Message::ofUser(...)` (or `Message::ofSystem(...)`, etc.) and pass it in.

```php
// Correct
$reply = $chat->submit(Message::ofUser('Hello!'));

// Wrong — method does not exist
$reply = $chat->send('Hello!');
```

## No `chatId`, no `getMessages()`, no `clear()`

`MessageStoreInterface::save()` and `load()` take no identifier. There is no `getMessages()` on `Chat`. There is no `clear()` on either `Chat` or `MessageStoreInterface`. Each conversation gets its own store instance : typically one per HTTP request, per session, or per worker job.

```php
// Wrong — no such method
$bag = $chat->getMessages();

// Wrong — no chatId parameter
$store->save('conv-1', $messages);

// Correct — one store per session
$store = new InMemory\Store(); // or any bridge, keyed by constructor ($key, $cacheKey, $indexName, $sessionKey)
$chat = new Chat($agent, $store);
```

If you need parallel sessions, override the store's identifier (`$cacheKey`, `$sessionKey`, `$indexName`, `$tableName`) per session : every bridge supports a custom key.

## `MessageBag` IS mutated

`Chat::submit()` calls `$messages->add(...)` on the bag returned by `store->load()`. `ChatStreamListener::onComplete()` also appends. The bag is not immutable.

```php
$bag = $store->load(); // same reference held by Chat
$chat->submit(Message::ofUser('Hi'));
// $bag now contains the user prompt AND the assistant reply;
// do not assume it stayed at the size you saw earlier.
```

Clone the bag yourself if you need a snapshot.

## Constructor intersection type

`Chat::__construct(AgentInterface $agent, MessageStoreInterface&ManagedStoreInterface $store)`. The store must implement **both** interfaces. The built-in `InMemory\Store` and every bridge (`Cache`, `Cloudflare`, `Doctrine`, `Meilisearch`, `MongoDb`, `Pogocache`, `Redis`, `Session`, `SurrealDb`) implement both. A custom store that only implements `MessageStoreInterface` will fail PHP's type check at instantiation.

```php
// Wrong — interface mismatch
$chat = new Chat($agent, new MyReadOnlyStore()); // does not implement ManagedStoreInterface
```

## Doctrine = DBAL, not ORM

`Bridge\Doctrine\DoctrineDbalMessageStore` takes a `Doctrine\DBAL\Connection` (not the ORM layer). There is no `ChatMessage` entity : the bridge creates a flat table via DBAL schema introspection (`Schema::createTable`).

```php
// Correct
$store = new DoctrineDbalMessageStore('chat_messages', $connection);

// Wrong — Doctrine bridge does not take an $entityManager argument
$store = new DoctrineDbalMessageStore($entityManager, 'chat_messages');
```

The constructor signature is `(string $tableName, Connection $dbalConnection, ?SerializerInterface $serializer = null, ?ClockInterface $clock = null)`. Table name is **first** and does not have a default : you must pass it.

## `setup()` per managed store

Every bridge implements `setup()`. This includes `Cache` and `Session`, contrary to the previous claim that "Cache needs no setup". Production deployments must call `setup()` (or run `ai:message-store:setup <service-id>`) before the first `submit()`.

```php
// Cache bridge — yes, this exists and is recommended
$store = new Cache\MessageStore($cachePool, 'chat_cache_key');
$store->setup(); // seeds an empty MessageBag into the cache
```

## `drop()` is non-destructive on Doctrine

`DoctrineDbalMessageStore::drop()` deletes rows from the table : it does NOT drop the table. The schema remains; subsequent calls to `setup()` will return early because the table exists. If you want to start fresh, drop the table manually (or via a migration rollback) before calling `setup()`.

## Per-instance state

Channels like Redis, MongoDB, Cache, and Session are essentially singletons keyed by constructor argument. Default keys (`$cacheKey = '_message_store_cache'`, `$sessionKey = 'messages'`, `$indexName = '_message_store_meilisearch'`) are not random : if you reuse one process for multiple sessions, override them per session or you will get collisions.

```php
// Per session
$store = new Cache\MessageStore($cachePool, 'chat_' . $sessionId);
$store = new Redis\MessageStore($redis, 'chat_' . $sessionId);
$store = new Session\MessageStore($requestStack, 'chat_' . $sessionId);
```

## Streaming persists on completion

`ChatStreamListener::onComplete()` is the only place that appends the assembled assistant message during a streaming call. If you break out of the `foreach` loop early, the listener never fires and the partial message is lost.

```php
foreach ($chat->stream(Message::ofUser('...')) as $delta) {
    if (someCondition()) {
        break; // BAD — final message is not persisted
    }
}
```

If you need to interrupt a stream and still persist, drain the generator to completion first, then truncate client-side.

## Meilisearch requires `symfony/clock`

The Meilisearch bridge's constructor throws `RuntimeException` if `symfony/clock` is not installed. The bridge uses `ClockInterface::sleep()` to poll task status. Install `symfony/clock` explicitly.

```php
// Composer
composer require symfony/ai-chat-meilisearch symfony/clock
```

## Console commands require `ManagedStoreInterface`

The `ai:message-store:setup` and `ai:message-store:drop` commands resolve a `<store>` service-id through a `ServiceLocator<ManagedStoreInterface>`. If the service does not implement `ManagedStoreInterface`, the command throws `RuntimeException` at `initialize()` time. The `drop` command additionally requires `--force` or returns `Command::FAILURE`.

## Race conditions on shared stores

Two PHP-FPM workers (or two Messenger consumers) handling the same `Chat`/`Store` instance can interleave `save()` calls. The Doctrine bridge inserts rows in order : two concurrent inserts may write out of order. The MongoDB and Redis bridges overwrite the whole bag atomically, so the last writer wins. Serialize per session (`flock`, Redis mutex, Symfony Lock) if you need strict ordering.

## `MessageNormalizer` identifier per bridge

`MessageNormalizer::normalize()` writes the message UUID under `$context['identifier'] ?? 'id'`. The MongoDB bridge overrides this to `_id`, the SurrealDB bridge to `messageId` (because SurrealDB rewrites the `id` field on read-back). If you serialise a `MessageBag` yourself with a different identifier, the normalizer round-trip will produce a new UUID instead of preserving the original.

## `initiate()` drops existing content

`Chat::initiate()` calls `store->drop()` before `store->save()`. Use it only when you intend to start a fresh conversation (e.g. on user "new chat" action). Calling `initiate()` mid-conversation silently wipes the history.

## See also

- `references/api.md` : full type and method catalogue.
- `references/patterns.md` : compile-ready samples.
- `agent` skill : for the agent that `Chat` wraps.
