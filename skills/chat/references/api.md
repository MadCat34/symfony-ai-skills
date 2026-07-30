# Chat : API Reference

Read this when the user asks for the full signature catalogue of the Chat framework. Everything below is grounded in the source files under `src/chat/src/`.

## Core namespaces

```php
Symfony\AI\Chat\
├── Chat                              (concrete, final)
├── ChatInterface                     (initiate, submit, stream)
├── MessageStoreInterface             (save, load)
├── ManagedStoreInterface             (setup, drop — SEPARATE interface)
├── InMemory\Store                    (built-in, both interfaces)
├── ChatStreamListener                (persists streamed assistant message)
├── TraceableChat                     (decorator, ChatInterface)
├── TraceableMessageStore             (decorator)
├── MessageNormalizer                 (Symfony Serializer normalizer)
└── Bridge\
    ├── Cache\MessageStore
    ├── Cloudflare\MessageStore
    ├── Doctrine\DoctrineDbalMessageStore
    ├── Meilisearch\MessageStore
    ├── MongoDb\MessageStore
    ├── Pogocache\MessageStore
    ├── Redis\MessageStore
    ├── Session\MessageStore
    └── SurrealDb\MessageStore
```

`ManagedStoreInterface` does NOT extend `MessageStoreInterface`. They are two independent marker interfaces. `Chat`'s constructor requires an intersection of both.

## `Chat`

```php
namespace Symfony\AI\Chat;

final class Chat implements ChatInterface
{
    public function __construct(
        private readonly AgentInterface $agent,
        private readonly MessageStoreInterface&ManagedStoreInterface $store,
    );

    public function initiate(MessageBag $messages): void;
    public function submit(UserMessage $message): AssistantMessage;
    public function stream(UserMessage $message): \Generator;
}
```text

- `initiate()` calls `store->drop()` then `store->save($messages)`. Useful for seeding a system prompt or pre-loading history.
- `submit()` loads history, appends the user message, calls the agent, appends the assistant message, persists, returns the assistant message.
- `stream()` loads history, appends the user message, calls the agent with `['stream' => true]`, attaches a `ChatStreamListener`, and yields `DeltaInterface` events. The final message is built and persisted on `CompleteEvent`.

`Chat` has no `getMessages()`, `clear()`, or chat-id concept. There is no `send()` method.

## `ChatInterface`

```php
namespace Symfony\AI\Chat;

interface ChatInterface
{
    public function initiate(MessageBag $messages): void;

    /** @throws \Symfony\AI\Agent\Exception\ExceptionInterface */
    public function submit(UserMessage $message): AssistantMessage;

    /** @return \Generator<\Symfony\AI\Platform\Result\Stream\Delta\DeltaInterface> */
    public function stream(UserMessage $message): \Generator;
}
```

## `MessageStoreInterface`

```php
namespace Symfony\AI\Chat;

interface MessageStoreInterface
{
    public function save(MessageBag $messages): void;
    public function load(): MessageBag;
}
```text

No `$chatId` parameter. `save()` and `load()` are the only members. There is no `clear()`.

## `ManagedStoreInterface`

```php
namespace Symfony\AI\Chat;

interface ManagedStoreInterface
{
    /** @param array<mixed> $options */
    public function setup(array $options = []): void;
    public function drop(): void;
}
```

Independent of `MessageStoreInterface`. Some bridges implement both; the `AiBundle` console commands require services implementing this interface.

## `InMemory\Store`

```php
namespace Symfony\AI\Chat\InMemory;

final class Store implements ManagedStoreInterface, MessageStoreInterface, ResetInterface
{
    public function __construct(
        private readonly string $identifier = '_message_store_memory',
    );

    public function setup(array $options = []): void;
    public function save(MessageBag $messages): void;
    public function load(): MessageBag;
    public function drop(): void;
    public function reset(): void;
}
```text

Backed by a single `MessageBag` keyed by `$identifier`. Useful for tests and single-process scripts.

## `ChatStreamListener`

```php
namespace Symfony\AI\Chat;

final class ChatStreamListener extends AbstractStreamListener
{
    public function __construct(
        private readonly MessageBag $messages,
        private readonly MessageStoreInterface $store,
    );

    public function onDelta(DeltaEvent $event): void;
    public function onComplete(CompleteEvent $event): void;
}
```

`onDelta()` concatenates `TextDelta` into a private buffer. `onComplete()` builds an `AssistantMessage` from the buffer, merges the result metadata, appends it to the bag, and calls `store->save()`.

## `TraceableChat`

```php
namespace Symfony\AI\Chat;

final class TraceableChat implements ChatInterface, ResetInterface
{
    public function __construct(
        private readonly ChatInterface $chat,
        private readonly ClockInterface $clock = new MonotonicClock(),
    );

    public function initiate(MessageBag $messages): void;
    public function submit(UserMessage $message): AssistantMessage;
    public function stream(UserMessage $message): \Generator;

    /** @return list<array{action: string, bag?: MessageBag, message?: UserMessage, submitted_at?: \DateTimeImmutable, streamed_at?: \DateTimeImmutable, initiated_at?: \DateTimeImmutable}> */
    public function getCalls(): array;

    public function reset(): void;
}
```text

Useful for tests and profiler wiring. `reset()` clears the call log and delegates to the wrapped `chat` if it implements `ResetInterface`.

## `TraceableMessageStore`

```php
namespace Symfony\AI\Chat;

final class TraceableMessageStore implements ManagedStoreInterface, MessageStoreInterface, ResetInterface
{
    public function __construct(
        private readonly MessageStoreInterface|ManagedStoreInterface $messageStore,
        private readonly ClockInterface $clock,
    );

    public function setup(array $options = []): void;
    public function save(MessageBag $messages): void;
    public function load(): MessageBag;
    public function drop(): void;

    /** @return list<array{bag: MessageBag, saved_at: \DateTimeImmutable}> */
    public function getCalls(): array;

    public function reset(): void;
}
```

`setup()` and `drop()` are no-ops when the wrapped store does not implement `ManagedStoreInterface`.

## `MessageNormalizer`

```php
namespace Symfony\AI\Chat;

final class MessageNormalizer implements NormalizerInterface, DenormalizerInterface, NormalizerAwareInterface
{
    public function normalize(mixed $data, ?string $format = null, array $context = []): array;
    public function denormalize(mixed $data, string $type, ?string $format = null, array $context = []): mixed;
    public function supportsNormalization(mixed $data, ?string $format = null, array $context = []): bool;
    public function supportsDenormalization(mixed $data, string $type, ?string $format = null, array $context = []): bool;
    public function getSupportedTypes(?string $format): array;
}
```text

Serialises and deserialises `MessageInterface` (and its concrete subclasses: `SystemMessage`, `UserMessage`, `AssistantMessage`, `ToolCallMessage`). Handles `Text`, `Image`, `File`, `Document`, `Audio`, `ImageUrl`, `DocumentUrl`, `Thinking`, and `ToolCall` content. The `$context['identifier']` key controls which field holds the UUID (`id` by default, `_id` for MongoDB, `messageId` for SurrealDB).

## Bridges

Every bridge ships a `MessageStore` (or `DoctrineDbalMessageStore` for Doctrine) that implements both `MessageStoreInterface` and `ManagedStoreInterface`. Detailed method signatures:

### `Bridge\Doctrine\DoctrineDbalMessageStore`

```php
public function __construct(
    string $tableName,                          // first positional argument
    Doctrine\DBAL\Connection $dbalConnection,
    ?SerializerInterface $serializer = null,
    ?Psr\Clock\ClockInterface $clock = null,
);

public function setup(array $options = []): void;  // creates table via Schema
public function drop(): void;                       // deletes rows (NOT the table)
public function save(MessageBag $messages): void;
public function load(): MessageBag;
```

Uses `Doctrine\DBAL\Connection` only. The default table name is not provided : callers must pass it (e.g. `'chat_messages'`). `drop()` clears rows, not the table.

### `Bridge\Redis\MessageStore`

```php
public function __construct(
    \Redis $redis,
    string $indexName,
    ?SerializerInterface $serializer = null,
);
```text

`setup()` writes an empty JSON array at the key. `drop()` resets it to empty. `save()` overwrites the JSON-encoded `MessageBag`. `load()` decodes and returns.

### `Bridge\MongoDb\MessageStore`

```php
public function __construct(
    MongoDB\Client $client,
    string $databaseName,
    string $collectionName,
    ?SerializerInterface $serializer = null,
);
```

`setup(array $options)` forwards `$options` to `createCollection`. Identifier is `_id`.

### `Bridge\Cache\MessageStore`

```php
public function __construct(
    Psr\Cache\CacheItemPoolInterface $cache,
    string $cacheKey = '_message_store_cache',
    int $ttl = 86400,
);
```text

Implements `setup()` (seeds an empty `MessageBag`) and `drop()` (`deleteItem`). `load()` falls back to a fresh `MessageBag` on cache miss.

### `Bridge\Session\MessageStore`

```php
public function __construct(
    Symfony\Component\HttpFoundation\RequestStack $requestStack,
    string $sessionKey = 'messages',
);
```

`setup()` initialises the session. `drop()` removes the key. `load()` defaults to an empty bag.

### `Bridge\Meilisearch\MessageStore`

```php
public function __construct(
    HttpClientInterface $httpClient,
    string $endpointUrl,
    #[\SensitiveParameter] string $apiKey,
    ClockInterface $clock,
    string $indexName = '_message_store_meilisearch',
    ?SerializerInterface $serializer = null,
);
```text

`setup()` creates the index with `addedAt` sortable. `drop()` deletes all documents. Throws `RuntimeException` if `symfony/clock` is missing.

### `Bridge\Cloudflare\MessageStore`

```php
public function __construct(
    HttpClientInterface $httpClient,
    string $namespace,
    #[\SensitiveParameter] string $accountId,
    #[\SensitiveParameter] string $apiKey,
    ?SerializerInterface $serializer = null,
    string $endpointUrl = 'https://api.cloudflare.com/client/v4/accounts',
);
```

`setup()` creates the KV namespace if missing. `drop()` deletes all keys in the namespace. `save()` uses bulk put keyed by message UUID.

### `Bridge\SurrealDb\MessageStore`

```php
public function __construct(
    HttpClientInterface $httpClient,
    string $endpointUrl,
    string $user,
    #[\SensitiveParameter] string $password,
    string $namespace,
    string $database,
    ?SerializerInterface $serializer = null,
    string $table = '_message_store_surrealdb',
    bool $isNamespacedUser = false,
);
```text

`setup()` is a no-op (records the option); throws if `$options` is non-empty. Identifier is `messageId` (SurrealDB rewrites the `id` field on read-back).

### `Bridge\Pogocache\MessageStore`

```php
public function __construct(
    HttpClientInterface $httpClient,
    string $host,
    #[\SensitiveParameter] string $password,
    string $key = '_message_store_pogocache',
    ?SerializerInterface $serializer = null,
);
```

`setup()` PUTs the key. `drop()` PUTs an empty payload. `save()` PUTs the normalised messages.

## Console commands

```php
namespace Symfony\AI\Chat\Command;

#[AsCommand(name: 'ai:message-store:setup')]
final class SetupStoreCommand extends Command
{
    public function __construct(ServiceLocator<ManagedStoreInterface> $stores);
}

#[AsCommand(name: 'ai:message-store:drop')]
final class DropStoreCommand extends Command
{
    public function __construct(ServiceLocator<ManagedStoreInterface> $stores);
}
```text

Both take a `<store>` argument (the service id of a `ManagedStoreInterface`). `drop` requires `--force` or returns `Command::FAILURE`.

## Exceptions

```php
namespace Symfony\AI\Chat\Exception;

interface ExceptionInterface extends \Throwable {}

class InvalidArgumentException extends \InvalidArgumentException implements ExceptionInterface {}
class LogicException extends \LogicException implements ExceptionInterface {}
class RuntimeException extends \RuntimeException implements ExceptionInterface {}
```

All Chat-component exceptions implement `ExceptionInterface`. Catch this marker interface for component-scoped error handling.
