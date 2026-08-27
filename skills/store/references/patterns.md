# Store : Patterns

Source of truth: `https://github.com/symfony/ai/tree/main/src/store/src/`. Each pattern below uses only real classes and signatures verified against the source.

> Always confirm with `bash scripts/check-snippets.sh` after editing.

## Pattern 1 : InMemory (tests, prototyping)

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
$store->setup();    // optional — drop() then leave it empty

$loader = new InMemoryLoader([
    new TextDocument('doc-1', 'Symfony AI is the AI toolkit for PHP.', new Metadata(['title' => 'Intro'])),
    new TextDocument('doc-2', 'pgvector adds vector search to Postgres.', new Metadata(['title' => 'Postgres'])),
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

$hits = $store->query(
    new VectorQuery($vectorizer->vectorize('How do I search vectors in Postgres?')),
    ['maxItems' => 3],
);

foreach ($hits as $hit) {
    echo $hit->getId(), ' score=', $hit->getScore(), PHP_EOL;
}
```

`InMemory\Store::query()` accepts `maxItems` (top-N) and a `filter` callable in `$options`. There is no `limit` parameter : it is `maxItems`.

## Pattern 2 : Postgres + pgvector (self-hosted)

```php
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;
use Symfony\AI\Store\Bridge\Postgres\Store;
use Symfony\AI\Store\Document\Loader\TextFileLoader;
use Symfony\AI\Store\Document\Vectorizer;
use Symfony\AI\Store\Indexer\DocumentProcessor;
use Symfony\AI\Store\Indexer\SourceIndexer;
use Symfony\AI\Store\Query\VectorQuery;

$pdo = new \PDO('pgsql:host=localhost;dbname=app', 'app', 'secret');

$store = new Store(
    connection: $pdo,
    tableName: 'documents',
    vectorFieldName: 'embedding',
    distance: \Symfony\AI\Store\Bridge\Postgres\Distance::Cosine,
    lang: 'english',
);

// Create extension + table + index (run once)
$store->setup([
    'vector_type'  => 'vector',
    'vector_size'  => 1536,    // match OpenAI text-embedding-3-small
    'index_method' => 'hnsw',
    'index_opclass' => 'vector_cosine_ops',
]);

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);
$vectorizer = new Vectorizer($platform, 'text-embedding-3-small');

$processor = new DocumentProcessor(
    $vectorizer,
    $store,
    transformers: [new TextSplitTransformer(chunkSize: 800, overlap: 200)],
);

$indexer = new SourceIndexer(new TextFileLoader(), $processor);
$indexer->index('/var/docs/symfony-ai-overview.md');

$hits = $store->query(
    new VectorQuery($vectorizer->vectorize('how do I index documents?')),
    ['limit' => 5],
);

foreach ($hits as $hit) {
    echo $hit->getId(), ' → ', $hit->getScore(), PHP_EOL;
}
```

The `setup()` SQL emitted by `Postgres\Store` (paraphrased):

```sql
CREATE EXTENSION IF NOT EXISTS vector;
CREATE TABLE IF NOT EXISTS "documents" (
    id UUID PRIMARY KEY,
    metadata JSONB,
    "embedding" vector(1536) NOT NULL
);
CREATE INDEX IF NOT EXISTS "documents_embedding_idx"
    ON "documents" USING hnsw ("embedding" vector_cosine_ops);
```

`Postgres\Store::query()` returns matches ordered by distance (lower is better). Pass `['limit' => N]` to cap the result set. The option name on this bridge is `limit`, not `maxItems` : bridge-specific options are not part of the `StoreInterface` contract.

## Pattern 3 : Pinecone (managed)

```php
use Probots\Pinecone\Client as PineconeClient;
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;
use Symfony\AI\Store\Bridge\Pinecone\Store;
use Symfony\AI\Store\Document\Loader\TextFileLoader;
use Symfony\AI\Store\Document\Vectorizer;
use Symfony\AI\Store\Indexer\DocumentProcessor;
use Symfony\AI\Store\Indexer\SourceIndexer;
use Symfony\AI\Store\Query\VectorQuery;

$pinecone = new PineconeClient(
    apiKey: $_ENV['PINECONE_API_KEY'],
    environment: $_ENV['PINECONE_ENV'],
);

$store = new Store(
    pinecone: $pinecone,
    indexName: 'symfony-ai',
    topK: 3,
);

// One-time setup — dimension must match the embedding model
$store->setup([
    'dimension' => 1536,
    'metric'    => 'cosine',
    'cloud'     => 'aws',
    'region'    => 'us-east-1',
]);

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);
$vectorizer = new Vectorizer($platform, 'text-embedding-3-small');

$processor = new DocumentProcessor($vectorizer, $store);
$indexer = new SourceIndexer(new TextFileLoader(), $processor);
$indexer->index('/var/docs/handbook.md');

$hits = $store->query(
    new VectorQuery($vectorizer->vectorize('how do I deploy?')),
    ['topK' => 5],
);

foreach ($hits as $hit) {
    echo $hit->getId(), ' → ', $hit->getScore(), PHP_EOL;
}
```

`Pinecone\Store::query()` accepts `['topK' => N]` : bridge-specific option, not `maxItems`. `add()` upserts in a single API call; `remove()` chunks ids by 1000 per API call.

## Pattern 4 : Hybrid retrieval + Cohere rerank

This wires `CombinedStore` (vector + text) for hybrid retrieval and a `Reranker` (delegating to a Cohere reranker model via `PlatformInterface`) into the `PostQueryEvent` chain.

```php
use Symfony\AI\Platform\Bridge\Cohere\Factory as CohereFactory;
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;
use Symfony\AI\Store\CombinedStore;
use Symfony\AI\Store\Document\Loader\TextFileLoader;
use Symfony\AI\Store\Document\Vectorizer;
use Symfony\AI\Store\EventListener\RerankerListener;
use Symfony\AI\Store\Indexer\DocumentProcessor;
use Symfony\AI\Store\Indexer\SourceIndexer;
use Symfony\AI\Store\Query\HybridQuery;
use Symfony\AI\Store\Query\VectorQuery;
use Symfony\AI\Store\Retriever;
use Symfony\AI\Store\Reranker\Reranker;
use Symfony\Contracts\EventDispatcher\EventDispatcher;

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);
$vectorizer = new Vectorizer($platform, 'text-embedding-3-small', includeText: true);

// Meilisearch is hybrid-native: use it directly, not wrapped in CombinedStore
// (CombinedStore requires both vector and text sub-stores; Meilisearch lacks TextQuery support alone).
$store = new \Symfony\AI\Store\Bridge\Meilisearch\Store($httpClient, 'docs', 'vector');

$processor = new DocumentProcessor(
    $vectorizer,
    $store,
    transformers: [new TextSplitTransformer(chunkSize: 1000, overlap: 200)],
);
$indexer = new SourceIndexer(new TextFileLoader(), $processor);
$indexer->index('/var/docs');

$coherePlatform = CohereFactory::createPlatform($_ENV['COHERE_API_KEY']);
// Reranker::__construct(PlatformInterface, string $model, ?LoggerInterface). Pass the model name as a plain string.
$reranker = new Reranker($coherePlatform, 'rerank-v3.5');

$dispatcher = new EventDispatcher();
$dispatcher->addListener(
    \Symfony\AI\Store\Event\PostQueryEvent::class,
    new RerankerListener($reranker, topK: 5),
);

$retriever = new Retriever(
    store: $store,
    vectorizer: $vectorizer,
    eventDispatcher: $dispatcher,
);

foreach ($retriever->retrieve('how does hybrid search work?', ['semanticRatio' => 0.7]) as $hit) {
    echo $hit->getId(), ' → ', $hit->getScore(), PHP_EOL;
}
```

`Retriever` will pick `HybridQuery` automatically when the store supports it, with `semanticRatio = $options['semanticRatio'] ?? 0.5`. `CombinedStore` performs Reciprocal Rank Fusion (`rrfK` default 60).

`RerankerListener` runs after the store returns its results: it pulls text from `Metadata::KEY_TEXT` (set by `Vectorizer(includeText: true)`), calls the Cohere reranker model, and rewrites the documents list with the reranked `VectorDocument[]`. The top-K is read from `$event->getOptions()['topK']` first, falling back to the constructor argument.

## Pattern 5 : Index a directory of Markdown

```php
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;
use Symfony\AI\Store\Bridge\Qdrant\Store;
use Symfony\AI\Store\Document\Loader\DirectoryLoader;
use Symfony\AI\Store\Document\Loader\MarkdownLoader;
use Symfony\AI\Store\Document\Vectorizer;
use Symfony\AI\Store\Indexer\DocumentProcessor;
use Symfony\AI\Store\Indexer\SourceIndexer;

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);
$vectorizer = new Vectorizer($platform, 'text-embedding-3-small');

$store = new Store($httpClient, 'docs', embeddingsDimension: 1536);
$store->setup();

$indexer = new SourceIndexer(
    new DirectoryLoader(['md' => new MarkdownLoader()]),
    new DocumentProcessor(
        $vectorizer,
        $store,
        transformers: [new TextSplitTransformer(chunkSize: 800, overlap: 150)],
    ),
);

$indexer->index('/var/docs');
```

`DirectoryLoader` requires `symfony/finder`. `MarkdownLoader` requires `symfony/string` and `symfony/filesystem` : they throw if not installed.

## Pattern 6 : Bundle-friendly indexer with default source

```php
use Symfony\AI\Store\Indexer\ConfiguredSourceIndexer;
use Symfony\AI\Store\Indexer\SourceIndexer;
use Symfony\AI\Store\Document\Loader\TextFileLoader;

// services.yaml wires a default source; the CLI / agent can still override at runtime.
$indexer = new ConfiguredSourceIndexer(
    new SourceIndexer(new TextFileLoader(), $processor),
    '/var/docs/handbook.md',
);

// Uses the default source.
$indexer->index();

// Override at runtime.
$indexer->index('/var/docs/release-notes.md');
```

`ConfiguredSourceIndexer::index(null)` falls back to the configured default. Pass a different string or iterable to override.

## Pattern 7 : Deterministic query preprocessing via `PreQueryEvent`

`PreQueryEvent::__construct(string $query, array $options = [])` exposes `getQuery()` / `setQuery()` and `getOptions()` / `setOptions()`. The `Retriever` reads back both after dispatch, so a listener can normalise the text or rewrite `$options['semanticRatio']` before the store builds the query. Keep the example deterministic and application-owned : no LLM calls inside the listener.

```php
use Symfony\AI\Store\Event\PreQueryEvent;
use Symfony\AI\Store\InMemory\Store;
use Symfony\AI\Store\Retriever;
use Symfony\Contracts\EventDispatcher\EventDispatcher;

// Application alias map for an internal product catalog.
// Keys are user-typed terms; values are the canonical replacement
// used both for vectorisation and full-text matching.
$productAliases = [
    'kb'   => 'keyboard',
    'ms'   => 'mouse',
    'dock' => 'docking-station',
];

$normalise = static function (PreQueryEvent $event) use ($productAliases): void {
    $token = strtolower(trim($event->getQuery()));
    $expanded = preg_replace_callback(
        '/\b(' . implode('|', array_keys($productAliases)) . ')\b/i',
        static fn (array $m): string => $productAliases[strtolower($m[1])] ?? $m[1],
        $token,
    );

    $event->setQuery($expanded);
    $event->setOptions(['semanticRatio' => 0.7] + $event->getOptions());
};

$dispatcher = new EventDispatcher();
$dispatcher->addListener(PreQueryEvent::class, $normalise);

$retriever = new Retriever(
    store: $store,
    vectorizer: $vectorizer,
    eventDispatcher: $dispatcher,
);
```

The listener only normalises tokens and rewrites a single option key. Avoid pulling an LLM into the listener : `PreQueryEvent` runs synchronously on every `Retriever::retrieve()` call, before the embedding request, so any latency or nondeterminism is added to the user request path.

`PostQueryEvent` follows the same contract (`getQuery()`, `getDocuments()`, `setDocuments()`, `getOptions()`); `RerankerListener` is a built-in listener for it.

## Pattern 8 : Bounded candidate retrieval + reranking

Rerankers score each candidate against the query, so they cost O(candidates). Keep the candidate pool small (top 20-50) and let the reranker produce the final top-K. `RerankerListener::__construct(RerankerInterface $reranker, int $topK = 5)` reads `$event->getOptions()['topK']` first, falling back to the constructor argument.

```php
use Symfony\AI\Store\CombinedStore;
use Symfony\AI\Store\Document\Vectorizer;
use Symfony\AI\Store\EventListener\RerankerListener;
use Symfony\AI\Store\Retriever;
use Symfony\AI\Store\Reranker\Reranker;
use Symfony\Contracts\EventDispatcher\EventDispatcher;

// `includeText: true` is mandatory: Reranker::rerank() reads Metadata::KEY_TEXT
// first, falling back to Metadata::KEY_SOURCE. Without `_text`, the reranker
// receives the source path (or empty string) and returns low scores.
$vectorizer = new Vectorizer($platform, 'text-embedding-3-small', includeText: true);

$store = new CombinedStore($vectorStore, $textStore);

$dispatcher = new EventDispatcher();
$dispatcher->addListener(
    \Symfony\AI\Store\Event\PostQueryEvent::class,
    new RerankerListener($reranker, topK: 5),
);

$retriever = new Retriever(
    store: $store,
    vectorizer: $vectorizer,
    eventDispatcher: $dispatcher,
);

// With CombinedStore, the candidate-limit option must be honoured by both backing
// stores. Use each bridge's own option instead, such as Postgres `limit` or
// Pinecone `topK`; do not assume `maxItems` is portable.
foreach ($retriever->retrieve('keyboard noise under heavy typing', ['maxItems' => 25]) as $hit) {
    echo $hit->getId(), ' → ', $hit->getScore(), PHP_EOL;
}
```

Failure behaviour when text metadata is absent depends on the bridge:

- `Vectorizer` skips `_text` injection when `includeText: false` : `Reranker::rerank()` then falls back to `Metadata::KEY_SOURCE` (a path/URL), returning low scores.

- Load that ran before `includeText` was enabled has no `_text` at all; you must re-index to repopulate it (see the `Metadata::KEY_TEXT` gotcha).

- `InMemory\Store` and `Cache\Store` keep `_text` in-process; a PHP restart keeps the data but the next index run rebuilds it without `includeText`.

## Hybrid semantics per store

Symfony AI distinguishes two ways to combine vector and text search:

**Native hybrid stores.** `Cache\Store`, `Meilisearch\Store`, `Postgres\Store`, `Sqlite\Store`, and `Sqlite\VecStore` implement `HybridQuery` directly. Each bridge exposes its own ratio knob:

- `Meilisearch\Store` constructor takes `float $semanticRatio = 1.0` : `0.0` is full-text, `1.0` is vector-only.

- `InMemory\Store::queryHybrid()` weights the vector result by `$query->getSemanticRatio()`; the text branch is unweighted.

- `Postgres\Store` honours `semanticRatio` and `keywordRatio` directly inside its SQL ranking expression (`(semantic_ratio * (1 - distance)) + (keyword_ratio * ts_rank(...))`); the values are forwarded as bound parameters.

`Retriever` only feeds `HybridQuery` when the store reports `supports(HybridQuery::class)`. If the store doesn't, `Retriever` falls back to `VectorQuery` (or `TextQuery` if no vectorizer is configured). `Pinecone\Store`, `Redis\Store`, `Supabase\Store`, and `Typesense\Store` do not support `HybridQuery`; use `CombinedStore` to combine their vector or text results instead.

**`CombinedStore` rank fusion.** `CombinedStore::__construct(StoreInterface $vectorStore, StoreInterface $textStore, int $rrfK = 60)` decomposes `HybridQuery` into a `VectorQuery` against the vector store and a `TextQuery` against the text store, then merges with Reciprocal Rank Fusion. RRF scores use `1.0 / (rrfK + rank + 1)` per ranker; the final `VectorDocument` carries the summed RRF score. When the same instance is passed for both sub-stores, `CombinedStore` skips the second `add()` / `remove()` / `clear()` call.

**Why `semanticRatio` is not portable.** The keyword is forwarded into `HybridQuery::__construct()` and the meaning is bridge-defined. `CombinedStore` ignores it entirely (RRF only), `Postgres\Store` interpolates it into a SQL ranking expression, and `Meilisearch\Store` forwards it as a backend payload : the three mechanisms are not interchangeable. Treat the value as a per-backend tuning knob; pick the absolute value the target bridge documentation recommends, and re-tune when you switch backends.

**Why store query limits are bridge-specific.** `StoreInterface::query(QueryInterface $query, array $options = []): iterable` carries an opaque `$options` array : the bridge owns it. `InMemory\Store` and `Cache\Store` read `maxItems` plus a `filter` callable; `Postgres\Store` reads `limit` and `maxScore`; `Pinecone\Store` reads `topK`; `Meilisearch\Store` reads `semanticRatio` (no client-side limit : the API returns the default top). When you compose a `Retriever` with a bridge, the keys you pass in `$options` are forwarded as-is, so consult the bridge's `query()` source before assuming a limit.
