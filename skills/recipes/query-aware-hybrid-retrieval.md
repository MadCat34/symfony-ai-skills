---
title: Query-aware hybrid retrieval
composes: platform, agent, ai-bundle, store
target-version: PHP 8.2+ / Symfony 6.4 | 7.4 | 8.0
last-verified: 2026-07-29
---

> Symfony AI is **experimental** : APIs may break between releases. Always check `UPGRADE.md` in the [symfony/ai monorepo](https://github.com/symfony/ai) before upgrading.

Pick a retrieval strategy (lexical, semantic, or hybrid) at query time from a deterministic, application-owned query classifier, run a single `Retriever::retrieve()` call against a hybrid-capable store, and surface the chosen strategy alongside the hits so callers can see *why* a given strategy was applied. This recipe is a **policy and observability pattern**: the classifier is application code, not a Symfony AI primitive, and the chosen strategy is always reported in the response. It does **not** prescribe model quality, embedding quality, or any specific scoring weight.

## Composes

- **`platform`** : the embedding model used by `Vectorizer`.
- **`agent`** : `Agent` and `Toolbox` turn the policy tool into a tool the model can call.
- **`ai-bundle`** : YAML wiring for the platform, agent and application services.
- **`store`** : `CombinedStore` (or a native hybrid store such as `Meilisearch\Store`, `Postgres\Store`, `Sqlite\Store`, `Cache\Store`) plus `Retriever`.

## Installation

```bash
composer require symfony/ai-platform symfony/ai-agent symfony/ai-bundle symfony/ai-store
composer require symfony/ai-open-ai-platform
```

No provider API, credentials or network are needed for the offline proof below. In production, configure the platform credentials through your secret manager.

## Domain: research-paper citation lookup

The corpus is a small set of research papers. Each entry has a stable reference (`paper-id`), a title, an abstract, and free-form tags. Queries come in three shapes:

- Exact identifiers, e.g. `paper-2024-12` : **lexical** is the right strategy.
- Conceptual questions, e.g. `How do teams train models without sharing raw data?` : **semantic** is the right strategy.
- Mixed term + intent, e.g. `federated learning privacy guarantees` : **hybrid** is the right strategy.

The retrieval pipeline must (1) classify the query, (2) choose a concrete strategy, (3) call the store with that strategy, (4) include the chosen strategy in the response so the caller can audit the decision.

```text
Query "paper-2024-12"        -> classifier -> lexical  -> TextQuery      -> store
Query "How does X work?"     -> classifier -> semantic -> VectorQuery    -> store
Query "federated learning…"  -> classifier -> hybrid   -> HybridQuery    -> CombinedStore (RRF) / native hybrid store
```

The classifier itself is application-owned code. Symfony AI does not provide a query classifier : the policy is your responsibility.

## The application-owned query classifier

The classifier is a pure function: same query in, same strategy out. It returns one of three strings : `lexical`, `semantic`, `hybrid` : and nothing else.

```php
namespace App\Papers;

/**
 * Classifies an inbound query into a retrieval strategy.
 *
 * Implementation is application-owned — Symfony AI does not ship a
 * classifier. The chosen strategy is surfaced in the response so
 * callers can audit the decision without re-running the pipeline.
 *
 * @return 'lexical'|'semantic'|'hybrid'
 */
function classify_query(string $query): string
{
    $trimmed = trim($query);

    // Exact identifier: an all-caps alnum + dash token, e.g. "paper-2024-12".
    if (1 === preg_match('/^[A-Z][A-Z0-9-]+$/', $trimmed)) {
        return 'lexical';
    }

    // Conceptual question: ends with "?" or starts with a question word.
    if (str_contains($trimmed, '?')
        || 1 === preg_match('/^(how|what|why|when|where|which|who|can|should|do|does)\b/i', $trimmed)
    ) {
        return 'semantic';
    }

    // Mixed term + intent: anything else (multi-token without question mark).
    return 'hybrid';
}
```

The classifier never reads configuration, never touches the network, and never calls an LLM. Re-classification of the same string always returns the same strategy.

## Mapping class to concrete strategy

The `Retriever` accepts the query string and an `$options` array and decides which `QueryInterface` to build. The classifier's output is forwarded as `strategy`; the retriever picks the matching query object:

```php
namespace App\Papers;

/**
 * @return array{strategy: 'lexical'|'semantic'|'hybrid', retriever: \Symfony\AI\Store\Retriever}
 */
function paper_retriever(string $query, \Symfony\AI\Store\Retriever $retriever): array
{
    $strategy = classify_query($query);

    return [
        'strategy' => $strategy,
        'retriever' => $retriever,
    ];
}
```

The retriever owns the store, the vectorizer, and any `PreQueryEvent`/`PostQueryEvent` listeners. The recipe only adds a deterministic decision (the classifier) and an observability hook (the strategy in the response).

## Wiring the hybrid store

The classical way to combine vector search with full-text search is `CombinedStore`, which decomposes a `HybridQuery` into a `VectorQuery` and a `TextQuery`, queries both sub-stores, and merges results by Reciprocal Rank Fusion (`rrfK`). The constructor signature is `__construct(StoreInterface $vectorStore, StoreInterface $textStore, int $rrfK = 60)` : pass exactly those three positional or named arguments:

```php
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;
use Symfony\AI\Store\Bridge\Meilisearch\Store as MeilisearchVectorStore;
use Symfony\AI\Store\Bridge\Meilisearch\Store as MeilisearchTextStore;
use Symfony\AI\Store\CombinedStore;
use Symfony\AI\Store\Document\Vectorizer;
use Symfony\AI\Store\Retriever;

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);
$vectorizer = new Vectorizer($platform, 'text-embedding-3-small');

// Two stores: one for vector search, one for full-text. Both share
// the same indexer pipeline in production. They can be the same
// instance when the backend supports hybrid natively.
$vectorStore = new MeilisearchVectorStore($httpClient, 'papers', vectorFieldName: 'vector');
$textStore   = new MeilisearchTextStore($httpClient, 'papers', vectorFieldName: 'text');

$store = new CombinedStore($vectorStore, $textStore, rrfK: 60);

$retriever = new Retriever(
    store: $store,
    vectorizer: $vectorizer,
);

// One call. The classifier decided the strategy before this line ran.
foreach ($retriever->retrieve($query) as $hit) {
    echo $hit->getId(), ' → ', $hit->getScore(), PHP_EOL;
}
```

The chosen strategy is reported separately, in the response shape, so the caller can audit which path was taken.

> **Do not pass `semanticRatio` as a portable knob.** Its meaning is bridge-defined: `CombinedStore` ignores it entirely (RRF), `Postgres\Store` interpolates it into a SQL ranking expression, `Meilisearch\Store` forwards it as a backend payload. The three mechanisms are not interchangeable. The recipe deliberately does **not** configure `semanticRatio` : it is a per-bridge tuning knob, not part of the policy contract.

## Response shape: the strategy is observable

Whatever strategy the classifier chose, the response must surface it. The application defines the response DTO:

```php
namespace App\Papers;

use Symfony\AI\Store\Document\VectorDocument;

/**
 * @param iterable<VectorDocument> $hits
 *
 * @return array{
 *     query: string,
 *     strategy: 'lexical'|'semantic'|'hybrid',
 *     hits: list<array{id: string, score: float}>
 * }
 */
function present_paper_results(string $query, iterable $hits): array
{
    $rows = [];
    foreach ($hits as $hit) {
        $rows[] = ['id' => $hit->getId(), 'score' => $hit->getScore()];
    }

    return [
        'query' => $query,
        'strategy' => classify_query($query),
        'hits' => $rows,
    ];
}
```

The strategy is the same value the classifier returned before the store call; recomputing it on the response side is cheap because the classifier is pure. This is the observability contract: the caller always knows why a given strategy was applied.

```php
$bundle = paper_retriever($query, $retriever);
$strategy = $bundle['strategy'];

$hits = $bundle['retriever']->retrieve($query);

$response = present_paper_results($query, $hits);
// $response['strategy'] === $strategy  (always)
```

Three guarantees encoded here:

1. **The classifier is deterministic.** Same query in, same strategy out, every time.
2. **The strategy is surfaced in the response.** `strategy` is a top-level field; it is never hidden inside a metadata blob.
3. **The strategy is recomputable.** The classifier is a pure function on the query string; the response can be re-validated offline without re-running the pipeline.

## Putting it behind an agent tool

Expose the policy as a single tool so the model can call it with a free-form string from the user:

```php
namespace App\Papers;

use Symfony\AI\Agent\Toolbox\Attribute\AsTool;

#[AsTool(
    name: 'paper_lookup',
    description: 'Look up research papers by identifier or topic. Returns matching papers and the retrieval strategy used.',
    method: '__invoke',
)]
final class PaperLookup
{
    public function __construct(
        private readonly \Symfony\AI\Store\Retriever $papers,
    ) {
    }

    /**
     * @return array{
     *     query: string,
     *     strategy: 'lexical'|'semantic'|'hybrid',
     *     hits: list<array{id: string, score: float}>
     * }
     */
    public function __invoke(string $query): array
    {
        return present_paper_results($query, $this->papers->retrieve($query));
    }
}
```

The tool returns the structured array above, so the agent's text stays separate from the auditable strategy and provenance.

## YAML wiring

`config/packages/ai.yaml` wires the platform, the agent, the embedding model and the tool:

```yaml
ai:
    platform:
        openai:
            api_key: '%env(OPENAI_API_KEY)%'

    agent:
        papers:
            platform: 'ai.platform.openai'
            model: 'gpt-4o-mini'
            tools:
                services:
                    - service: 'App\Papers\PaperLookup'
            include_sources: true
```

The bundle compiles the `Agent` and wires an `AgentProcessor` around the toolbox. `PaperLookup` is a service in your container, not a Symfony AI class : its constructor takes the `Retriever` you wired in the previous step.

## Guarantees

- The query classifier maps each inbound query to exactly one of `lexical`, `semantic`, or `hybrid`, deterministically.
- The chosen strategy is included in the response under a top-level `strategy` field, separate from the hits.
- The classifier is application code. Symfony AI does not ship it and does not infer it from the query at runtime.
- `CombinedStore` is constructed with exactly `(StoreInterface, StoreInterface, int $rrfK = 60)`. No additional constructor arguments are passed.
- The recipe is a policy and observability pattern; it does not prescribe any specific scoring weight or ratio.

## Non-guarantees

- `semanticRatio` is **not portable** between `CombinedStore` and native hybrid stores (`Meilisearch\Store`, `Postgres\Store`, `Sqlite\Store`, `Cache\Store`, `InMemory\Store`). Treat it as a per-bridge tuning knob. The recipe does not pass it.
- The recipe does **not** claim model-quality improvements. Real semantic retrieval depends on the embedding model and the bridge; the recipe's policy layer is orthogonal to model quality.
- The recipe does **not** claim any RAG accuracy or recall. The offline prototype exercises the classifier and the rank-fusion path on a tiny corpus and does not extrapolate to production corpora.
- The recipe does **not** imply that the prototype's character n-gram cosine is a real semantic model. The proof at `tests/recipes/query-aware-retrieval-proof.php` uses a deterministic proxy for the semantic score; production code must use a real embedding model via `Vectorizer`.
- Different store bridges require tuning per their own semantics. The classifier's three classes are a policy contract; the per-bridge ratio / limit / ranking expression is the bridge's own contract.

## Offline proof

The deterministic proof at `tests/recipes/query-aware-retrieval-proof.php` validates the policy and observability contract end-to-end. It runs without an LLM, embeddings, credentials or network. Four gates are checked: classifier mapping (G1), expected-document rank after query-aware ranking (G2), strategy surfaced in output (G3), and no `semanticRatio` portability claim (G4).

```bash
php -d assert.exception=1 tests/recipes/query-aware-retrieval-proof.php
```

The `assert.exception=1` setting is required so a failed invariant raises an exception instead of potentially exiting successfully when assertions are disabled.

Expected output:

```text
PROOF OK: query-aware-retrieval (3 queries × 3 scenarios, decision=publish)
```

The companion audit document `docs/audits/2026-07-29-query-aware-retrieval-prototype.md` records the gate-by-gate results and the `publish` decision.

## See also

- `platform` skill : embedding models and `Vectorizer`
- `agent` skill : `Toolbox` and `#[AsTool]` for exposing the policy
- `ai-bundle` skill : YAML wiring for agents and tools
- `store` skill : `Retriever`, `CombinedStore`, and the **Hybrid semantics per store** section in `references/patterns.md`
- `store` skill reference: `references/patterns.md` pattern 4 : `CombinedStore` + RRF + `RerankerListener` wiring
- `store` skill reference: `references/patterns.md` pattern 7 : `PreQueryEvent` for application-owned preprocessing
- [agent-response-with-source-metadata](agent-response-with-source-metadata.md) : surface provenance separately from the answer text
- [rag-postgres-pgvector](rag-postgres-pgvector.md) : native hybrid store example (`Postgres\Store` honours `semanticRatio` directly in SQL)
