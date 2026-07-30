---
title: Agent response with source metadata
composes: platform, agent, ai-bundle
target-version: PHP 8.2+ / Symfony 6.4 | 7.4 | 8.0
last-verified: 2026-07-29
---

> Symfony AI is **experimental** : APIs may break between releases. Always check `UPGRADE.md` in the [symfony/ai monorepo](https://github.com/symfony/ai) before upgrading.

Look up sections of an internal engineering handbook through a tool that returns both an answer and a `Source` for each section it touched, propagate the sources through `AgentProcessor` (with `includeSources: true`), and consume the agent's text and the provenance list separately so the UI can show "no provenance available" when the tool returns nothing attributable.

## Composes

- **`platform`** : `Symfony\AI\Platform\Bridge\OpenAi\Factory` (or any other platform factory) plus the chat model identifier (e.g. `gpt-4o-mini`).
- **`agent`** : `Symfony\AI\Agent\Agent`, `Symfony\AI\Agent\Toolbox\Toolbox`, `Toolbox\AgentProcessor`, and the source-propagation contract `Toolbox\Source\HasSourcesInterface` / `HasSourcesTrait` / `Source` / `SourceCollection`.

## Installation

```bash
composer require symfony/ai-platform symfony/ai-agent
composer require symfony/ai-open-ai-platform
composer require symfony/ai-bundle   # optional YAML wiring
```

## Critical API rules

From `src/agent/src/Toolbox/AgentProcessor.php` and `src/agent/src/Toolbox/Toolbox.php`:

- `AgentProcessor` merges every `ToolResult::getSources()` into its internal `SourceCollection` **only when constructed with `includeSources: true`** (default is `false`). The merged collection is exposed on the final `ToolCallResult` under metadata key `sources` once the outermost tool loop completes. For streamed runs, drain the stream first; the metadata is only final then.
- `Toolbox::execute()` instantiates a fresh `SourceCollection` per call and passes it to the tool via `HasSourcesInterface::setSourceCollection()` when the tool implements the interface. A tool that does **not** implement `HasSourcesInterface` produces a `ToolResult` with `getSources() === null` and contributes no provenance.
- `SourceCollection::merge()` concatenates; it does not deduplicate. Your application layer normalises duplicates (typically by `reference`).
- `Toolbox::__construct(iterable $tools, ...)` is **not** variadic. Always pass an array: `new Toolbox([new HandbookLookup()])`.
- `Agent::__construct(PlatformInterface $platform, string $model, iterable $inputProcessors = [], iterable $outputProcessors = [], string $name = 'agent')` has **no** `$toolboxes` parameter. Tools enter the pipeline via an `AgentProcessor` registered in both processor lists.
- `#[AsTool]` is `TARGET_CLASS | IS_REPEATABLE` (`src/agent/src/Toolbox/Attribute/AsTool.php`). Put it on the **class**.

## Domain: internal engineering handbook

The tool searches a small, versioned handbook. Each section has a stable reference (e.g. `handbook/security/csrf.md#token-storage`), a human-readable title, and the section text. The tool returns both the answer content the agent will see and a `Source` per matched section.

```text
Handbook section: name, reference, content
HandbookLookup tool returns: answer text + SourceCollection (zero or more)
AgentProcessor with includeSources: true merges them into result metadata
Application reads metadata('sources') separately from the agent text
```

## The tool

A source-aware tool implements `HasSourcesInterface` and uses `HasSourcesTrait` so it can register `Source` objects during the call:

```php
namespace App\Handbook;

use Symfony\AI\Agent\Toolbox\Attribute\AsTool;
use Symfony\AI\Agent\Toolbox\Source\HasSourcesInterface;
use Symfony\AI\Agent\Toolbox\Source\HasSourcesTrait;
use Symfony\AI\Agent\Toolbox\Source\Source;

#[AsTool(
    name: 'handbook_search',
    description: 'Search the internal engineering handbook for sections matching the query. Returns the top matching sections and their references.',
    method: '__invoke',
)]
final class HandbookLookup implements HasSourcesInterface
{
    use HasSourcesTrait;

    /**
     * @var list<array{name: string, reference: string, content: string}>
     */
    private const SECTIONS = [
        [
            'name' => 'CSRF token storage',
            'reference' => 'handbook/security/csrf.md#token-storage',
            'content' => 'CSRF tokens must be stored in encrypted session storage with HttpOnly + SameSite=Lax cookies.',
        ],
        [
            'name' => 'Cache key conventions',
            'reference' => 'handbook/performance/cache-keys.md',
            'content' => 'Cache keys are namespaced by feature, then version. Use psr-6 namespace per bounded context.',
        ],
        [
            'name' => 'Migration review checklist',
            'reference' => 'handbook/database/migrations.md#review',
            'content' => 'Every migration must be reversible, declared in a single PR, and reviewed by a second engineer.',
        ],
    ];

    public function __invoke(string $query): string
    {
        $matches = [];
        $needle = strtolower($query);
        foreach (self::SECTIONS as $section) {
            if (str_contains(strtolower($section['content']), $needle)) {
                $this->addSource(new Source(
                    $section['name'],
                    $section['reference'],
                    $section['content'],
                ));
                $matches[] = $section['name'];
            }
        }

        if ([] === $matches) {
            return 'No matching handbook sections were found for the query.';
        }

        return sprintf(
            'Found %d matching handbook section(s): %s.',
            \count($matches),
            implode(', ', $matches),
        );
    }
}
```

Key points:

- The tool **always** returns a string for the agent (so the model has something to ground its answer in). Provenance is added **on top** via `addSource()`.
- A miss produces a non-empty answer and an empty `SourceCollection`. Downstream that becomes `"sourceStatus": "unavailable"`, never "hidden".

## Wiring the agent

The tool is wrapped in a `Toolbox`, the toolbox in an `AgentProcessor` with `includeSources: true`, and the processor is registered in both lists of an `Agent`:

```php
use Symfony\AI\Agent\Agent;
use Symfony\AI\Agent\Toolbox\AgentProcessor;
use Symfony\AI\Agent\Toolbox\Toolbox;
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);

$toolbox = new Toolbox([new HandbookLookup()]);
$toolProcessor = new AgentProcessor(
    $toolbox,
    eventDispatcher: $dispatcher,   // optional; share with the rest of the lifecycle
    includeSources: true,
);

$agent = new Agent(
    $platform,
    'gpt-4o-mini',
    [$toolProcessor],   // inputProcessors
    [$toolProcessor],   // outputProcessors
);

$result = $agent->call('What is the rule for CSRF token storage?');
```

After the tool loop completes, `$result->getMetadata()['sources']` is a `SourceCollection` aggregating every `Source` produced by every tool call in the loop. For streamed runs, consume the stream before reading metadata.

## Consuming the answer and the sources separately

The agent's final `ResultInterface` carries two distinct things: the assistant text (`getContent()`) and the provenance collection (`getMetadata()['sources']`). Render them as two separate fields. Normalise and deduplicate the collection by reference so a section matched twice appears once:

```php
namespace App\Handbook;

use Symfony\AI\Agent\Toolbox\Source\SourceCollection;
use Symfony\AI\Platform\Result\ResultInterface;

/**
 * @return array{answer: string, sources: list<array{name: string, reference: string}>, sourceStatus: string}
 */
function presentHandbookAnswer(string $answer, SourceCollection $sources): array
{
    $normalised = [];
    $seen = [];

    foreach ($sources as $source) {
        $reference = $source->getReference();
        if ('' === $reference || isset($seen[$reference])) {
            continue;
        }
        $seen[$reference] = true;
        $normalised[] = [
            'name' => $source->getName(),
            'reference' => $reference,
        ];
    }

    return [
        'answer' => $answer,
        'sources' => $normalised,
        'sourceStatus' => [] === $normalised ? 'unavailable' : 'complete',
    ];
}

function extractAnswer(ResultInterface $result): string
{
    $content = $result->getContent();

    if (\is_array($content)) {
        return implode(' ', array_map(static fn ($part) => (string) $part, $content));
    }

    return (string) $content;
}

function extractSources(ResultInterface $result): SourceCollection
{
    $metadata = $result->getMetadata();
    $sources = $metadata['sources'] ?? null;

    if ($sources instanceof SourceCollection) {
        return $sources;
    }

    return new SourceCollection();
}
```

Three guarantees encoded here:

1. **Answer and sources are read separately.** The answer text is never inspected to extract provenance.
2. **Sources are deduplicated by `reference`.** A section matched by two tool calls collapses to one entry.
3. **An empty collection surfaces as `"sourceStatus": "unavailable"`.** The caller can render an explicit "no provenance available" banner : the absence is never hidden.

## Controller

```php
namespace App\Controller;

use App\Handbook\HandbookLookup;
use App\Handbook\presentHandbookAnswer;
use App\Handbook\extractAnswer;
use App\Handbook\extractSources;
use Symfony\AI\Agent\AgentInterface;
use Symfony\AI\Agent\Toolbox\AgentProcessor;
use Symfony\AI\Agent\Toolbox\Toolbox;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

final class HandbookController
{
    public function __construct(private readonly AgentInterface $handbookAgent)
    {
    }

    #[Route('/handbook/answer', methods: ['POST'])]
    public function answer(Request $request): Response
    {
        $query = (string) $request->request->get('query');

        $result = $this->handbookAgent->call($query);

        return new JsonResponse(presentHandbookAnswer(
            extractAnswer($result),
            extractSources($result),
        ));
    }
}
```

The JSON shape is `{answer, sources: [{name, reference}], sourceStatus: "complete" | "unavailable"}`. When `sourceStatus === "unavailable"`, `sources` is an empty list : the UI renders the empty state explicitly.

## YAML wiring (with the bundle)

`config/packages/ai.yaml` : keys verified against `src/ai-bundle/config/options.php`:

```yaml
ai:
    platform:
        openai:
            api_key: '%env(OPENAI_API_KEY)%'

    agent:
        handbook:
            platform: 'ai.platform.openai'
            model: 'gpt-4o-mini'
            tools:
                services:
                    - service: 'App\Handbook\HandbookLookup'
            include_sources: true
```

The bundle compiles the `Agent` and wires an `AgentProcessor` around the toolbox with `includeSources: true` when `include_sources: true` is set on the agent config block.

## Guarantees

- A tool implementing `HasSourcesInterface` propagates its `Source` objects via `AgentProcessor` (with `includeSources: true`) onto the final `ResultInterface` metadata under the key `sources`.
- The sources are surfaced **alongside** the agent's text content, not interleaved with it. The application code reads them through two independent accessors.
- The provenance contract is by `reference` (a stable path-like string). Two `Source` objects sharing a reference describe the same provenance and should be collapsed by the consumer.

## Non-guarantees

- The agent does **not** guarantee phrase-level alignment between the answer and the sources. The text may paraphrase; a section listed in `sources` may not be cited verbatim, and a fact in the answer may not be listed. Do not infer citation by string overlap.
- Sources do **not** verify factual accuracy. `Source::getContent()` is whatever the tool returned; neither the framework nor the model validates it.
- A tool that returns no `Source` (either because it does not implement `HasSourcesInterface` or because it had nothing to add) produces no provenance on the final answer. The application sees an empty `SourceCollection` and is responsible for surfacing this as an explicit `"sourceStatus": "unavailable"` : there is no implicit "unknown" status.

## Offline test

The proof at `tests/recipes/source-metadata-proof.php` is the canonical invariant test for this recipe. It runs without network, without an LLM, and without Composer autoloading : it loads the source classes directly from the monorepo and exercises the same normalisation the controller uses.

```bash
php -d assert.exception=1 tests/recipes/source-metadata-proof.php
```

The `assert.exception=1` setting is required so a failed invariant raises an exception instead of potentially exiting successfully when assertions are disabled.

Expected output:

```text
PROOF OK: source-metadata (5/5 assertions, 3 sources, status=complete)
```

The five assertions encode the contract:

1. multiple tool calls accumulate into a single merged `SourceCollection`;
2. references are deduplicated by value (two `Source`s sharing `policy/auth.md` collapse to one);
3. the answer text remains accessible as a plain string, separate from sources;
4. an empty `SourceCollection` is reported as `"unavailable"`, never as `"complete"`;
5. the answer is not augmented with citation markers; provenance is delivered out-of-band through the metadata collection rather than by mutating the answer text.

When you adapt the proof to your own domain, keep those five invariant shapes : they're the minimum surface area that makes the recipe's guarantees testable.

## See also

- `platform` skill : model invocation, bridge factories
- `agent` skill : `Agent`, `AgentProcessor`, `Toolbox`, source-propagation contract
- `ai-bundle` skill : YAML wiring for agents and tools
- `agent` skill reference: `references/patterns.md` section 6 : shared lifecycle dispatcher and source propagation
- [tool-calling-agent](tool-calling-agent.md) : extend a source-aware agent with more tools
