---
title: Bounded customer-support document investigation
composes: platform, agent, ai-bundle
target-version: PHP 8.2+ / Symfony 6.4 | 7.4 | 8.0
last-verified: 2026-07-29
---

> Symfony AI is **experimental** : APIs may break between releases. Always check `UPGRADE.md` in the [symfony/ai monorepo](https://github.com/symfony/ai) before upgrading.

Answer a tenant support question from a small customer-support corpus while making the investigation budget explicit. The application owns the budget, consultation ledger, finding and report types; Symfony AI owns model invocation, tool calling and YAML wiring. The result always states whether the report completed or stopped at its limit.

## Composes

- **`platform`** : the model platform and chat model used for structured invocation.
- **`agent`** : `Agent`, `Toolbox`, and `AgentProcessor` for tool calls and the verified `maxToolCalls` ceiling.
- **`ai-bundle`** : YAML wiring for the platform, agent and application tools.

## Installation

```bash
composer require symfony/ai-platform symfony/ai-agent symfony/ai-bundle
composer require symfony/ai-open-ai-platform
```

No provider API, credentials or network are needed for the offline proof below. In production, configure the platform credentials through your secret manager.

## Application contract

The support application defines these concepts, not Symfony AI:

```php
final class InvestigationReport
{
    public function __construct(
        /** @var list<array{question: string, answer: string, evidence: list<string>}> */
        public readonly array $findings,
        /** @var list<string> */
        public readonly array $unresolvedQuestions,
        /** @var list<string> */
        public readonly array $consultedDocuments,
        /** @var 'complete'|'exhausted' */
        public readonly string $budgetStatus,
    ) {}
}
```

A support corpus might contain references such as `support/tenant-acme/login-failure.md` and `kb/session-expiry.md`. Give every document a stable reference and keep the corpus lookup behind application tools. Use fresh tool names that describe the support domain, for example `ticket_triage` (classify a ticket and identify its tenant) and `kb_article` (consult one named knowledge-base article). These are application services; they are not replacements for `Agent`, `Toolbox`, or `AgentProcessor`.

## Structured output contract

Define the response contract as application code in `App\Handbook`. The string-backed enum constrains the status values reflected into the model's response schema:

```php
<?php

namespace App\Handbook;

enum BudgetStatus: string
{
    case Complete = 'complete';
    case Exhausted = 'exhausted';
}

final readonly class InvestigationReportDto
{
    public function __construct(
        /** @var list<array{question: string, answer: string, evidence: list<string>}> */
        public array $findings,
        /** @var list<string> */
        public array $unresolvedQuestions,
        /** @var list<string> */
        public array $consultedDocuments,
        public BudgetStatus $budgetStatus,
    ) {}
}
```

Pass the DTO class through `response_format`, as Symfony AI's `MultiAgent` does with `Decision::class` for structured routing:

```php
use App\Handbook\InvestigationReportDto;
use Symfony\AI\Agent\Agent;
use Symfony\AI\Platform\Message\{Message, MessageBag};

/** @var Agent $agent */
$messages = new MessageBag(
    Message::forSystem($systemPrompt),
    Message::ofUser($query),
);
$result = $agent->call($messages, [
    'response_format' => InvestigationReportDto::class,
]);

$report = $result->getContent();
if (!$report instanceof InvestigationReportDto) {
    return $this->degradedReport('The model did not return a valid investigation report.');
}

$this->reportValidator->validate($report); // validates all four typed list/enum fields
```

The production validator checks that `findings`, `unresolvedQuestions`, and `consultedDocuments` retain their documented list shapes and that `budgetStatus` is a `BudgetStatus` case. A wrong content type, missing field, malformed list item, or invalid enum value produces a structured degraded response; it is never silently skipped.

### Critical API rules

- `Agent::call(string|MessageBag|UserMessage $input, array $options = []): ResultInterface` takes the options array as its second argument, not a JSON Schema object.
- `response_format` accepts a DTO class FQN. Symfony AI derives the JSON Schema from the DTO through reflection.
- `Symfony\AI\Platform\Contract\JsonSchema\Factory` is the only framework class under the `JsonSchema` namespace. Do not instantiate it directly in application code; the agent/platform bridge uses it internally.

## Bounded tool loop

`AgentProcessor` takes its tool-call limit in the constructor. The current signature places `maxToolCalls` after `includeSources`:

```php
use Symfony\AI\Agent\Toolbox\AgentProcessor;
use Symfony\AI\Agent\Toolbox\Event\ToolCallsExecuted;
use Symfony\AI\Agent\Toolbox\Toolbox;

$toolbox = new Toolbox([
    new TicketTriage(),
    new KnowledgeBaseArticle(),
], eventDispatcher: $dispatcher);

$processor = new AgentProcessor(
    $toolbox,
    eventDispatcher: $dispatcher,
    includeSources: true,
    maxToolCalls: 8,
);
```

Register this same processor in both the input and output processor lists of the `Agent`. The shared dispatcher lets the application observe the toolbox lifecycle and `ToolCallsExecuted`; source-aware tools can propagate `Source` objects when provenance is useful. `includeSources` does not deduplicate: normalise the final collection by document reference in application code.

The application budget is separate from the framework ceiling. Before each ticket classification or article consultation, debit a step. Debit a document only on its first successful consultation; a repeated reference consumes neither another document allowance nor another step. Append a journal entry only after a permitted step so the journal count cannot exceed the step budget. When a required article is absent, record the question as unresolved with a missing-reference reason instead of inventing content. When either budget reaches zero, stop the loop and construct a report with `budgetStatus: 'exhausted'`.

## Controller and explicit partial results

The investigation service performs the DTO-based call and validation shown above. A controller consumes the validated `InvestigationReportDto` and makes the stop visible to clients:

```php
use App\Handbook\BudgetStatus;
use App\Handbook\InvestigationReportDto;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Response;

public function investigate(string $ticketId): Response
{
    $report = $this->supportInvestigator->investigate($ticketId);

    if (!$report instanceof InvestigationReportDto) {
        return new JsonResponse([
            'error' => 'invalid_model_output',
            'message' => 'The model did not return a valid investigation report.',
        ], Response::HTTP_BAD_GATEWAY);
    }

    $this->reportValidator->validate($report);

    return new JsonResponse([
        'partial' => BudgetStatus::Exhausted === $report->budgetStatus,
        'findings' => $report->findings,
        'unresolvedQuestions' => $report->unresolvedQuestions,
        'consultedDocuments' => array_values(array_unique($report->consultedDocuments)),
        'budgetStatus' => $report->budgetStatus->value,
    ], Response::HTTP_OK);
}
```

`partial: true` is the explicit signal for an exhausted investigation. Render findings and unresolved questions as separate sections; do not present an exhausted report as a complete answer. The validator converts malformed DTO field shapes into the same structured `invalid_model_output` degradation response rather than allowing an invalid report through.

## YAML wiring

`config/packages/ai.yaml` wires the composed framework services and application-owned tools:

```yaml
ai:
    platform:
        openai:
            api_key: '%env(OPENAI_API_KEY)%'

    agent:
        support_investigator:
            platform: 'ai.platform.openai'
            model: 'gpt-4o-mini'
            tools:
                services:
                    - service: 'App\Support\TicketTriage'
                    - service: 'App\Support\KnowledgeBaseArticle'
```

The bundle supplies the agent wiring. Keep the application budget and report mapping in a dedicated service so framework lifecycle concerns do not leak into the HTTP response shape.

## Termination and degradation

- **Complete report:** `findings` is non-empty, `unresolvedQuestions` is empty, and `budgetStatus === BudgetStatus::Complete`.
- **Partial / exhausted report:** unresolved questions are present (or the investigation could not finish) and `budgetStatus === BudgetStatus::Exhausted`; the controller returns HTTP 200 with `partial: true`.
- **Repeated evidence:** deduplicate `consultedDocuments` by stable reference before rendering. Repeated consultations do not receive a second budget debit.
- **Missing documents:** the article tool returns a typed miss; the investigator adds an unresolved question identifying the missing reference and never fabricates evidence.
- **Model failure:** if result content is not an `InvestigationReportDto`, or DTO validation finds missing fields, malformed list entries, or an invalid `BudgetStatus` value, the controller returns a structured `invalid_model_output` error response. It never silently skips the failure or constructs an apparently valid report.

This recipe guarantees bounded retrieval with an explicit stop. It does **not** guarantee exhaustive retrieval: the model may stop after the configured framework or application budget, and an exhausted report must remain visibly partial.

## Offline test

The deterministic proof at `tests/recipes/bounded-investigation-proof.php` exercises both termination paths, repeat-debit protection and the journal cap without a model, embeddings, credentials or network:

```bash
php -d assert.exception=1 tests/recipes/bounded-investigation-proof.php
```

Expected output:

```text
PROOF OK: bounded-investigation (2 scenarios, 2/2 termination paths)
```

The same invariants can be exercised offline because the proof drives the budget, ledger and report contract directly.

## See also

- `platform` skill : model invocation and structured output
- `agent` skill : `Agent`, `Toolbox`, `AgentProcessor`, lifecycle dispatcher and source propagation
- `ai-bundle` skill : YAML wiring and tool registration
- `agent` skill reference: `references/patterns.md` section 6 : shared dispatcher and sources
- `agent-response-with-source-metadata.md` : consuming and deduplicating propagated sources
