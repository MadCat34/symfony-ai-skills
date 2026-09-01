# Platform : Embeddings, Vector, Reranking

Read this when the user asks for embeddings, vector search, similarity, or
reranking. These use a **different contract** than text generation : different
model identifier, different `Result` subtype, different bridge package.

## Contents

- Embeddings contract
- End-to-end RAG (Platform + Store)
- Embedding model selection (this codebase)
- Reranking
  - Cohere (canonical)
  - OpenRouter (alternative)
- Gotchas
- When to use what

## Embeddings contract

The Platform component does **not** ship a `PlatformVectorizer` or an
`Indexer` class. Embedding integration lives in the **`store`** component
under `Symfony\AI\Store\Document\Vectorizer` and
`Symfony\AI\Store\Indexer\DocumentIndexer`. At the raw Platform layer,
embeddings are just another model invocation.

Anthropic bridges do not expose a native embedding model; use a provider with an embedding capability for vector generation.

```php
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;
use Symfony\AI\Platform\Message\Message;
use Symfony\AI\Platform\Message\MessageBag;
use Symfony\AI\Platform\Vector\Vector;

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);

// One input → VectorResult wrapping a single Vector
$result = $platform->invoke('text-embedding-3-small', 'Hello world');
$vector = $result->asVectors()[0];           // asVectors() returns Vector[]

// Many inputs → VectorResult wrapping many Vector objects
$vectors = $platform->invoke('text-embedding-3-small', [
    'Hello',
    'World',
])->asVectors();
```

`DeferredResult::asVectors()` returns `Vector[]`. Each `Vector` is a final
value object: constructor `Vector(array $data, ?int $dimensions = null)`,
read via `getData(): list<float>` and `getDimensions(): int`. The constructor
throws `InvalidArgumentException` if the data is empty or if `$dimensions`
does not match `count($data)`.

For an array input, the bridge's `Embeddings\ModelClient` sends it directly as
the embedding input list. A string input is passed through as-is:
`StringToMessageBagListener` would wrap it in a `UserMessage`, but it only fires
when a dispatcher is wired into `Platform` (which `ai-bundle` does and the
standalone factories do not), and it bails out anyway unless the model declares
`Capability::INPUT_MESSAGES` — embedding models do not.

## End-to-end RAG (Platform + Store)

The `store` skill ships the `Document\Vectorizer`, `DocumentIndexer`, and
`StoreInterface`. This is the smallest working pipeline that lives entirely
in Symfony AI:

```php
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;
use Symfony\AI\Store\Document\TextDocument;
use Symfony\AI\Store\Document\Vectorizer;
use Symfony\AI\Store\Indexer\DocumentIndexer;
use Symfony\AI\Store\Indexer\DocumentProcessor;
use Symfony\AI\Store\InMemory\Store as InMemoryStore;
use Symfony\AI\Store\Query\VectorQuery;
use Symfony\Component\Uid\Uuid;

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);
$store = new InMemoryStore();

// Build the vectorizer (raw Platform → Vector[]) and the indexer
// that takes care of chunking, embedding, and persisting.
// includeText: true is what puts the original text in Metadata::KEY_TEXT;
// it defaults to false, and then getText() below returns null.
$vectorizer = new Vectorizer($platform, 'text-embedding-3-small', includeText: true);
$processor = new DocumentProcessor($vectorizer, $store);
$indexer = new DocumentIndexer($processor);

// Ingest documents
$indexer->index(new TextDocument(Uuid::v7(), 'Symfony is a PHP framework.'));
$indexer->index(new TextDocument(Uuid::v7(), 'Doctrine is an ORM.'));

// Query. vectorize(string) returns a single Vector, not an array — do not
// index into it. StoreInterface::query() takes a QueryInterface, so wrap the
// vector in a VectorQuery.
$queryVector = $vectorizer->vectorize('What is Symfony?');

foreach ($store->query(new VectorQuery($queryVector)) as $hit) {
    // VectorDocument has no `content` property. The original text is carried
    // in the metadata by Vectorizer::vectorizeEmbeddableDocuments().
    echo $hit->getId() . ': ' . $hit->getMetadata()->getText() . PHP_EOL;
}
```

In production replace `InMemoryStore` with one of the 24 vector-store bridges
(`store` skill). `StoreInterface::query(QueryInterface $query, array $options = []): iterable`
yields `VectorDocument` objects (`getId()`, `getVector()`, `getMetadata()`,
`getScore()`); which query types a given store accepts is reported by its
`supports()` method — see `store` skill for the per-bridge matrix.

## Embedding model selection (this codebase)

| Provider / bridge                                  | Embedding model         | Dim  | Notes                                |
|----------------------------------------------------|-------------------------|------|--------------------------------------|
| `symfony/ai-open-ai-platform`                      | `text-embedding-3-small`| 1536 | cheap default                        |
| `symfony/ai-open-ai-platform`                      | `text-embedding-3-large`| 3072 | better recall                        |
| `symfony/ai-voyage-platform` (`Voyage::INPUT_TYPE_DOCUMENT` / `_QUERY`) | `voyage-3`              | 1024 | strong general-purpose               |
| `symfony/ai-cohere-platform` (`Bridge\Cohere\Embeddings`) | `embed-english-v3.0` / `embed-multilingual-v3.0` | 1024 | dedicated embedding model            |
| `symfony/ai-gemini-platform` / `symfony/ai-vertex-ai-platform` | `text-embedding-…`      | varies | Google embeddings                     |
| `symfony/ai-mistral-platform`                      | `mistral-embed`         | 1024 | Mistral embeddings                   |
| `symfony/ai-azure-platform`                        | Azure-hosted OpenAI embedding | matches OpenAI dims | proxy of OpenAI          |

Critical: the query-time model **must** match the index-time model. Different
models produce incompatible vectors (different dimensions, different metric
spaces) : a mismatch crashes the store at insert time, not at query time.

## Reranking

Reranking lives in **two** bridges, both shipped as separate Composer
packages. There is **no** Voyage rerank in this codebase.

### Cohere (canonical)

`Bridge\Cohere\Reranker` with models `rerank-v3.5`, `rerank-v4.0-fast`,
`rerank-v4.0-pro`, `rerank-english-v3.0`, `rerank-multilingual-v3.0`. The
result type is `Result\RerankingResult`, an iterable of
`Reranking\RerankingEntry` (`getIndex(): int`, `getScore(): float`).

```php
use Symfony\AI\Platform\Bridge\Cohere\Factory as CohereFactory;
use Symfony\AI\Platform\Bridge\Cohere\Reranker;

$cohere = CohereFactory::createPlatform($_ENV['COHERE_API_KEY']);

$entries = $cohere->invoke(
    new Reranker('rerank-v3.5'),
    [
        'query' => 'What is Symfony?',
        // The payload key is `texts`; the ModelClient renames it to
        // `documents` on the wire. Passing `documents` throws
        // InvalidArgumentException (Reranker/ModelClient.php).
        'texts' => $candidateTexts,
    ],
)->asReranking();

foreach ($entries as $entry) {
    echo $entry->getIndex() . ' → ' . $entry->getScore() . PHP_EOL;
}
```

### OpenRouter (alternative)

`Bridge\OpenRouter\RerankModel` plus a `Rerank/` subnamespace under
`symfony/ai-open-router-platform`.

Typical pipeline: top-N from vector search → rerank → top-K to LLM context.

## Gotchas

- **Embeddings ≠ text completion**: do not pass `text-embedding-3-small` to
  `Platform::invoke()` expecting a text reply. The bridge registers it as an
  embedding model : the result is `VectorResult`, not `TextResult`.
- **Dimension mismatch crashes the store** at insert time. If you switch
  embedding model, drop and rebuild the index.
- **No streaming for embeddings.** Every provider returns the full vector
  synchronously.
- **`ResultInterface` has no `asVectors()`.** Only `DeferredResult` does.
  Always go through `DeferredResult::asVectors()`.
- **Rerank result is `RerankingEntry[]`** (with `int $index`, `float $score`),
  not `Vector[]`. Sort by score descending.
- **Cohere embeddings expect `InputType`** (`document` vs `query`) when
  constructed through `Voyage`-style options; the Cohere bridge passes that
  flag in the wire payload, but a raw `invoke()` call won't infer it for you.

## When to use what

| Need                          | Skill                                |
|-------------------------------|--------------------------------------|
| Generate embeddings           | `platform` (this file)               |
| Store + retrieve vectors      | `store`                              |
| RAG agent                     | `agent`                              |
| Rerank retrieved candidates   | `platform` (this file) + `store` (filtering) |
