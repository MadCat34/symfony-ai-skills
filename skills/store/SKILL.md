---
name: store
description: Use when storing or querying documents in a vector database for RAG, semantic search, similarity, or long-term retrieval. Covers indexing pipelines (load → transform → vectorize → store), query types (VectorQuery / TextQuery / HybridQuery), the 24 supported bridge adapters, distance metrics, hybrid retrieval via Reciprocal Rank Fusion, and reranking. Triggers on `StoreInterface`, `VectorQuery`, `TextQuery`, `HybridQuery`, `VectorDocument`, `TextDocument`, `Vectorizer`, `DocumentIndexer`, `DocumentProcessor`, `Retriever`, `CombinedStore`, `Metadata`. Do NOT trigger for raw embeddings generation (use `platform`).
license: MIT
metadata:
  author: MadCat34
  email: madcat34@gmail.com
  url: https://github.com/MadCat34
  version: "0.12.0"
---

# Store : Symfony AI

> **Store requires a configured Platform for embeddings. In the `platform` skill, read `references/embeddings.md` first. No Platform → no embeddings → no store.**

> **Symfony AI is experimental.** APIs may break between releases. Always check `UPGRADE.md` in the [symfony/ai monorepo](https://github.com/symfony/ai) before upgrading.

The persistence + retrieval layer for Symfony AI. The embedding model lives in `platform`; the Store component borrows it to turn text into vectors and persist them in a backend you choose.

## When to use Store vs raw vector DB client

Use **Store** when:

- You want to swap vector DB backends without rewriting the application (Pinecone ↔ Postgres ↔ Qdrant).
- You want the standard transformers (chunking, batching, throttling).
- You are building a RAG agent (combine with `agent` skill).

Use **raw vector DB client** when:

- You need a DB-specific feature (Pinecone namespaces, Qdrant collection metadata, Milvus partitions).
- You need full control over the SQL level (custom indexes on metadata columns).

## Installation

```bash
composer require symfony/ai-store
composer require symfony/ai-platform
composer require symfony/ai-open-ai-platform
# Plus at least one bridge
composer require symfony/ai-pinecone-store
# Or: ai-postgres-store, ai-qdrant-store, ai-meilisearch-store, …
```

## Quick reference

```php
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;
use Symfony\AI\Store\Document\Loader\InMemoryLoader;
use Symfony\AI\Store\Document\Metadata;
use Symfony\AI\Store\Document\TextDocument;
use Symfony\AI\Store\Document\Transformer\TextSplitTransformer;
use Symfony\AI\Store\Document\Vectorizer;
use Symfony\AI\Store\Indexer\DocumentIndexer;
use Symfony\AI\Store\Indexer\DocumentProcessor;
use Symfony\AI\Store\InMemory\Store;
use Symfony\AI\Store\Query\VectorQuery;

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);
$vectorizer = new Vectorizer($platform, 'text-embedding-3-small');

$store = new Store();
$store->setup();

$loader = new InMemoryLoader([
    new TextDocument('doc-1', 'Symfony AI is the AI toolkit for PHP.', new Metadata(['title' => 'Intro'])),
]);

$processor = new DocumentProcessor(
    $vectorizer,
    $store,
    transformers: [new TextSplitTransformer(chunkSize: 1000, overlap: 200)],
);

$indexer = new DocumentIndexer($processor);
foreach ($loader->load() as $doc) {
    $indexer->index($doc);
}

$results = $store->query(
    new VectorQuery($vectorizer->vectorize('What is Symfony AI?')),
    ['maxItems' => 3],
);

foreach ($results as $doc) {
    echo $doc->getId(), ' → ', $doc->getScore(), PHP_EOL;
}
```

## Architecture

```text
LoaderInterface → DocumentProcessor → StoreInterface → bridge
(TextFileLoader)  (filter/transform     (add/query/        (Pinecone,
                   /vectorize/store)     remove/clear)      Postgres, …)
                          ↑
TransformerInterface[]   VectorizerInterface   RetrieverInterface
(chunking, trim, …)      (Platform delegate)   (query side)
```

- `StoreInterface` : write/read interface (24 bridges implement it).
- `ManagedStoreInterface` : adds `setup()` / `drop()` for index lifecycle.
- `IndexerInterface` : high-level "turn sources into stored vectors" service.
- `DocumentProcessor` : internal pipeline used by `DocumentIndexer` and `SourceIndexer`.
- `RetrieverInterface` : read-side service: a string in, `VectorDocument[]` out.
- `CombinedStore` : wraps a vector store + a text store, performs Reciprocal Rank Fusion for `HybridQuery`.
- `TraceableStore` : decorator that records calls (useful for tests / debug).
- `RerankerListener` : listens to `PostQueryEvent` to rerank the result list.

Everything lives under namespace `Symfony\AI\Store`. See `references/api.md` for the full tree.

### Pipeline order (DocumentProcessor)

`DocumentProcessor::process()` runs sequentially:

```text
filter (FilterInterface[]) → transform (TransformerInterface[]) → vectorize → store
```

It chunks the stream into batches of 50 documents (`DocumentProcessor` default; override via `process($docs, ['chunk_size' => N])`) and calls `$store->add()` once per batch.

### Indexer chain

| Class | Input shape | Purpose |
|---|---|---|
| `Indexer\DocumentIndexer(DocumentProcessor $processor)` | `EmbeddableDocumentInterface` or iterable | Index a hand-crafted list |
| `Indexer\SourceIndexer(LoaderInterface $loader, DocumentProcessor $processor)` | source identifier (string or iterable of strings) | Index whatever the loader yields |
| `Indexer\ConfiguredSourceIndexer(SourceIndexer $indexer, string\|array $defaultSource)` | source or null → falls back to `$defaultSource` | Bundle-friendly default |

The interfaces never take a `PlatformInterface` directly : wiring goes through `Vectorizer`.

### Document lifecycle

- `TextDocument(int|string $id, string $content, Metadata $metadata = new Metadata())` : note the required `id`. Empty content throws `InvalidArgumentException`.
- `Metadata` extends `\ArrayObject`. Reserved keys: `_parent_id`, `_text`, `_source`, `_summary`, `_title`, `_depth`.
- `VectorDocument(int|string $id, VectorInterface $vector, Metadata $metadata = new Metadata(), ?float $score = null)` : `withScore()` returns a new instance with an updated score.
- `Vector` (from `Symfony\AI\Platform\Vector`) exposes `getData(): list<float>` and `getDimensions(): int`.

### Query types

`StoreInterface::query()` takes a `QueryInterface`:

- `VectorQuery(Vector $vector)` : pure vector similarity.
- `TextQuery(string|array $text)` : keyword / full-text only. Internally uses `Metadata::KEY_TEXT`.
- `HybridQuery(Vector $vector, string|array $text, float $semanticRatio = 0.5)` : combined; the ratio must be `0.0-1.0`.

Always call `$store->supports(VectorQuery::class)` before issuing a vector query, since some bridges are text-only or FTS-only.

### Lifecycle commands

The Store component ships five CLI commands when used inside a Symfony app (via `ai-bundle`):

- `ai:store:setup <store>` : create the index / table.
- `ai:store:drop <store> --force` : destroy infrastructure.
- `ai:store:clear <store> --force` : remove all documents, keep the store usable.
- `ai:store:index <indexer> [--source=…]` : index using a configured `SourceIndexer` / `ConfiguredSourceIndexer`.
- `ai:store:retrieve <retriever> [query] [--limit=N]` : query via a configured `RetrieverInterface`.

## Key gotchas (5)

1. **Embedding-model match.** The model used to embed documents *at index time* must match the model used to embed queries *at retrieval time*. Changing the model requires a full re-index.
2. **Chunking window.** `TextSplitTransformer` defaults: `chunkSize=1000`, `overlap=200`. The overlap must be `>= 0` and `< chunkSize` (throws otherwise). Each chunk gets a fresh `Uuid::v4()` id; `Metadata::KEY_PARENT_ID` links it back.
3. **Batch indexing memory.** `DocumentProcessor` flushes every 50 documents (override via `chunk_size`). Tune for rate limits and combine with `ChunkDelayTransformer` (which requires a `ClockInterface`) to throttle between batches.
4. **Metadata JSON serialisation.** Bridges that persist metadata (`Postgres`, `Supabase`, `Cloudflare`, …) JSON-encode the `Metadata` array. `Metadata::KEY_TEXT` may be a long string : make sure the column or field size supports it.
5. **Distance metrics differ across bridges.** Cosine on Postgres ≠ cosine on Qdrant in absolute terms. Stick to one backend per index, never compare raw scores across systems.

For the full list (empty result sets, drop semantics, query-time `limit`, transformer chain order, re-indexing after metadata schema change, reranker ordering), see `references/gotchas.md`.

## Common tasks

- **Index a directory of Markdown files** : use `DirectoryLoader(['md' => new MarkdownLoader()])` inside a `SourceIndexer`, then `$indexer->index('/path/to/dir')`.
- **Hybrid search** : wrap a vector store + a text store in `CombinedStore`, then issue `HybridQuery` queries.
- **Rerank results** : wire `Reranker` (a `PlatformInterface` plus a Cohere reranker model) into a `RerankerListener` listening to `PostQueryEvent`.
- **Test without a database** : use `InMemory\Store`. It implements both `StoreInterface` and `ManagedStoreInterface`, supports `VectorQuery`, `TextQuery`, `HybridQuery`, and accepts `maxItems` plus a `filter` callable in `$options`.

## References

- `references/api.md` : full namespace tree, every constructor signature, every query type. Read this when wiring the DI container.
- `references/bridges.md` : the 24 bridge packages, grouped by category. Read this when picking a backend.
- `references/patterns.md` : InMemory, Postgres+pgvector, Pinecone, and hybrid retrieval patterns with copy-pasteable code.
- `references/gotchas.md` : embedding-model match, chunking, batch indexing, distance metrics, rerankers, drop semantics, query-time `limit`, and more.

Triggers: "add RAG", "store vectors", "vector database", "semantic search", "find similar docs", "chunk documents before embedding", "pinecone / qdrant / milvus / weaviate / chroma / pgvector / meilisearch / redis / mongodb vector / typesense / supabase / s3 vectors", "rerank results", "hybrid search", "in-memory store for tests".

Validation: run `bash skills/store/scripts/check-snippets.sh` to lint every PHP code block in this skill.

## See also

- `platform` skill, `references/embeddings.md` : the embedding model side
- `platform` skill, `references/bridges.md` : embedding model providers
- `agent` skill : for RAG agent patterns
- `ai-bundle` skill : for Symfony wiring of stores / indexers / retrievers
