# Store : Bridges Catalogue

Source of truth: `https://github.com/symfony/ai/tree/main/src/store/src/Bridge/`. The directory contains **25 packages** : each is an independent Composer package (e.g. `symfony/ai-pinecone-store`, `symfony/ai-postgres-store`) that you install alongside `symfony/ai-store` and `symfony/ai-platform`.

Each bridge exposes a concrete class : `Store`, `SearchStore` (AzureSearch), `VecStore` (Sqlite with `sqlite-vec`) or `OrmStore` (Doctrine) : implementing `StoreInterface`, and usually `ManagedStoreInterface` as well.

## Contents

- Bridge table (25 packages, managed or not)
- Index definition and metric names (1.0)
- Grouped by category
  - Cloud-managed
  - SQL / NoSQL databases
  - Search engines
  - Vector-native engines
  - Caching / ephemeral
- Doctrine (`OrmStore`, mirroring, 1.0)
- `StoreFactory`
- Picking a backend

## Bridge table

| # | Bridge | Class | Implements `ManagedStoreInterface` | Notes |
|---|---|---|---|---|
| 1 | AzureSearch | `Bridge\AzureSearch\SearchStore` | no | REST/HTTP. Class name is `SearchStore`, not `Store`. |
| 2 | Cache | `Bridge\Cache\Store` | yes | PSR-6 + `Symfony\Contracts\Cache\CacheInterface`. |
| 3 | ChromaDb | `Bridge\ChromaDb\Store` | yes | Requires `codewithkyrian/chromadb-php`. |
| 4 | ClickHouse | `Bridge\ClickHouse\Store` | yes | HTTP API; scoped client, build via `StoreFactory`. |
| 5 | Cloudflare | `Bridge\Cloudflare\Store` | yes | HTTP API for Vectorize. |
| 6 | Doctrine | `Bridge\Doctrine\OrmStore` | no | 1.0. Vectors in an `#[Embedding]` field of a Doctrine entity; queries return the entities. PostgreSQL + pgvector, MariaDB 11.7+, SQLite + sqlite-vec. |
| 7 | Elasticsearch | `Bridge\Elasticsearch\Store` | yes | HTTP API; scoped client, build via `StoreFactory`. |
| 8 | ManticoreSearch | `Bridge\ManticoreSearch\Store` | yes | HTTP API; scoped client, build via `StoreFactory`. |
| 9 | MariaDb | `Bridge\MariaDb\Store` | yes | Uses its own `Metric` enum (`Distance` before 1.0). |
| 10 | Meilisearch | `Bridge\Meilisearch\Store` | yes | Native `semanticRatio` support (hybrid). |
| 11 | Milvus | `Bridge\Milvus\Store` | yes | HTTP API; scoped client, build via `StoreFactory`. |
| 12 | MongoDb | `Bridge\MongoDb\Store` | yes | Atlas Vector Search; `setup()` creates the index from `dimensions` (1536), `metric` (`Metric::Euclidean`) and `indexFields`. |
| 13 | Neo4j | `Bridge\Neo4j\Store` | yes | Vector indexes via Neo4j; scoped client, build via `StoreFactory`. |
| 14 | OpenSearch | `Bridge\OpenSearch\Store` | yes | k-NN plugin; scoped client, build via `StoreFactory`. |
| 15 | Pinecone | `Bridge\Pinecone\Store` | yes | Serverless; `setup()` creates the index from `dimensions` (1536), `metric`, `cloud`, `region`. |
| 16 | Postgres | `Bridge\Postgres\Store` | yes | Requires `pgvector` 0.5.0+ (`hnsw` index). Uses its own `Metric` enum. |
| 17 | Qdrant | `Bridge\Qdrant\Store` | yes | HTTP API. |
| 18 | Redis | `Bridge\Redis\Store` | yes | Uses its own `Metric` enum (Redis-stack); 1536 dimensions by default (1.0, was 3072). |
| 19 | S3Vectors | `Bridge\S3Vectors\Store` | yes | AWS S3 Vectors (preview). |
| 20 | Sqlite | `Bridge\Sqlite\Store` and `Bridge\Sqlite\VecStore` | yes | Two stacks: pure SQLite (FTS5) or `sqlite-vec`. |
| 21 | Supabase | `Bridge\Supabase\Store` | no | REST/HTTP against pgvector; table pre-created by user; scoped client, build via `StoreFactory`. |
| 22 | SurrealDb | `Bridge\SurrealDb\Store` | yes | HTTP/WebSocket; SurrealDB 3 supported, `HNSW` index (0.15). |
| 23 | Typesense | `Bridge\Typesense\Store` | yes | HTTP API. |
| 24 | Vektor | `Bridge\Vektor\Store` | yes | Local on-disk vector store (`centamiv/vektor`). |
| 25 | Weaviate | `Bridge\Weaviate\Store` | yes | HTTP API. |

Total: **25 bridges**. Two implementations for Sqlite (`Store` for FTS5-only hybrid; `VecStore` for sqlite-vec).

## Index definition and metric names (1.0)

Since 1.0 the stores that create an index take its definition as constructor arguments, and their `setup()` throws `InvalidArgumentException` ("No supported options.") when it receives options:

| Store         | `setup()` option before 1.0                          | Constructor argument since 1.0            |
| ------------- | ---------------------------------------------------- | ----------------------------------------- |
| Elasticsearch | `dimensions`, `similarity`                           | `dimensions`, `metric`                    |
| MariaDB       | `dimensions`                                         | `dimensions`                              |
| MongoDB       | `fields`                                             | `indexFields`                             |
| OpenSearch    | `dimensions`, `space_type`                           | `dimensions`, `metric`                    |
| Pinecone      | `dimension`, `metric`, `cloud`, `region`             | `dimensions`, `metric`, `cloud`, `region` |
| Postgres      | `vector_size`, `vector_type`, `index_method`, `index_opclass` | `dimensions`, `vectorType`, `indexMethod`, `indexOpclass` |
| Redis         | `vector_size`, `index_method`, `extra_schema`        | `dimensions`, `indexMethod`, `extraSchema` |
| S3 Vectors    | `dimension`, `distanceMetric`, `dataType`, `metadata`, `encryption.kmsKeyId`, `tags` | `dimensions`, `metric`, `dataType`, `metadataConfiguration`, `kmsKeyId`, `tags` |

Every store and factory also names the vector metric `metric` and the vector size `dimensions`. Positional calls are unaffected, named ones break:

| Store           | Before 1.0                                   | 1.0                    |
| --------------- | -------------------------------------------- | ---------------------- |
| Elasticsearch, ManticoreSearch | `similarity`                  | `metric`               |
| MariaDB, Postgres, Redis | `distance`                          | `metric`               |
| Meilisearch, Typesense | `embeddingsDimension`                 | `dimensions`           |
| Milvus          | `metricType`                                 | `metric`               |
| MongoDB         | `embeddingsDimension`, `similarity`          | `dimensions`, `metric` |
| Neo4j, Qdrant   | `embeddingsDimension`, `embeddingsDistance`  | `dimensions`, `metric` |
| OpenSearch      | `spaceType`                                  | `metric`               |
| SQLite (`VecStore`) | `vectorDimension`, `distance`            | `dimensions`, `metric` |
| Supabase        | `vectorDimension`                            | `dimensions`           |
| SurrealDB       | `embeddingsDimension`, `strategy`            | `dimensions`, `metric` |

The `Distance` enums of the MariaDB, Postgres, Redis and SQLite bridges and the `Similarity` enum of MongoDB are renamed `Metric`, with the same cases (`use Symfony\AI\Store\Bridge\Postgres\Metric;`, `metric: Metric::Cosine`). Pinecone and S3 Vectors no longer require a dimension (1536 by default), and Redis defaults to 1536 instead of 3072. In-process scoring (`InMemory\Store`, `Cache\Store`) still uses `Distance\DistanceStrategy`.

## Grouped by category

### Cloud-managed

- **AzureSearch** : REST, semantic ranking; lifecycle is Azure-side. `query()` reads `limit` (default 5) and, since 0.15, runs an approximate (HNSW) vector query; pass `['exhaustive' => true]` for the previous exact KNN.
- **Cloudflare** : Workers AI Vectorize (HTTP, preview API).
- **Pinecone** : serverless or pod-based; `setup()` creates the index from the `dimensions` (1536 by default since 1.0), `metric`, `cloud` and `region` constructor arguments (`setup()` options before 1.0).
- **S3Vectors** : AWS S3 Vectors (preview service).

### SQL / NoSQL databases

- **ClickHouse** : HTTP API; vector columns.
- **MariaDb** : native vector type (MariaDB 11.7+, 11.8+ for `Metric::Distance`).
- **MongoDb** : Atlas Vector Search. `new Store($client, $db, $collection, $indexName, dimensions: 1536, metric: Metric::Cosine, indexFields: [...])` defines the index `setup()` creates; `indexFields` (the `fields` setup option before 1.0) adds filter fields only and rejects an entry for the vector path.
- **Neo4j** : vector indexes.
- **Postgres** : pgvector extension; the canonical self-hosted choice. `setup()` builds an `hnsw` index with the opclass of the metric (0.15); `dimensions`, `vectorType`, `indexMethod`, `indexOpclass` are constructor arguments since 1.0.
- **Redis** : Redis Stack / RediSearch. `dimensions`, `indexMethod` and `extraSchema` are constructor arguments since 1.0; the default index is 1536-dimensional (was 3072), so pass `dimensions: 3072` for Gemini embeddings.
- **Sqlite** : two stacks (`Store` with FTS5 hybrid; `VecStore` with `sqlite-vec`).
- **Supabase** : REST against pgvector (no `ManagedStoreInterface`).
- **SurrealDb** : multi-model (HTTP/WS). Since 0.15 `setup()` creates an `HNSW` index (was `MTREE`, removed in SurrealDB 3) and `query()` uses the `<|k,EF|>` operator; tune it with `query($q, ['ef' => 100])` (default `max(40, limit)`). `setup(['forceDatabaseCreation' => true])` (the only `setup()` option left; `ai:store:setup <store> --option forceDatabaseCreation=true` in the bundle) also creates the namespace and database, which SurrealDB 3 no longer does on first use. An existing `MTREE` index silently returns nothing: `REMOVE INDEX` it and rerun `setup()`.

### Search engines

- **Elasticsearch** : `dense_vector` fields + k-NN.
- **ManticoreSearch** : Manticore vector search.
- **Meilisearch** : built-in hybrid search (`semanticRatio`).
- **OpenSearch** : k-NN plugin.
- **Typesense** : vector search only. Its `supports()` returns true for
  `VectorQuery` and nothing else — no `TextQuery`, no `HybridQuery`.
- **Weaviate** : vector-first search engine.

### Vector-native engines

- **ChromaDb** : embeddable DB; uses `codewithkyrian/chromadb-php`.
- **Milvus** : production-grade vector DB.
- **Qdrant** : vector DB with filtering.
- **Vektor** : local on-disk (no separate server).

### Caching / ephemeral

- **Cache** : PSR-6 cache (Redis, filesystem, etc.); scores computed in PHP via `DistanceCalculator`.

## Doctrine (`OrmStore`, mirroring, 1.0)

`symfony/ai-doctrine-store` keeps each vector in a field of the entity itself, so a query returns entities instead of documents to load afterwards. It supports PostgreSQL with pgvector, MariaDB 11.7+ and SQLite with sqlite-vec; MySQL has no vector distance function, so mirror the entities into another store instead. With the AI bundle's `doctrine` store, the `vector` DBAL type and the `VECTOR_DISTANCE` DQL function are registered for you; without it, declare `Symfony\AI\Store\Bridge\Doctrine\Dbal\Types\VectorType` and `Symfony\AI\Store\Bridge\Doctrine\Orm\Query\VectorDistance` in `doctrine.yaml`.

```php
use Doctrine\ORM\Mapping as ORM;
use Symfony\AI\Platform\Vector\VectorInterface;
use Symfony\AI\Store\Bridge\Doctrine\Dbal\Metric;
use Symfony\AI\Store\Bridge\Doctrine\Mapping\Embedding;
use Symfony\AI\Store\Bridge\Doctrine\OrmStore;
use Symfony\AI\Store\Retriever;

#[ORM\Entity]
class Article
{
    // ...
    #[ORM\Column(type: 'vector', nullable: true)]
    #[Embedding(from: ['title', 'body'])]   // the fields joined into the text to embed
    private ?VectorInterface $embedding = null;
}

$store = new OrmStore($entityManager, Article::class, Metric::Cosine);   // Cosine | Euclidean | InnerProduct
foreach ((new Retriever($store, $vectorizer))->retrieve('articles about cats', ['limit' => 5, 'maxScore' => 0.5]) as $document) {
    echo $document->getEntity()->getTitle();   // EntityVectorDocument
}
```

- **Filling it.** `EntityEmbedder` (wraps a `Vectorizer`) sets the field; `EntityIndexer($entityManager, $embedder)->index(Article::class, ['only_missing' => true, 'batch_size' => 100])` embeds existing rows; `EmbeddingListener` on Doctrine's `onFlush` embeds new entities and those whose `from` fields changed. `IndexableEntityInterface::getIndexableContent()` builds the text in PHP instead. `SourceIndexer` and `DocumentIndexer` do not work: `add()` only writes vectors onto existing entities and throws for a document without one.
- **Write semantics.** `add()` and `remove()` flush the entity manager, writing every other pending change too; `remove()` and `clear()` set vectors to `null`, never delete entities; `count()` counts entities with a vector; document metadata is not stored.
- **Index in a migration only.** The mapping has no size: give the column `vector(1536)` and an HNSW index in a migration. `doctrine:schema:update` builds a btree index that fails above ~670 dimensions on PostgreSQL (`index row size ... exceeds btree version 4 maximum 2704`) and from 769 on MariaDB (`ERROR 1071`). MariaDB needs `columnDefinition: 'VECTOR(1536) NOT NULL'` for a vector index.
- **Rate limits and server errors do not fail the flush**: the listener logs a warning and saves the entity without a vector; run the indexer with `only_missing` later. An invalid API key fails the flush.
- **Mirroring.** Put `#[Embedding(from: [...])]` on the **class** (no vector field), register `Mirror\MirrorListener` on `onFlush` and `postFlush` with the target store, and read hits back as entities with `Mirror\EntityRetriever(new Retriever($mirrorStore, $vectorizer), $entityManager)`. Document ids are UUIDs built from the class and entity id: renaming the entity class orphans the old documents. Inside a wider transaction, `postFlush` writes the store before the outer commit, so a rollback leaves stale documents; re-run the indexer.
- **Bundle**: `ai.store.doctrine.<name>` with `entity`, `metric`, `entity_manager`, `vectorizer` (embeds on flush and registers the `ai:store:index <name>` indexer) and `mirror_to` (see `symfony-ai-bundle`).

## `StoreFactory`

Some bridges ship a `StoreFactory` class that builds the store from environment configuration:

- `Bridge\AzureSearch\StoreFactory`
- `Bridge\Cache\StoreFactory`
- `Bridge\ChromaDb\StoreFactory`
- `Bridge\ClickHouse\StoreFactory`
- `Bridge\Cloudflare\StoreFactory`
- `Bridge\Elasticsearch\StoreFactory`
- `Bridge\ManticoreSearch\StoreFactory`
- `Bridge\Meilisearch\StoreFactory`
- `Bridge\Milvus\StoreFactory`
- `Bridge\Neo4j\StoreFactory`
- `Bridge\OpenSearch\StoreFactory`
- `Bridge\Postgres\StoreFactory`
- `Bridge\Qdrant\StoreFactory`
- `Bridge\Sqlite\StoreFactory`
- `Bridge\Supabase\StoreFactory`
- `Bridge\SurrealDb\StoreFactory`
- `Bridge\Typesense\StoreFactory`
- `Bridge\Weaviate\StoreFactory`

Use them in `services.yaml` to keep credentials and DSNs in `.env`.

### Scoped-client stores (since 0.14)

The Elasticsearch, ManticoreSearch, Milvus, Neo4j, OpenSearch and Supabase `Store` constructors no longer take an endpoint or credentials: they take an `HttpClientInterface` **already scoped** to the instance as first argument (ClickHouse works the same way). Endpoint and credentials moved to `StoreFactory::create()`, which wraps the client in a `ScopingHttpClient` and applies the credentials:

| Bridge          | `StoreFactory::create()` signature |
|-----------------|------------------------------------------------------------------------|
| ClickHouse      | `create(string $databaseName = 'default', string $tableName = 'embedding', ?string $dsn = null, ?HttpClientInterface $httpClient = null)` |
| Elasticsearch   | `create(string $indexName, ?string $endpoint = null, ?HttpClientInterface $httpClient = null, string $vectorsField = '_vectors', int $dimensions = 1536, string $metric = 'cosine')` |
| ManticoreSearch | `create(string $table, ?string $endpoint = null, ?HttpClientInterface $httpClient = null, string $field = '_vectors', string $type = 'hnsw', string $metric = 'cosine', int $dimensions = 1536, string $quantization = '8bit')` |
| Milvus          | `create(string $database, string $collection, ?string $endpoint = null, ?string $apiKey = null, ?HttpClientInterface $httpClient = null, …)` : bearer token |
| Neo4j           | `create(string $databaseName, string $vectorIndexName, string $nodeName, ?string $endpoint = null, ?string $username = null, ?string $password = null, ?HttpClientInterface $httpClient = null, …)` : basic auth |
| OpenSearch      | `create(string $indexName, ?string $endpoint = null, ?HttpClientInterface $httpClient = null, string $vectorsField = '_vectors', int $dimensions = 1536, string $metric = 'l2')` |
| Supabase        | `create(?string $endpoint = null, ?string $apiKey = null, ?HttpClientInterface $httpClient = null, string $table = 'documents', …)` : `apikey` header + bearer |

```php
use Symfony\AI\Store\Bridge\Milvus\StoreFactory;

$store = StoreFactory::create('my_database', 'my_documents', 'http://localhost:19530', 'api-key', $httpClient);
```

Omit the endpoint and pass a pre-scoped `$httpClient` (e.g. a `scoped_clients` service from `framework.http_client`) to keep the connection details out of PHP. Credentials without an endpoint throw `InvalidArgumentException`.

**Upgrading from 0.13:** do not keep positional arguments on `new Store(...)`. On several bridges the old call does not fail : the values shift into the wrong parameters (the endpoint becomes the index name, and so on). Switch to the factory or to named arguments.

## Picking a backend

| Need | Pick |
|---|---|
| Self-host, no extra infra | Postgres + pgvector, or Sqlite (`VecStore` for sqlite-vec). |
| Search Doctrine entities, vectors in the entity | Doctrine `OrmStore` (PostgreSQL + pgvector, MariaDB 11.7+, SQLite + sqlite-vec); MySQL: mirror to another store. |
| Managed, pay-as-you-go | Pinecone (serverless), Cloudflare Vectorize. |
| Hybrid search out of the box | Sqlite, Postgres, `Cache\Store`, `InMemory\Store` (all three query types); Meilisearch accepts `HybridQuery` but not `TextQuery`. |
| In-memory test store | `InMemory\Store` (not a bridge). |
| Ephemeral / process-level | `Bridge\Cache\Store`. |
| Largest open-source communities | Qdrant, Weaviate, Milvus. |
| Multi-model graph | Neo4j. |

For RAG recipes, see `references/patterns.md`.
