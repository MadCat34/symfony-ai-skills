---
title: RAG with Postgres pgvector
composes: platform, store, agent
target-version: PHP 8.2+ / Symfony 6.4 | 7.4 | 8.0
last-verified: 2026-07-28
---

> Symfony AI is **experimental** : APIs may break between releases. Always check `UPGRADE.md` in the [symfony/ai monorepo](https://github.com/symfony/ai) before upgrading.

Same RAG pattern as the Pinecone recipe, but self-hosted on Postgres using the `pgvector` extension. Pick this when you already run Postgres and want one database for everything.

## Composes

- **`platform`** : `Symfony\AI\Platform\Bridge\OpenAi\Factory` for chat and embeddings.
- **`store`** : `Symfony\AI\Store\Bridge\Postgres\Store` (managed; supports `VectorQuery`, `TextQuery`, `HybridQuery`) plus `Document\Vectorizer` and `Indexer\DocumentIndexer`.
- **`agent`** : `Agent`, `Toolbox`, and `Toolbox\AgentProcessor`.

## Installation

```bash
composer require symfony/ai-platform symfony/ai-store symfony/ai-agent
composer require symfony/ai-open-ai-platform
composer require symfony/ai-postgres-store
composer require symfony/ai-bundle   # optional YAML wiring
```

## Prerequisites

The recipe requires two things outside of Symfony AI:

1. **PostgreSQL 12+** reachable via the configured `$DATABASE_URL`.
2. **The `pgvector` extension** installed in the target database. Without it, the `vector` column type does not exist and `setup()` fails with an SQL error. To install:

   ```bash
   psql "$DATABASE_URL" -c "CREATE EXTENSION IF NOT EXISTS vector;"
   ```

   On Debian/Ubuntu systems the OS package is `postgresql-15-pgvector` (or matching the server major version); on RHEL-family systems it ships as `pgvector_$VERSION`. On managed services (AWS RDS / Cloud SQL / Neon / Supabase) the extension is pre-installed or enabled via the provider's console.

## Database setup

The store's `setup()` then creates the table and the IVFFlat index on first run; see `src/store/src/Bridge/Postgres/Store.php`.

## Configuration

`config/packages/ai.yaml` : keys verified against `src/ai-bundle/config/store/postgres.php`:

```yaml
ai:
    platform:
        openai:
            api_key: '%env(OPENAI_API_KEY)%'

    store:
        postgres:
            my_index:
                dsn: '%env(resolve:DATABASE_URL)%'
                # Or use dbal_connection instead of dsn (mutually exclusive)
                # dbal_connection: 'default'
                table_name: 'documents'
                vector_field: 'embedding'
                distance: 'cosine'   # cosine | inner_product | l1 | l2; default is 'l2' (Postgres\Store Distance::L2)
                setup_options:
                    vector_type: 'vector'
                    vector_size: 1536
                    index_method: 'ivfflat'
                    index_opclass: 'vector_cosine_ops'

    vectorizer:
        my_vectorizer:
            platform: 'ai.platform.openai'
            model: 'text-embedding-3-small'

    indexer:
        my_indexer:
            vectorizer: 'ai.vectorizer.my_vectorizer'
            store: 'ai.store.postgres.my_index'

    agent:
        rag:
            platform: 'ai.platform.openai'
            model: 'gpt-4o-mini'
            tools:
                services:
                    - service: 'App\AI\SimilaritySearchTool'
```

## Service: similarity search tool

```php
namespace App\AI;

use Symfony\AI\Agent\Toolbox\Attribute\AsTool;
use Symfony\AI\Platform\PlatformInterface;
use Symfony\AI\Platform\Vector\Vector;
use Symfony\AI\Store\Query\VectorQuery;
use Symfony\AI\Store\StoreInterface;

#[AsTool(
    name: 'search_knowledge',
    description: 'Search the knowledge base for documents relevant to a query. Returns the top-K most relevant passages.',
)]
final class SimilaritySearchTool
{
    public function __construct(
        private readonly StoreInterface $store,
        private readonly PlatformInterface $platform,
        private readonly string $embeddingModel = 'text-embedding-3-small',
        private readonly int $topK = 5,
    ) {
    }

    public function __invoke(string $query): string
    {
        /** @var Vector $vector */
        $vector = $this->platform->invoke($this->embeddingModel, $query)->asVectors()[0];

        $documents = $this->store->query(new VectorQuery($vector), ['limit' => $this->topK]);

        $chunks = [];
        foreach ($documents as $document) {
            $chunks[] = sprintf(
                "%s:\n%s",
                $document->getMetadata()['source'] ?? 'unknown',
                $document->getMetadata()['_text'] ?? '',
            );
        }

        return implode("\n\n---\n\n", $chunks);
    }
}
```

## CLI command: setup the table

`ai:store:setup` provisions the index using the store's `setup()` method (see `src/ai-bundle/src/Command/SetupStoreCommand` and `ManagedStoreInterface::setup()`):

```bash
php bin/console ai:store:setup ai.store.postgres.my_index
```

## Ingestion and query

Same `Indexer\DocumentIndexer` + `ai:agent:call rag` flow as the Pinecone recipe. The Postgres bridge is transparent : no other changes required.

## Tuning the index

For > 1000 rows, switch from the default IVFFlat to HNSW (better recall, slower writes):

```sql
CREATE INDEX documents_embedding_idx
    ON documents
    USING hnsw (embedding vector_cosine_ops);
```

Or rebuild via the store's `setup()`:

```php
use Symfony\AI\Store\Bridge\Postgres\Store;

$store->setup([
    'index_method' => 'hnsw',
    'index_opclass' => 'vector_cosine_ops',
]);
```

| Rows | Recommended index | Notes |
|---|---|---|
| < 1000 | (none) | Seq scan is fast enough |
| 1000 - 100k | IVFFlat with `lists = sqrt(rows)` | Training data: rows must pre-exist |
| > 100k | HNSW | Higher memory cost, slower writes |

## Variants

- **Pinecone** instead of Postgres: see [rag-pinecone](rag-pinecone.md)
- **Hybrid retrieval**: issue a `HybridQuery` against the same store : Postgres supports `VectorQuery`, `TextQuery`, and `HybridQuery` (see `Store::supports()`)
- **Streaming responses**: pass `'stream' => true` to `Agent::call()`

## See also

- `store` skill (chunking, metadata, dimension, hybrid query, rerank)
- `platform` skill (embedding model selection)
- `agent` skill (tool-calling patterns)
