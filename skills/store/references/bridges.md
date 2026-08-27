# Store : Bridges Catalogue

Source of truth: `https://github.com/symfony/ai/tree/main/src/store/src/Bridge/`. The directory contains **24 packages** : each is an independent Composer package (e.g. `symfony/ai-pinecone-store`, `symfony/ai-postgres-store`) that you install alongside `symfony/ai-store` and `symfony/ai-platform`.

Each bridge exposes a concrete class : `Store`, `SearchStore` (AzureSearch), or `VecStore` (Sqlite with `sqlite-vec`) : implementing `StoreInterface`, and usually `ManagedStoreInterface` as well.

| # | Bridge | Class | Implements `ManagedStoreInterface` | Notes |
|---|---|---|---|---|
| 1 | AzureSearch | `Bridge\AzureSearch\SearchStore` | no | REST/HTTP. Class name is `SearchStore`, not `Store`. |
| 2 | Cache | `Bridge\Cache\Store` | yes | PSR-6 + `Symfony\Contracts\Cache\CacheInterface`. |
| 3 | ChromaDb | `Bridge\ChromaDb\Store` | yes | Requires `codewithkyrian/chromadb-php`. |
| 4 | ClickHouse | `Bridge\ClickHouse\Store` | yes | HTTP API. |
| 5 | Cloudflare | `Bridge\Cloudflare\Store` | yes | HTTP API for Vectorize. |
| 6 | Elasticsearch | `Bridge\Elasticsearch\Store` | yes | HTTP API. |
| 7 | ManticoreSearch | `Bridge\ManticoreSearch\Store` | yes | HTTP API. |
| 8 | MariaDb | `Bridge\MariaDb\Store` | yes | Uses its own `Distance` enum. |
| 9 | Meilisearch | `Bridge\Meilisearch\Store` | yes | Native `semanticRatio` support (hybrid). |
| 10 | Milvus | `Bridge\Milvus\Store` | yes | HTTP API. |
| 11 | MongoDb | `Bridge\MongoDb\Store` | yes | Atlas Vector Search index must be pre-created. |
| 12 | Neo4j | `Bridge\Neo4j\Store` | yes | Vector indexes via Neo4j. |
| 13 | OpenSearch | `Bridge\OpenSearch\Store` | yes | k-NN plugin. |
| 14 | Pinecone | `Bridge\Pinecone\Store` | yes | Serverless; `setup()` requires `dimension` option. |
| 15 | Postgres | `Bridge\Postgres\Store` | yes | Requires `pgvector` extension. Uses its own `Distance` enum. |
| 16 | Qdrant | `Bridge\Qdrant\Store` | yes | HTTP API. |
| 17 | Redis | `Bridge\Redis\Store` | yes | Uses its own `Distance` enum (Redis-stack). |
| 18 | S3Vectors | `Bridge\S3Vectors\Store` | yes | AWS S3 Vectors (preview). |
| 19 | Sqlite | `Bridge\Sqlite\Store` and `Bridge\Sqlite\VecStore` | yes | Two stacks: pure SQLite (FTS5) or `sqlite-vec`. |
| 20 | Supabase | `Bridge\Supabase\Store` | no | REST/HTTP against pgvector; table pre-created by user. |
| 21 | SurrealDb | `Bridge\SurrealDb\Store` | yes | HTTP/WebSocket. |
| 22 | Typesense | `Bridge\Typesense\Store` | yes | HTTP API. |
| 23 | Vektor | `Bridge\Vektor\Store` | yes | Local on-disk vector store (`centamiv/vektor`). |
| 24 | Weaviate | `Bridge\Weaviate\Store` | yes | HTTP API. |

Total: **24 bridges**. Two implementations for Sqlite (`Store` for FTS5-only hybrid; `VecStore` for sqlite-vec).

## Grouped by category

### Cloud-managed

- **AzureSearch** : REST, semantic ranking; lifecycle is Azure-side.
- **Cloudflare** : Workers AI Vectorize (HTTP, preview API).
- **Pinecone** : serverless or pod-based; requires `dimension` in `setup()` options.
- **S3Vectors** : AWS S3 Vectors (preview service).

### SQL / NoSQL databases

- **ClickHouse** : HTTP API; vector columns.
- **MariaDb** : native vector type.
- **MongoDb** : Atlas Vector Search.
- **Neo4j** : vector indexes.
- **Postgres** : pgvector extension; the canonical self-hosted choice.
- **Redis** : Redis Stack / RediSearch.
- **Sqlite** : two stacks (`Store` with FTS5 hybrid; `VecStore` with `sqlite-vec`).
- **Supabase** : REST against pgvector (no `ManagedStoreInterface`).
- **SurrealDb** : multi-model (HTTP/WS).

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

## `StoreFactory`

Some bridges ship a `StoreFactory` class that builds the store from environment configuration:

- `Bridge\AzureSearch\StoreFactory`
- `Bridge\Cache\StoreFactory`
- `Bridge\ChromaDb\StoreFactory`
- `Bridge\Cloudflare\StoreFactory`
- `Bridge\Meilisearch\StoreFactory`
- `Bridge\Postgres\StoreFactory`
- `Bridge\Qdrant\StoreFactory`
- `Bridge\Sqlite\StoreFactory`
- `Bridge\SurrealDb\StoreFactory`
- `Bridge\Typesense\StoreFactory`
- `Bridge\Weaviate\StoreFactory`

Use them in `services.yaml` to keep credentials and DSNs in `.env`.

## Picking a backend

| Need | Pick |
|---|---|
| Self-host, no extra infra | Postgres + pgvector, or Sqlite (`VecStore` for sqlite-vec). |
| Managed, pay-as-you-go | Pinecone (serverless), Cloudflare Vectorize. |
| Hybrid search out of the box | Sqlite, Postgres, `Cache\Store`, `InMemory\Store` (all three query types); Meilisearch accepts `HybridQuery` but not `TextQuery`. |
| In-memory test store | `InMemory\Store` (not a bridge). |
| Ephemeral / process-level | `Bridge\Cache\Store`. |
| Largest open-source communities | Qdrant, Weaviate, Milvus. |
| Multi-model graph | Neo4j. |

For RAG recipes, see `references/patterns.md`.
