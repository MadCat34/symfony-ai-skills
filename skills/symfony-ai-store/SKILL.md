---
name: symfony-ai-store
description: 'Use when building RAG, semantic search or similarity lookup with Symfony AI Store, including generic questions on chunking documents or picking a vector database: loading and chunking documents, indexing embeddings, querying pgvector, Pinecone, Qdrant, Elasticsearch, Redis and others, hybrid search or reranking. Triggers on `StoreInterface`, `VectorQuery`, `DocumentIndexer`, `Vectorizer`. Not for generating embeddings alone (`symfony-ai-platform`) or chat history (`symfony-ai-chat`).'
license: MIT
metadata:
  author: Romain Bastide <madcat34@gmail.com>
  url: https://github.com/MadCat34
  version: 0.14.1
  tags: symfony, php, ai, rag, vector-database, semantic-search, embeddings, pgvector, pinecone, qdrant
---

# Symfony AI Store

## Purpose

The persistence and retrieval layer of Symfony AI: load documents, chunk them,
turn them into vectors through a Platform embedding model, store them in one
of 24 backends, and query them back by similarity, keywords, or both.

## When to use

- Retrieval-augmented generation (RAG) or semantic search over documents.
- Swapping vector databases without rewriting the application (Pinecone ↔ Postgres ↔ Qdrant).
- Standard loaders and transformers: directories, Markdown, chunking, batching, throttling.
- Hybrid (vector + keyword) search, reranking, or a store for tests (`InMemory\Store`).
- Embeddings kept in a MySQL `JSON` column today: a JSON column has no vector
  index and no similarity search, so every query becomes a full scan in PHP.

## When not to use

- Generating embeddings without storing them: use `symfony-ai-platform`.
- Persisting a chat conversation: use `symfony-ai-chat`.
- The agent that consumes retrieved documents: use `symfony-ai-agent`.
- Declaring stores, indexers and retrievers in `config/packages/ai.yaml`: use `symfony-ai-bundle`.
- A database-specific feature the bridge hides (Pinecone namespaces, Qdrant
  collection metadata, Milvus partitions) or full control of the SQL (custom
  indexes on metadata columns): use the database client directly.

## Prerequisites

PHP 8.2+, the store package, at least one store bridge, and a configured
Platform with an embedding model: vector search is impossible without
embeddings. Read `references/embeddings.md` in `symfony-ai-platform` first.

```bash
composer require symfony/ai-store symfony/ai-platform symfony/ai-open-ai-platform
composer require symfony/ai-pinecone-store
# Or: ai-postgres-store, ai-qdrant-store, ai-meilisearch-store, …
```

## Examples

Index one document, then query it by similarity:

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

- `StoreInterface`: write/read interface, implemented by the 24 bridges; it
  extends `\Countable`, so `count($store)` returns the number of documents.
- `ManagedStoreInterface`: adds `setup()` / `drop()` for the index lifecycle.
- `DocumentProcessor::process()` runs filter → transform → vectorize → store,
  in batches of 50 documents (`process($docs, ['chunk_size' => N])`), with one
  `$store->add()` per batch.
- `Indexer\DocumentIndexer(DocumentProcessor)` indexes documents you built;
  `Indexer\SourceIndexer(LoaderInterface, DocumentProcessor)` indexes whatever a
  loader yields from a source; `Indexer\ConfiguredSourceIndexer` adds a default
  source. None of them takes a `PlatformInterface` directly: wiring goes
  through `Vectorizer`.
- `RetrieverInterface`: a string in, `VectorDocumentInterface[]` out.
- `CombinedStore`: a vector store + a text store, merged by Reciprocal Rank
  Fusion for `HybridQuery`.
- `RerankerListener`: reranks results on `PostQueryEvent`; `TraceableStore`
  records calls for tests and debugging.

Documents and queries:

- `TextDocument(int|string $id, string $content, Metadata $metadata = new Metadata())`:
  the `id` is required. `Metadata` extends `\ArrayObject`; reserved keys are
  `_parent_id`, `_text`, `_source`, `_summary`, `_title`, `_depth`.
- `VectorDocument(int|string $id, VectorInterface $vector, Metadata $metadata = new Metadata(), ?float $score = null)`:
  `withScore()` returns a copy. Stores, retrievers and rerankers are typed
  against `VectorDocumentInterface`; never narrow results to `VectorDocument`.
- `VectorQuery(VectorInterface $vector)` for similarity (feed a result's
  `getVector()` back for "more like this"), `TextQuery(string|array $text)`
  for keywords, `HybridQuery(VectorInterface $vector, string|array $text, float $semanticRatio = 0.5)`
  for both.

Inside a Symfony app (`symfony-ai-bundle`), five commands manage stores:
`ai:store:setup <store>`, `ai:store:drop <store> --force`,
`ai:store:clear <store> --force`, `ai:store:index <indexer> [--source=…]` and
`ai:store:retrieve <retriever> [query] [--limit=N]`.

## Key gotchas

1. **Embedding-model match.** Documents and queries must be embedded with the
   same model. Changing the model requires a full re-index.
2. **Chunking window.** `TextSplitTransformer` defaults to `chunkSize=1000`,
   `overlap=200`. Each chunk gets a fresh `Uuid::v4()` id; `Metadata::KEY_PARENT_ID`
   links it back to its source document.
3. **Batch indexing memory.** `DocumentProcessor` flushes every 50 documents;
   tune `chunk_size` for rate limits, and throttle with `ChunkDelayTransformer`
   (it requires a `ClockInterface`).
4. **Metadata is JSON-encoded.** Bridges that persist metadata (`Postgres`,
   `Supabase`, `Cloudflare`, …) store it as JSON, and `Metadata::KEY_TEXT` can
   be a long string: size the column or field for it.
5. **Check support before querying.** Some bridges are text-only or
   vector-only: call `$store->supports(VectorQuery::class)` first.

## Troubleshooting

| Error | Cause | Fix |
| --- | --- | --- |
| `Unexpected response type: expected "…\VectorResult", got "…\TextResult".` (`UnexpectedResultTypeException`) | The `Vectorizer` was given a chat model. | Use an embedding model, e.g. `text-embedding-3-small`. |
| `The content shall not be an empty string.` (`InvalidArgumentException`) | A `TextDocument` was built from empty content. | Skip empty sources before building documents, or drop them with a filter. |
| `Overlap must be non-negative and less than chunk size. Got chunk size: …, overlap: ….` | `TextSplitTransformer` received `overlap >= chunkSize` or a negative overlap. | Keep `0 <= overlap < chunkSize`. |
| `Query type "…" is not supported by store "…"` (`UnsupportedQueryTypeException`) | The bridge cannot run that query type. | Check `$store->supports(…)`; for hybrid search use a bridge that supports `HybridQuery` or a `CombinedStore`. |
| `Semantic ratio must be between 0.0 and 1.0, got …` | `HybridQuery` received a ratio outside `[0.0, 1.0]`. | Pass a ratio between 0 and 1 (0.5 by default). |
| `For using the DirectoryLoader, the Symfony Finder component is required. …` (same pattern for `MarkdownLoader`, RSS, JSON loaders) | An optional dependency of the loader is missing. | Run the `composer require` named in the message. |
| Results look unrelated after a model or provider change | Documents were embedded with the previous model. | Re-index everything with the new model. |

## Limitations

- The component is experimental: APIs change between minor versions. Pin
  `symfony/ai-store` and read `UPGRADE.md` in the monorepo before upgrading.
- Similarity scores are not comparable across backends: distance metrics and
  normalisation differ (cosine on Postgres ≠ cosine on Qdrant in absolute terms).
- `AzureSearch` and `Supabase` do not implement `ManagedStoreInterface`: create
  and remove their indexes outside Symfony AI.
- Vector search depends on a Platform embedding model; keyword-only stores
  answer `TextQuery` alone.

## Usage

- **Index a directory of Markdown files**: `DirectoryLoader(['md' => new MarkdownLoader()])`
  inside a `SourceIndexer`, then `$indexer->index('/path/to/dir')`.
- **Hybrid search**: wrap a vector store and a text store in `CombinedStore`,
  then issue `HybridQuery` queries.
- **Rerank results**: wire a `Reranker` (a `PlatformInterface` plus a reranking
  model such as Cohere's) into a `RerankerListener` on `PostQueryEvent`.
- **Test without a database**: use `InMemory\Store`. It implements both
  `StoreInterface` and `ManagedStoreInterface`, supports `VectorQuery`,
  `TextQuery` and `HybridQuery`, and accepts `maxItems` plus a `filter`
  callable in `$options`.

## References

- Read [`references/api-reference.md`](references/api-reference.md) when wiring
  classes by hand or in the container: the namespace tree, every constructor
  signature, every query type, the commands.
- Read [`references/bridges.md`](references/bridges.md) when the user picks a
  backend: the 24 bridge packages, their classes and quirks.
- Read [`references/patterns.md`](references/patterns.md) when the user wants
  runnable code: InMemory, Postgres + pgvector, Pinecone, hybrid retrieval.
- Read [`references/gotchas.md`](references/gotchas.md) when retrieval
  misbehaves and the cause is not above: empty results, drop semantics,
  query-time limits, transformer order, rerankers, re-indexing.

## See also

- `symfony-ai-platform`: the embedding model side (`references/embeddings.md`)
  and the providers that offer embeddings (`references/bridges.md`).
- `symfony-ai-agent`: an agent that consumes retrieved documents (RAG agent).
- `symfony-ai-bundle`: stores, vectorizers, indexers and retrievers in `ai.yaml`.
