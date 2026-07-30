# Store : API Reference

Source of truth: `https://github.com/symfony/ai/tree/main/src/store/src/`. All namespaces below use the `Symfony\AI\Store` root.

> The Store component is experimental : verify signatures against the source before pinning a version.

## Namespace tree

```php
Symfony\AI\Store
├── StoreInterface
├── ManagedStoreInterface
├── IndexerInterface
├── RetrieverInterface
├── Retriever
├── CombinedStore
├── TraceableStore
│
├── Document\
│   ├── EmbeddableDocumentInterface
│   ├── TextDocument
│   ├── VectorDocument
│   ├── Metadata
│   ├── VectorizerInterface
│   ├── Vectorizer           (concrete)
│   ├── TransformerInterface
│   ├── LoaderInterface
│   ├── FilterInterface
│   ├── Loader\
│   │   ├── CsvLoader
│   │   ├── DirectoryLoader
│   │   ├── InMemoryLoader
│   │   ├── JsonFileLoader
│   │   ├── MarkdownLoader
│   │   ├── RssFeedLoader          (with RssItem)
│   │   ├── RstLoader
│   │   ├── RstToctreeLoader
│   │   └── TextFileLoader
│   ├── Filter\
│   │   └── TextContainsFilter
│   └── Transformer\
│       ├── ChainTransformer
│       ├── ChunkDelayTransformer
│       ├── SummaryGeneratorTransformer
│       ├── TextReplaceTransformer
│       ├── TextSplitTransformer
│       └── TextTrimTransformer
│
├── Indexer\
│   ├── DocumentIndexer
│   ├── SourceIndexer
│   ├── DocumentProcessor
│   └── ConfiguredSourceIndexer
│
├── Query\
│   ├── QueryInterface
│   ├── VectorQuery
│   ├── TextQuery
│   └── HybridQuery
│
├── Distance\
│   ├── DistanceCalculator
│   └── DistanceStrategy           (enum)
│
├── Reranker\
│   ├── RerankerInterface
│   └── Reranker
│
├── Event\
│   ├── PreQueryEvent
│   └── PostQueryEvent
│
├── EventListener\
│   └── RerankerListener
│
├── InMemory\
│   └── Store
│
└── Bridge\                          (24 packages — see references/bridges.md)
```

There is **no** `Symfony\AI\Store\Indexer\Indexer` concrete class, no `Vectorizer\PlatformVectorizer`, no `Transformer\RemoveMetadataTransformer`. The interfaces themselves live at `Symfony\AI\Store\{IndexerInterface, Document\TransformerInterface, Document\VectorizerInterface}`, not under `Indexer\` or `Transformer\` or `Vectorizer\`.

## StoreInterface

```php
namespace Symfony\AI\Store;

interface StoreInterface
{
    public function add(VectorDocument|array $documents): void;
    public function remove(string|array $ids, array $options = []): void;
    public function clear(array $options = []): void;
    public function query(QueryInterface $query, array $options = []): iterable;
    public function supports(string $queryClass): bool;
}
```text

Notes:
- `add()` takes a single `VectorDocument` or an array of them : not variadic.
- `remove()` accepts a string id or an array of string ids; non-string ids (e.g. `int`) must be cast by the caller. The `InMemory\Store` casts via `(string) $document->getId()` internally.
- `query()` requires a `QueryInterface` : pass `VectorQuery`, `TextQuery`, or `HybridQuery`. It never takes a raw `Vector`.
- `supports()` takes the FQCN of a `QueryInterface` implementation.

`clear()` removes all documents but keeps the store usable. To destroy the underlying schema, use `ManagedStoreInterface::drop()`.

## ManagedStoreInterface

```php
namespace Symfony\AI\Store;

interface ManagedStoreInterface
{
    public function setup(array $options = []): void;
    public function drop(array $options = []): void;
}
```

- `setup()` creates the index / table / collection. Options are backend-specific (e.g. `['dimension' => 1536, 'metric' => 'cosine']` for Pinecone).
- `drop()` destroys the underlying infrastructure. It is *not* reversible.
- Not every bridge implements `ManagedStoreInterface` : `Supabase`, `AzureSearch`, etc. leave lifecycle to the user.

## IndexerInterface

```php
namespace Symfony\AI\Store;

interface IndexerInterface
{
    public function index(string|iterable|object $input, array $options = []): void;
}
```text

Three concrete indexers live under `Indexer\` : none of them is named `Indexer`:

### `DocumentIndexer`

```php
public function __construct(DocumentProcessor $processor);

public function index(string|iterable|object $input, array $options = []): void;
```

Accepts an `EmbeddableDocumentInterface` or an iterable of them; anything else throws `InvalidArgumentException`.

### `SourceIndexer`

```php
public function __construct(LoaderInterface $loader, DocumentProcessor $processor);

public function index(string|iterable|object|null $input = null, array $options = []): void;
```text

Accepts a source identifier (string or iterable of strings) and delegates to `LoaderInterface::load($source)`. `null` invokes the loader with no source (only works for source-independent loaders such as `InMemoryLoader`).

### `ConfiguredSourceIndexer`

```php
public function __construct(SourceIndexer $indexer, string|array $defaultSource);

public function index(string|iterable|object|null $input = null, array $options = []): void;
```

A decorator for `SourceIndexer` that supplies a default source when `$input` is `null` : useful for bundle configuration where the source is defined in YAML.

### `DocumentProcessor` (the actual pipeline)

```php
public function __construct(
    VectorizerInterface $vectorizer,
    StoreInterface $store,
    array $filters = [],
    array $transformers = [],
    LoggerInterface $logger = new NullLogger(),
);

public function process(iterable $documents, array $options = []): void;
```yaml

Pipeline: `filter → transform → vectorize → store`. Batches flush every 50 documents (override with `process($docs, ['chunk_size' => N])`). Per-batch options forwarded to the platform are `platform_options` (`process($docs, ['platform_options' => [...]])`).

## RetrieverInterface

```php
namespace Symfony\AI\Store;

interface RetrieverInterface
{
    public function retrieve(string $query, array $options = []): iterable;
}
```

The `Retriever` implementation:

```php
public function __construct(
    StoreInterface $store,
    ?VectorizerInterface $vectorizer = null,
    ?EventDispatcherInterface $eventDispatcher = null,
    LoggerInterface $logger = new NullLogger(),
);
```text

It picks the query type automatically: if the store supports `HybridQuery` it builds a `HybridQuery` with `semanticRatio = $options['semanticRatio'] ?? 0.5`; otherwise `VectorQuery` if supported, otherwise `TextQuery`. It dispatches `PreQueryEvent` before and `PostQueryEvent` after when an event dispatcher is wired.

## Query types

```php
namespace Symfony\AI\Store\Query;

interface QueryInterface {}

final class VectorQuery implements QueryInterface
{
    public function __construct(Vector $vector);
    public function getVector(): Vector;
}

final class TextQuery implements QueryInterface
{
    public function __construct(string|array $text);
    public function getText(): string;
    public function getTexts(): array;
}

final class HybridQuery implements QueryInterface
{
    public function __construct(Vector $vector, string|array $text, float $semanticRatio = 0.5);
    public function getVector(): Vector;
    public function getText(): string;
    public function getTexts(): array;
    public function getSemanticRatio(): float;
    public function getKeywordRatio(): float;
}
```

`HybridQuery` constructor throws `InvalidArgumentException` if `$semanticRatio` is outside `[0.0, 1.0]`.

## Document types

### TextDocument

```php
namespace Symfony\AI\Store\Document;

final class TextDocument implements EmbeddableDocumentInterface
{
    public function __construct(
        int|string $id,        // REQUIRED first positional
        string $content,       // REQUIRED; empty content throws
        Metadata $metadata = new Metadata(),
    );

    public function withContent(string $content): self;
    public function getId(): int|string;
    public function getContent(): string;
    public function getMetadata(): Metadata;
}
```php

### VectorDocument

```php
namespace Symfony\AI\Store\Document;

final class VectorDocument
{
    public function __construct(
        int|string $id,
        VectorInterface $vector,
        Metadata $metadata = new Metadata(),
        ?float $score = null,
    );

    public function withScore(float $score): self;   // returns a new instance
    public function getId(): int|string;
    public function getVector(): VectorInterface;
    public function getMetadata(): Metadata;
    public function getScore(): ?float;
}
```

`VectorInterface` (from `Symfony\AI\Platform\Vector\VectorInterface`) exposes `getData(): list<float>` and `getDimensions(): int`.

### Metadata

```php
final class Metadata extends \ArrayObject
{
    public const KEY_PARENT_ID = '_parent_id';
    public const KEY_TEXT      = '_text';
    public const KEY_SOURCE    = '_source';
    public const KEY_SUMMARY   = '_summary';
    public const KEY_TITLE     = '_title';
    public const KEY_DEPTH     = '_depth';

    // typed accessors
    public function hasParentId(): bool;
    public function getParentId(): int|string|null;
    public function setParentId(int|string $parentId): void;

    public function hasText(): bool;
    public function getText(): ?string;
    public function setText(string $text): void;

    public function hasSource(): bool;
    public function getSource(): ?string;
    public function setSource(string $source): void;

    public function hasSummary(): bool;
    public function getSummary(): ?string;
    public function setSummary(string $summary): void;

    public function hasTitle(): bool;
    public function getTitle(): ?string;
    public function setTitle(string $title): void;

    public function hasDepth(): bool;
    public function getDepth(): ?int;
    public function setDepth(int $depth): void;
}
```text

The reserved keys (`_text`, `_parent_id`, …) are used by transformers and bridges; do not repurpose them for your own data.

### EmbeddableDocumentInterface

```php
namespace Symfony\AI\Store\Document;

interface EmbeddableDocumentInterface
{
    public function getId(): int|string;
    public function getContent(): string|object;
    public function getMetadata(): Metadata;
}
```

## Vectorizer

### `VectorizerInterface`

```php
namespace Symfony\AI\Store\Document;

interface VectorizerInterface
{
    public function vectorize(
        string|\Stringable|EmbeddableDocumentInterface|array $values,
        array $options = [],
    ): Vector|VectorDocument|array;
}
```text

A single method. The return type narrows by input shape : string in ⇒ `Vector` out; `EmbeddableDocumentInterface` in ⇒ `VectorDocument` out; array in ⇒ array out.

### `Vectorizer` (concrete)

```php
namespace Symfony\AI\Store\Document;

final class Vectorizer implements VectorizerInterface
{
    public function __construct(
        PlatformInterface $platform,
        string $model,
        LoggerInterface $logger = new NullLogger(),
        bool $includeText = false,
    );
}
```

The fourth constructor argument (`bool $includeText = false`) controls whether the source text is copied into `Metadata::KEY_TEXT` when vectorizing an `EmbeddableDocumentInterface`. Without it, downstream `TextQuery` and `Reranker` cannot recover the original text.

## Transformers

All under `Symfony\AI\Store\Document\Transformer\`. The interface lives at `Symfony\AI\Store\Document\TransformerInterface`.

### ChainTransformer

```php
public function __construct(iterable $transformers);   // REQUIRED
public function transform(iterable $documents, array $options = []): iterable;
```text

Applies each transformer in sequence, replacing the document stream with the result of the previous one.

### TextSplitTransformer

```php
public function __construct(
    int $chunkSize = 1000,    // default
    int $overlap   = 200,     // default; must be >= 0 and < $chunkSize
);

public const OPTION_CHUNK_SIZE = 'chunk_size';
public const OPTION_OVERLAP    = 'overlap';

public function transform(iterable $documents, array $options = []): iterable;
```

Each chunk becomes a fresh `TextDocument` with `Metadata::KEY_PARENT_ID` set to the original id. Chunks shorter than `$chunkSize` are yielded as-is (with `KEY_TEXT` set).

### ChunkDelayTransformer

```php
public function __construct(
    ClockInterface $clock,                  // REQUIRED first positional
    int $chunkSize = 50,
    int $delay     = 10,                    // seconds
    LoggerInterface $logger = new NullLogger(),
);

public const OPTION_CHUNK_SIZE = 'chunk_size';
public const OPTION_DELAY      = 'delay';
```php

Useful for rate-limiting the embedding API. Uses `$clock->sleep($delay)` between batches. Pass `Symfony\Component\Clock\NativeClock` in production and `Symfony\Component\Clock\MockClock` in tests.

### SummaryGeneratorTransformer

```php
public function __construct(
    PlatformInterface $platform,
    string $model,
    bool $yieldSummaryDocuments = false,
    string $systemPrompt = 'Summarize the following text in 2-3 sentences, capturing the key concepts and any technical terms. Be concise and precise.',
);
```

Generates a summary per document via the platform and stores it under `Metadata::KEY_SUMMARY`. When `$yieldSummaryDocuments` is `true`, it also yields a new `TextDocument` whose content is the summary and whose metadata has `KEY_TEXT` set to the summary : a dual-indexing mode.

### TextReplaceTransformer

```php
public function __construct(
    string $search = '',
    string $replace = '',
);

public const OPTION_SEARCH  = 'search';
public const OPTION_REPLACE = 'replace';
```text

Throws if `$search === $replace`.

### TextTrimTransformer

```php
public function transform(iterable $documents, array $options = []): iterable;
```

No constructor arguments. Trims leading/trailing whitespace from each document's content using `trim()`.

## LoaderInterface

```php
namespace Symfony\AI\Store\Document;

interface LoaderInterface
{
    public function load(?string $source = null, array $options = []): iterable;
}
```text

`$source` is `null` for source-independent loaders (`InMemoryLoader`).

### Loaders

| Class              | Constructor                                                                                                                                                                                                  | Notes                                                                                             |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------- |
| `CsvLoader`        | `(string\|int $contentColumn = 'content', string\|int\|null $idColumn = null, array $metadataColumns = [], string $delimiter = ',', string $enclosure = '"', string $escape = '\\', bool $hasHeader = true)` | One CSV row → one `TextDocument`.                                                                 |
| `DirectoryLoader`  | `(array $loaders, bool $recursive = true)`                                                                                                                                                                   | Map of file extension (without dot) to a loader. Requires `symfony/finder`.                       |
| `InMemoryLoader`   | `(array $documents = [])`                                                                                                                                                                                    | Yields prebuilt documents; ignores `$source`.                                                     |
| `JsonFileLoader`   | `(string $id, string $content, array $metadata = [])`                                                                                                                                                        | JsonPath expressions for id, content, metadata. Requires `symfony/json-path`.                     |
| `MarkdownLoader`   | no constructor                                                                                                                                                                                               | Optional `$options['strip_formatting'] = true`. Requires `symfony/string` + `symfony/filesystem`. |
| `RssFeedLoader`    | `(HttpClientInterface $httpClient, string $uuidNamespace = '6ba7b810-9dad-11d1-80b4-00c04fd430c8')`                                                                                                          | UUID v5 generated from `guid` or `link`. Requires `symfony/dom-crawler`.                          |
| `RstLoader`        | no constructor                                                                                                                                                                                               | Splits RST on heading boundaries.                                                                 |
| `RstToctreeLoader` | `(RstLoader $rstLoader = new RstLoader(), bool $throwOnMissingEntry = false, LoggerInterface $logger = new NullLogger(), ?int $maxDepth = null)`                                                             | Follows `.. toctree::` directives.                                                                |
| `TextFileLoader`   | no constructor                                                                                                                                                                                               | One file → one `TextDocument` with `Uuid::v4()` id.                                               |

`RssFeedLoader` produces a `TextDocument` whose id is a `Uuid`, with `Metadata::KEY_SOURCE` set to the feed URL and the RSS metadata (title, date, link, author, description, content) stored as plain keys.

## Filters

```php
namespace Symfony\AI\Store\Document\Filter;

interface FilterInterface
{
    public function filter(iterable $documents, array $options = []): iterable;
}
```

`TextContainsFilter(string $needle, bool $caseSensitive = false)` : yields documents whose content does **not** contain the needle (i.e. it removes matches). Supports `$options[self::OPTION_NEEDLE]` and `$options[self::OPTION_CASE_SENSITIVE]`.

## Reranker

```php
namespace Symfony\AI\Store\Reranker;

interface RerankerInterface
{
    public function rerank(string $query, array $documents, int $topK = 5): array;
}

final class Reranker implements RerankerInterface
{
    public function __construct(
        PlatformInterface $platform,
        string $model,                     // e.g. a Cohere reranker model
        LoggerInterface $logger = new NullLogger(),
    );
}
```php

`Reranker::rerank()` pulls text from `Metadata::KEY_TEXT` (or `KEY_SOURCE` as a fallback) and calls `$platform->invoke($model, ['query' => ..., 'texts' => [...]])->asReranking()`. It returns a `list<VectorDocument>` re-ordered by descending reranker score.

```php
namespace Symfony\AI\Store\EventListener;

final class RerankerListener
{
    public function __construct(RerankerInterface $reranker, int $topK = 5);
    public function __invoke(PostQueryEvent $event): void;
}
```

Reads `$event->getOptions()['topK']` first, falling back to the constructor default.

## Distance

```php
namespace Symfony\AI\Store\Distance;

enum DistanceStrategy: string
{
    case COSINE_DISTANCE     = 'cosine';
    case ANGULAR_DISTANCE    = 'angular';
    case EUCLIDEAN_DISTANCE  = 'euclidean';
    case MANHATTAN_DISTANCE  = 'manhattan';
    case CHEBYSHEV_DISTANCE  = 'chebyshev';
}

final class DistanceCalculator
{
    public function __construct(
        DistanceStrategy $strategy = DistanceStrategy::COSINE_DISTANCE,
        int $batchSize = 100,        // only used when maxItems is set
    );

    public function calculate(array $documents, Vector $vector, ?int $maxItems = null): array;
}
```text

Used by `InMemory\Store` and `Bridge\Cache\Store` to score documents in-process. `calculate()` returns `VectorDocument[]` with `withScore()` applied.

## Events

```php
namespace Symfony\AI\Store\Event;

final class PreQueryEvent extends Event
{
    public function __construct(string $query, array $options = []);
    public function getQuery(): string;
    public function setQuery(string $query): void;
    public function getOptions(): array;
    public function setOptions(array $options): void;
}

final class PostQueryEvent extends Event
{
    public function __construct(string $query, iterable $documents, array $options = []);
    public function getQuery(): string;
    public function getDocuments(): iterable;
    public function setDocuments(iterable $documents): void;
    public function getOptions(): array;
}
```

Both are dispatched by `Retriever` (when an `EventDispatcherInterface` is wired) and observed by `RerankerListener`.

## Commands

All under `Symfony\AI\Store\Command\`. They are tagged in `ai-bundle` for `bin/console`:

| Command                                             | Purpose                                                   | Notes                                                 |
| --------------------------------------------------- | --------------------------------------------------------- | ----------------------------------------------------- |
| `ai:store:setup <store>`                            | Call `ManagedStoreInterface::setup()` on the named store. | Iterates `ServiceLocator<ManagedStoreInterface>`.     |
| `ai:store:drop <store> --force`                     | Destroy the store's infrastructure.                       | Requires `--force` (no default).                      |
| `ai:store:clear <store> --force`                    | Remove all documents, keep the store.                     | Different from `drop` : store remains usable.         |
| `ai:store:index <indexer> [--source=…]`             | Run a `SourceIndexer` / `ConfiguredSourceIndexer`.        | Multiple `--source` allowed.                          |
| `ai:store:retrieve <retriever> [query] [--limit=N]` | Query via a configured `RetrieverInterface`.              | Interactive if `$query` is omitted; default limit 10. |

## Exceptions

All under `Symfony\AI\Store\Exception\`. All implement `ExceptionInterface`:

- `InvalidArgumentException` (extends `\InvalidArgumentException`)
- `RuntimeException` (extends `\RuntimeException`)
- `UnsupportedFeatureException` (extends `\LogicException`)
- `UnsupportedQueryTypeException` (extends `\RuntimeException`) : constructor: `(string $queryClass, StoreInterface $store)`.

There is **no** `DimensionMismatchException`. Dimension mismatch surfaces as `InvalidArgumentException` from the platform `Vector` constructor, or as a backend-specific runtime error.

## CombinedStore and TraceableStore

```php
final class CombinedStore implements StoreInterface
{
    public function __construct(
        StoreInterface $vectorStore,
        StoreInterface $textStore,
        int $rrfK = 60,   // Reciprocal Rank Fusion constant
    );
}
```text

For a `HybridQuery`, splits it into `VectorQuery` + `TextQuery`, queries each side, and merges using Reciprocal Rank Fusion. Other query types are forwarded to the appropriate sub-store based on `supports()`.

```php
final class TraceableStore implements StoreInterface, ManagedStoreInterface, ResetInterface
{
    public function __construct(
        StoreInterface $store,
        ClockInterface $clock = new MonotonicClock(),
    );

    public function getCalls(): array;   // for debugging / assertions
    public function getDecoratedStore(): StoreInterface;
    public function reset(): void;
}
```

`setup()` / `drop()` are forwarded only if the decorated store implements `ManagedStoreInterface`.

## InMemory\Store

```php
final class Store implements ManagedStoreInterface, StoreInterface, ResetInterface
{
    public function __construct(DistanceCalculator $distanceCalculator = new DistanceCalculator());

    public function setup(array $options = []): void;
    public function drop(array $options = []): void;
    public function reset(): void;

    public function add(VectorDocument|array $documents): void;
    public function remove(string|array $ids, array $options = []): void;
    public function clear(array $options = []): void;
    public function supports(string $queryClass): bool;

    /**
     * @param array{maxItems?: positive-int, filter?: callable(VectorDocument): bool} $options
     */
    public function query(QueryInterface $query, array $options = []): iterable;
}
```

`setup()` rejects any non-empty `$options`. The query options support both `maxItems` and a per-document `filter` callable.

## Bridges

See `references/bridges.md` for the catalogue of 24 packages. Each bridge exposes its own `Store` (or `SearchStore`, `VecStore` for `Sqlite`) class implementing `StoreInterface`, plus an optional `ManagedStoreInterface`.
