# Agent : Bridges

Read this when picking or configuring a message store, or a ready-made tool. Every class lives in `src/agent/src/Bridge/<Name>/` and ships as its own Composer package; re-verify constructors against the source before changing anything.

## Contents

- Message-store bridges (9)
- Serializer and stored format
- Migrating from `symfony/ai-chat`
- Tool bridges (14)
- `SimilaritySearch`
- `McpToolbox`
- `Filesystem`

## Message-store bridges (9)

Since 1.0 the message stores belong to the Agent component (they were `Symfony\AI\Chat\Bridge\*`): same package names, classes under `Symfony\AI\Agent\Bridge\<Backend>\`, all implementing `MessageStore\MessageStoreInterface` and keeping each conversation by the id of its `MessageBag`. Pass one as `new Agent(..., messageStore: $store)`.

| Backend | Package | Class | Constructor (required arguments first) | Managed |
| --- | --- | --- | --- | --- |
| PSR-6 cache | `symfony/ai-cache-message-store` | `Cache\MessageStore` | `(CacheItemPoolInterface $cache, string $cacheKey = '_message_store_cache', int $ttl = 86400)` | no |
| Cloudflare KV | `symfony/ai-cloudflare-message-store` | `Cloudflare\MessageStore` | `(HttpClientInterface $httpClient, string $namespace, string $accountId, string $apiKey, SerializerInterface $serializer = …, string $endpointUrl = 'https://api.cloudflare.com/client/v4/accounts')` | yes |
| Doctrine DBAL | `symfony/ai-doctrine-message-store` | `Doctrine\DoctrineDbalMessageStore` | `(string $tableName, Connection $dbalConnection, SerializerInterface $serializer = …, ClockInterface $clock = new MonotonicClock())` | yes |
| Meilisearch | `symfony/ai-meilisearch-message-store` | `Meilisearch\MessageStore` | `(HttpClientInterface $httpClient, string $endpointUrl, string $apiKey, ClockInterface $clock, string $indexName = '_message_store_meilisearch', SerializerInterface $serializer = …)` | yes |
| MongoDB | `symfony/ai-mongo-db-message-store` | `MongoDb\MessageStore` | `(MongoDB\Client $client, string $databaseName, string $collectionName, SerializerInterface $serializer = …)` | yes |
| Pogocache | `symfony/ai-pogocache-message-store` | `Pogocache\MessageStore` | `(HttpClientInterface $httpClient, string $host, string $password, string $key = '_message_store_pogocache', SerializerInterface $serializer = …)` | no |
| Redis | `symfony/ai-redis-message-store` | `Redis\MessageStore` | `(\Redis $redis, string $indexName, SerializerInterface $serializer = …)` | yes |
| HttpFoundation session | `symfony/ai-session-message-store` | `Session\MessageStore` | `(RequestStack $requestStack, string $sessionKey = 'messages')` | no |
| SurrealDB | `symfony/ai-surreal-db-message-store` | `SurrealDb\MessageStore` | `(HttpClientInterface $httpClient, string $endpointUrl, string $user, string $password, string $namespace, string $database, SerializerInterface $serializer = …, string $table = '_message_store_surrealdb', bool $isNamespacedUser = false)` | yes |

Plus `MessageStore\InMemoryMessageStore` in `symfony/ai-agent` itself: one process only, `reset()` empties it (tests, workers).

"Managed" stores implement `ManagedMessageStoreInterface`: call `setup()` once (or `ai:message-store:setup`) before the first conversation. `setup()` keeps what already exists: Doctrine creates the table only when missing, Meilisearch the index, MongoDB the collection, Cloudflare the KV namespace; Redis and SurrealDB have nothing to create. `drop()` removes every conversation but keeps the table, index, collection or namespace. `Cache`, `Pogocache` and `Session` are not managed since 1.0 and have no `setup()` or `drop()`; remove one conversation with `delete($id)` on any store.

Per-backend notes:

- **Doctrine DBAL**, not the ORM: the table has the columns `id` (the bag id, primary key), `version`, `messages` (the serialized bag) and `updated_at`, one row per conversation.
- **Redis** keys are `<indexName>:<conversation id>`; `drop()` scans and deletes them.
- **Cache** keys are `<cacheKey>.<conversation id>` and expire after `$ttl` seconds (one day by default); the bag goes through the cache's own serialization, there is no `$serializer` argument.
- **Session** keeps every conversation of the user's session in one array under `$sessionKey`: it dies with the session and loads all of them on every call.
- **Meilisearch** needs a `ClockInterface` to poll its tasks (`symfony/clock`).
- **MongoDB** stores the conversation under `_id` = the bag id.

Concurrency: when two requests answer the same conversation, the slower `save()` throws `Exception\ConflictException` ("The messages "…" were changed in the meantime, load them again before saving."). Doctrine DBAL, MongoDB and SurrealDB update only where the stored `version` is unchanged, and Redis uses `WATCH`/`MULTI`, so their check is atomic. Cache, Session, Cloudflare, Meilisearch, Pogocache (atomic only for the first save) and `InMemoryMessageStore` compare and then write: a second writer between the two can still overwrite the first. Lock per conversation id (Symfony Lock) when that matters.

## Serializer and stored format

Every bridge with a `$serializer` argument defaults to:

```php
$serializer = new Serializer([new MessageBagNormalizer(), new SourceCollectionNormalizer()], [new JsonEncoder()]);
```

`Platform\Serializer\MessageBagNormalizer` writes the whole conversation losslessly: message ids, metadata and every content type, with all content as `parts`. Objects in message metadata keep their class name; token usage and finish reason are handled directly, any other object goes to the serializer, so the default one throws `NotNormalizableValueException` ("Could not normalize object of type "DateTimeImmutable", no supporting normalizer found.") for, e.g., a date put in the metadata. Pass a serializer that knows it:

```php
use Symfony\AI\Agent\Bridge\Redis\MessageStore;
use Symfony\AI\Agent\Toolbox\Source\SourceCollectionNormalizer;
use Symfony\AI\Platform\Serializer\MessageBagNormalizer;
use Symfony\Component\Serializer\Encoder\JsonEncoder;
use Symfony\Component\Serializer\Normalizer\DateTimeNormalizer;
use Symfony\Component\Serializer\Serializer;

$store = new MessageStore($redis, 'chat', new Serializer([
    new MessageBagNormalizer(),
    new SourceCollectionNormalizer(),
    new DateTimeNormalizer(),
], [new JsonEncoder()]));
```

Because loading instantiates the stored class names, only load conversations from a storage that your application alone writes to. In the AI bundle, the stores receive the application's `serializer` service, on which the bundle registers `ai.platform.message_normalizer`, `ai.platform.message_bag_normalizer` and `ai.agent.source_collection_normalizer`.

## Migrating from `symfony/ai-chat`

| 0.x (`symfony/ai-chat`) | 1.0 |
| --- | --- |
| `new Chat($agent, new MessageStore($redis, 'chat'))` | `new Agent($platform, $model, [...], messageStore: new MessageStore($redis, 'chat'))` |
| `$chat->initiate(new MessageBag(Message::forSystem('…')))` | `SystemPromptInputProcessor('…')` on the agent; the system prompt is never stored |
| `$chat->submit(Message::ofUser('Hello'))` | `$agent->call(MessageBag::forId($conversationId, Message::ofUser('Hello')))` |
| `$chat->stream(...)` | `$agent->call($bag, ['stream' => true])`, then iterate `asStream()` to the end |
| one store instance (key) per conversation | one store, conversations keyed by the bag id |
| `Symfony\AI\Chat\Bridge\<Backend>\MessageStore` | `Symfony\AI\Agent\Bridge\<Backend>\MessageStore` |
| `Symfony\AI\Chat\MessageNormalizer` + `ToolCallNormalizer` | `Symfony\AI\Platform\Serializer\MessageNormalizer` (reads the old format, writes `parts`) |
| `Chat\Command\SetupStoreCommand` / `DropStoreCommand` | `Agent\Command\SetupMessageStoreCommand` / `DropMessageStoreCommand` |
| `Chat\TraceableMessageStore`, `TraceableChat` | `Agent\MessageStore\TraceableMessageStore`; trace the agent with `TraceableAgent` |
| `InMemory\Store` | `MessageStore\InMemoryMessageStore` |

The 1.0 bridges store each conversation as one serialized `MessageBag` and do **not** read what the 0.x stores wrote. For Doctrine, drop the old table (its name defaults to the store name) and set the store up again, since `setup()` keeps an existing table:

```bash
php bin/console dbal:run-sql 'DROP TABLE main'
php bin/console ai:message-store:setup ai.message_store.doctrine.dbal.main
```

## Tool bridges (14)

Each is a class in `src/agent/src/Bridge/<Name>/` exposing one or more `#[AsTool]` methods. Listed alphabetically:

| Bridge class                        | Tools exposed (per `#[AsTool]`)                                             | Source collection         |
| ----------------------------------- | --------------------------------------------------------------------------- | ------------------------- |
| `Brave\Brave`                       | `brave_search`                                                              | yes (HasSourcesInterface) |
| `Clock\Clock`                       | `clock`                                                                     | yes                       |
| `Filesystem\Filesystem`             | `filesystem_read/write/append/copy/move/delete/mkdir/exists/info/list` (10) | no                        |
| `Filesystem\PathValidator`          | (utility, not a tool)                                                       | :                         |
| `Firecrawl\Firecrawl`               | `firecrawl_scrape / crawl / map`                                            | no                        |
| `Mapbox\Mapbox`                     | `geocode`, `reverse_geocode`                                                | no                        |
| `Mcp\McpToolbox` (0.14)             | every tool of a remote MCP server, prefixed `<server>_` (a toolbox, not a tool) | :                     |
| `Ollama\Ollama`                     | `web_search`, `fetch_webpage`                                               | yes                       |
| `OpenMeteo\OpenMeteo`               | `weather_current`, `weather_forecast`                                       | no                        |
| `Scraper\Scraper`                   | `scraper`                                                                   | yes                       |
| `SerpApi\SerpApi`                   | `serpapi`                                                                   | yes                       |
| `SimilaritySearch\SimilaritySearch` | `similarity_search`                                                         | yes (since 1.0)           |
| `Tavily\Tavily`                     | `tavily_search`, `tavily_extract`                                           | yes                       |
| `Wikipedia\Wikipedia`               | `wikipedia_search`, `wikipedia_article`                                     | yes                       |
| `Youtube\YoutubeTranscriber`        | `youtube_transcript`                                                        | no                        |

## `SimilaritySearch`

`symfony/ai-similarity-search-tool`. Since 1.0 the constructor only takes a `Symfony\AI\Store\RetrieverInterface` (the `$promptTemplate` argument is gone), `__invoke()` returns a `SimilaritySearchResult` instead of a string, and `getUsedDocuments()` is removed.

```php
use Symfony\AI\Agent\Agent;
use Symfony\AI\Agent\Bridge\SimilaritySearch\DocumentSource;
use Symfony\AI\Agent\Bridge\SimilaritySearch\SimilaritySearch;
use Symfony\AI\Agent\Toolbox\Toolbox;

$agent = new Agent($platform, 'gpt-4o-mini', toolbox: new Toolbox([new SimilaritySearch($retriever)]), includeSources: true);
$result = $agent->call('What does our refund policy say?');

$documents = [];
foreach ($result->getMetadata()->get('sources', []) as $source) {
    if ($source instanceof DocumentSource) {
        $documents[] = $source->getDocument(); // VectorDocumentInterface
    }
}
```

The model receives a JSON list of the documents, each with its `id` and its metadata, or `[]` without results (`SimilaritySearchResult::jsonSerialize()`). To change that text, register a normalizer for `SimilaritySearchResult` in the serializer of the agent's `toolResultConverter` (`new ToolResultConverter(new Serializer([$yourNormalizer, new JsonSerializableNormalizer(), …], [new JsonEncoder()]))`). A `DocumentSource` takes its name from the document's `title` metadata, its reference from `source` (else the id) and its content from `text`.

## `McpToolbox`

`Mcp\McpToolbox` (package `symfony/ai-mcp-tool`, since 0.14) extends `AbstractToolbox` and exposes the tools of a remote MCP server through a `ToolsetInterface` (`ClientToolset($name, Mcp\Client, TransportInterface)`): `new Agent($platform, $model, toolbox: new McpToolbox($toolset))`. Combine it with local tools via `ChainToolbox`. A server whose tool listing fails is skipped for `retryAfter` seconds (default 60) instead of breaking the agent. In a Symfony app use the `mcp_server:` tool entry of `ai-bundle` instead.

`getTools()` copies a remote tool's MCP annotations into `Tool::getMetadata()`, keyed by their spec names (`readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`; `title` is dropped), so a `ToolCallRequested` listener can deny destructive calls with `$event->getDefinition()->isDestructive()` (1.0; `true` unless the tool is read-only or says `destructiveHint: false`). `McpToolbox` also implements `ResetInterface`: it caches the tool list once fetched, and `reset()` forgets it so the next listing asks the server again (a server marked unreachable is still skipped until its retry delay elapses). Call `reset()` between jobs in a long-running worker, or the agent keeps the tool list of the first request.

## `Filesystem`

`Filesystem\Filesystem`'s `write/append/copy/move/delete/mkdir` operations let the model mutate or remove files with no built-in confirmation : restrict writable paths with `Filesystem\PathValidator` and/or gate the call in a `ToolCallRequested` listener (`deny()`) before exposing it against a real filesystem. Since 1.0 the denied extensions default to `PathValidator::DEFAULT_DENIED_EXTENSIONS` (`php`, `php3`–`php8`, `phps`, `pht`, `phtml`, `phar`, `sh`, `exe`, `bat`) and the denied patterns to `PathValidator::DEFAULT_DENIED_PATTERNS` (`.*`, `*.env*`); a validated directory is also checked for files with a denied extension.
