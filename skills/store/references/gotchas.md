# Store : Gotchas

Source of truth: `https://github.com/symfony/ai/tree/main/src/store/src/`. Every entry below comes from a real class or method in the source : no fabricated behaviours.

## 1. Embedding-model match (index-time vs query-time)

`Vectorizer::vectorize()` calls `PlatformInterface::invoke($model, $content, $options)`. The model passed in the constructor is used for **both** indexing and retrieval. If you change `$model`, you must re-index everything.

```php
$vectorizer = new Vectorizer($platform, 'text-embedding-3-small');
// later: changing to 'text-embedding-3-large' or any other model requires a full re-index.
```

This is the single most common cause of "the store returns nonsense" : the index was built with one embedding model and the query uses another.

## 2. Chunking window : defaults are 1000/200, not 500/50

`TextSplitTransformer::__construct(int $chunkSize = 1000, int $overlap = 200)` : the constructor **throws** if `$overlap < 0` or `$overlap >= $chunkSize`. Each chunk gets a fresh `Uuid::v4()` id; `Metadata::KEY_PARENT_ID` links it back to the source document.

```php
new TextSplitTransformer(chunkSize: 1000, overlap: 200);
```

Tuning tips:

- **Too small** → the chunk loses context; answers become literal.

- **Too large** → the chunk dilutes the topic; recall drops for narrow queries.

- **Overlap too small** → adjacent chunks miss shared context.

- **Overlap too large** → you embed the same content twice (cost).

For RAG over mixed prose + code, start with 800/200.

## 3. Batch indexing memory and rate limits

`DocumentProcessor::process()` batches every 50 documents (override via `$options['chunk_size']`). Each batch triggers exactly one platform call.

For rate-limited APIs (OpenAI tier 1, Cohere free tier, Voyage free tier) combine with `ChunkDelayTransformer`:

```php
use Symfony\Component\Clock\NativeClock;

new ChunkDelayTransformer(
    clock: new NativeClock(),
    chunkSize: 50,
    delay: 10,    // seconds
);
```

In tests, swap `NativeClock` for `MockClock` so the suite does not actually sleep. The transformer also accepts a `LoggerInterface` (defaults to `NullLogger`).

## 4. Metadata is JSON-serialised

Most bridges call `Metadata::getArrayCopy()` and JSON-encode it (Postgres, Supabase, Cloudflare, MongoDB, etc.). `Metadata::KEY_TEXT` is the most likely to overflow: a 15000-character RST section is fine for Postgres `JSONB` but might exceed Typesense / Redis default metadata limits.

Other pitfalls:

- `Metadata` extends `\ArrayObject`. Use the typed accessors (`setText()`, `setSource()`, …) : the reserved keys (`_text`, `_parent_id`, `_source`, `_summary`, `_title`, `_depth`) are special-cased.

- Bridges strip `Metadata::KEY_TEXT` before sending it to some vector-only backends (e.g. ChromaDB stores it in a separate `originalDocuments` array).

## 5. Distance metrics differ across bridges

Cosine on Postgres ≠ cosine on Qdrant in absolute score terms. Even when both bridges label the metric "cosine", they may normalise differently, return distance vs similarity, or round at different precisions.

Rules:

- Pick one backend per index.

- Never compare raw scores across systems.

- For Postgres, the metric is set at index-creation time via the `index_opclass` option in `setup()` (`vector_cosine_ops`, `vector_l2_ops`, `vector_ip_ops`).

- For `InMemory\Store` and `Cache\Store`, scores come from `DistanceCalculator` and match the configured `DistanceStrategy`.

## 6. Reranker ordering : Cohere reranker model

`Reranker` takes a `PlatformInterface` and a model. The platform-side model lives under `Symfony\AI\Platform\Bridge\<Provider>\Reranker`. For Cohere, this is `Symfony\AI\Platform\Bridge\Cohere\Reranker` (an empty `Model` subclass : pick a concrete model name such as `rerank-v3.5`). There is **no** Voyage reranker : `symfony/ai-voyage-platform` ships embeddings only. The one alternative is `Symfony\AI\Platform\Bridge\OpenRouter\RerankModel`.

`Reranker::rerank()` reads text from `Metadata::KEY_TEXT` first, falling back to `Metadata::KEY_SOURCE`. Make sure your `Vectorizer` was constructed with `includeText: true` (otherwise metadata has no `_text` and the reranker sees empty strings).

```php
new Vectorizer($platform, 'text-embedding-3-small', includeText: true);
```

## 7. Transformer chain order

`ChainTransformer` applies transformers in the order they are passed. Some orderings are required:

```php
new ChainTransformer([
    new TextReplaceTransformer('<REDACTED>', '[secret]'),  // 1. strip secrets
    new TextTrimTransformer(),                            // 2. normalise whitespace
    new TextSplitTransformer(chunkSize: 1000, overlap: 200), // 3. chunk last
]);
```

Putting `TextSplitTransformer` first is usually wrong : you'd be chunking a document with secrets still inside.

## 8. Drop semantics

- `setup()` creates the index / table.

- `drop()` destroys it (irreversible; requires `--force` on the CLI).

- `clear()` removes all documents but keeps the store usable.

If you `drop()` a managed store, you must `setup()` again before adding more documents.

## 9. Query-time `limit` vs `maxItems`

There is no single option name across bridges:

- `InMemory\Store` and `Cache\Store` accept `maxItems` plus a `filter` callable.

- `Postgres\Store` accepts `limit` (and `maxScore`).

- `Pinecone\Store` accepts `topK`.

- `Meilisearch\Store`, `Typesense\Store`, etc. accept backend-native options.

Always check the bridge you use. The `StoreInterface::query(QueryInterface, array $options = []): iterable` contract is intentionally loose here : options are bridge-specific.

## 10. Vector dimension validation

There is **no** `DimensionMismatchException` in the Store component. Dimension errors come from:

- `Symfony\AI\Platform\Vector\Vector::__construct()` : throws `InvalidArgumentException` if `count($data) !== $dimensions`.

- The bridge itself (e.g. Postgres pgvector rejects inserts whose dimension differs from the column type).

Practical rules:

- Match the model's output dimension in `setup()` (`['vector_size' => 1536]`).

- For `VecStore` (sqlite-vec), `$vectorDimension` is a constructor argument.

- For `Qdrant\Store`, `embeddingsDimension` is a constructor argument.

- For `Pinecone\Store`, `dimension` is a `setup()` option.

## 11. Re-indexing after metadata schema change

Bridges store metadata as `JSONB` (Postgres, Supabase), a dynamic column (MongoDB), or an untyped payload (most others). Renaming a metadata key does **not** require a re-index : old documents still have the old key. But adding a new **required** filter is a different story:

- Postgres pgvector: store the filter via `metadata->>'your_key' = ...`; GIN index on `metadata` if you filter often.

- ChromaDB / Qdrant: add a `where` clause in the bridge's `query()` options; some bridges expose `filter` natively.

If you change the *vector dimension*, you must re-index everything and likely `drop()` + `setup()` the store.

## 12. Empty result sets

If `query()` returns no documents, `Retriever` yields zero results (no exception). For CLI:

```bash
bin/console ai:store:retrieve my-retriever "nonsense"
[WARNING] No results found.
```

The score on a `VectorDocument` is `null` until the store has ranked it. Some stores set it explicitly; `InMemory\Store` always does (via `DistanceCalculator`); `CombinedStore` sets it after RRF.

## 13. Adding documents without an id

`TextDocument::__construct(int|string $id, string $content, Metadata $metadata = new Metadata())` : the id is **required** and must be the first positional argument. Loaders that don't have an obvious id use `Uuid::v4()`. `RssFeedLoader` is the exception and the difference matters: it reuses the item's `<guid>` when that is a valid UUID, and otherwise derives a **deterministic `Uuid::v5($namespace, $guid ?? $link)`** (`RssFeedLoader.php:71`). Re-indexing the same feed therefore produces the same ids and updates rows in place, where a v4-based loader would insert duplicates. Your custom documents must pick the semantics they want deliberately.

## 14. `Vectorizer::vectorize()` on arrays of `EmbeddableDocumentInterface`

`Vectorizer::vectorize()` distinguishes the array variant by inspecting the first element:

```php
$vectorizer->vectorize([$doc1, $doc2]); // array of EmbeddableDocumentInterface → array of VectorDocument
$vectorizer->vectorize(['hello', 'world']); // array of strings → array of Vector
$vectorizer->vectorize('hello'); // single string → single Vector
$vectorizer->vectorize($doc); // single EmbeddableDocumentInterface → single VectorDocument
```

Mixing types in the array (`['hello', $doc]`) throws `RuntimeException`.

## 15. `CombinedStore` and equal sub-stores

If you pass the same store instance as both `$vectorStore` and `$textStore`, `CombinedStore` skips the second `add()` / `remove()` / `clear()` call (deduping write operations). **However, this does not make `HybridQuery` available unless the store also supports `TextQuery`** — `CombinedStore::supports(HybridQuery::class)` requires both `vectorStore->supports(VectorQuery)` and `textStore->supports(TextQuery)`. For a hybrid-native bridge like Meilisearch that supports `HybridQuery` natively but not `TextQuery` alone, use the store directly in `Retriever` without wrapping it in `CombinedStore`. For real hybrid queries across separate stores, pair a vector-only store (e.g., Pinecone) with a text-capable one (Sqlite, Postgres, Cache, or InMemory).

## 16. `TraceableStore` reset between tests

`TraceableStore` implements `ResetInterface`. In a Symfony test using `KernelTestCase` with the `ResetServicesTrait`, the recorded calls are wiped between tests automatically. Without it, call `$traceable->reset()` in `tearDown()`.

## 17. `Metadata::KEY_TEXT` propagation

When `Vectorizer` is constructed with `includeText: true`, it copies `EmbeddableDocumentInterface::getContent()` into `Metadata::KEY_TEXT` at vectorization time. This is required for:

- `TextQuery` matching (the bridge looks at `KEY_TEXT`).

- `Reranker::rerank()` (falls back to `KEY_SOURCE` if missing, but `_source` is usually a path, not actual text).

Without `includeText`, full-text search and reranking are useless.

## 18. Reading order: read `platform/references/embeddings.md` first

Every Store configuration depends on the Platform. If you have not configured `Bridge\OpenAi\Factory::createPlatform(...)` (or another provider's factory) yet, stop and read the `platform` skill. The Store component will not run without an embedding model.

## 19. Ingestion pipeline is application-owned

The Store component does not ship a source manifest, change-data-capture, or scheduler. Everything between "I have content" and "the store has vectors" is composed by the application:

- **Loader** (`Document\LoaderInterface`, e.g. `TextFileLoader`, `MarkdownLoader`, `DirectoryLoader`): turns a source identifier into a stream of `EmbeddableDocumentInterface` instances.

- **Filter** (`Document\FilterInterface`): drops documents before they reach the embedding API.

- **Transformer** (`Document\TransformerInterface`, e.g. `TextSplitTransformer`, `SummaryGeneratorTransformer`, `ChunkDelayTransformer`, `ChainTransformer`): mutates or chunks the document stream.

- **Vectorizer** (`Document\Vectorizer`, `Document\VectorizerInterface`): calls the platform to turn text into vectors.

- **Indexer** (`DocumentIndexer`, `SourceIndexer`, `ConfiguredSourceIndexer`): wires the previous stages and calls `Store::add()`.

Symfony AI provides each stage in isolation. It does **not** track which sources have been indexed, which file mtimes changed, or which documents were deleted upstream. You decide:

- whether to re-run on every deploy or only on a hook,

- how to detect changes (filesystem mtime, hash, message-bus event, etc.),

- how to schedule incremental updates (Messenger, Scheduler, cron, manual `bin/console ai:store:index`).

The loader → transformer → vectorizer → store wiring is this skill's concern; the source manifest is not. Treat it as a separate concern belonging to the application.

## 20. Generated chunk UUIDs and naive replacement

`TextSplitTransformer::transform()` yields every chunk with a fresh `Uuid::v4()` id on every run, regardless of whether the chunking parameters or source content changed, and stores the original document id only in `Metadata::KEY_PARENT_ID`. The same is true for `SummaryGeneratorTransformer` (when `$yieldSummaryDocuments = true`) and the `MarkdownLoader`.

Practical consequences:

- **"Replace the document" is not a single delete.** You must collect the previously generated chunk ids (typically by querying for `metadata->>'_parent_id' = :source_id`) and call `Store::remove($chunkIds, $options)` before re-indexing. A single `remove($sourceId)` only removes chunks whose own id equals the source id : i.e. never, after chunking.

- **Re-chunking with different parameters produces a different id set.** Going from `chunkSize: 1000, overlap: 200` to `chunkSize: 500, overlap: 100` allocates new UUIDs for every chunk. Old chunks stay in the store until you delete them by parent id.

- **Bridge upserts are per-id.** Postgres, Pinecone, and Qdrant upsert on the document id, so a chunk that survives with its old id is *not* re-embedded : even if the source text changed.

- **Re-indexing is not idempotent without a parent sweep.** Without removing the previous generation, repeated runs pile up duplicate chunks (same text, different ids).

Recommended pattern: keep the source identifier stable (the document id passed to `TextDocument`), store it in `Metadata::KEY_SOURCE` or as the parent id, and on every re-index run `Store::remove([... chunk ids for that parent ...])` before calling `Indexer::index()`. The `StoreInterface::remove()` signature is `remove(string|array $ids, array $options = [])` : pass an array of chunk ids.

## 21. `semanticRatio` is not portable across hybrid implementations

The `HybridQuery` carries a `semanticRatio` and `Retriever` defaults it to `0.5` when the option is absent. The semantics differ by store:

- `CombinedStore::hybridQuery()` ignores `semanticRatio` entirely : it always runs RRF with `rrfK = 60` (overridable via the constructor argument). Changing `semanticRatio` only affects the `HybridQuery` object's metadata; the rank fusion does not read it.

- `InMemory\Store::queryHybrid()` multiplies the vector score by `semanticRatio` for vector-only matches and leaves full-text matches unweighted. A higher `semanticRatio` shifts the relative weight toward dense vectors.

- `Postgres\Store::queryHybrid()` honours `semanticRatio` and `keywordRatio` directly inside the SQL ranking expression (`(semantic_ratio * (1 - distance)) + (keyword_ratio * ts_rank(...))`). The two values are forwarded as bound parameters.

- `Meilisearch\Store` forwards the ratio to the Meilisearch hybrid search API, which balances `semanticRatio` between the embedder and the full-text pipeline server-side.

If you re-tune `semanticRatio` on one bridge and move the index to another, do not expect the same ordering. Treat the value as a bridge-specific knob, document the chosen bridge alongside the index, and re-evaluate quality metrics whenever you migrate.

## 22. Reranker failure when text metadata is absent

`Reranker::rerank(string $query, array $documents, int $topK = 5)` reads `Metadata::getText() ?? Metadata::getSource() ?? ''` for each candidate. When `Metadata::KEY_TEXT` is missing across the whole index, the reranker receives source paths (or empty strings) and returns near-zero scores that swamp the original ranking. There is no exception : the pipeline silently degrades.

How text metadata reaches `Metadata::KEY_TEXT`:

- `Vectorizer` with `includeText: true` sets it at vectorization time (`vectorizeEmbeddableDocument` and `vectorizeEmbeddableDocuments` both call `metadata->setText($document->getContent())` when the flag is true and the metadata does not already have `_text`).

- `TextSplitTransformer` sets `_text` on each chunk (the chunk's content).

- `TextDocument` constructed manually without `Metadata::KEY_TEXT` does not get it set retroactively.

Symptoms to watch for:

- reranker scores cluster near 0 and the order becomes nearly random,

- `Metadata::getText()` returns `null` for every result,

- the ratio `total_with_text / total_results` is 0 even though the query has clear matches.

To repair:

- flip the `Vectorizer` constructor to `includeText: true` and re-index the affected sources (chunk UUIDs change : see gotcha #20),

- or apply a `ChainTransformer` step that writes `Metadata::setText($document->getContent())` for every document, then re-index.
