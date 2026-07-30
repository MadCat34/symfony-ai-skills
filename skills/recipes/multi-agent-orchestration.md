---
title: Multi-agent orchestration
composes: agent, chat
target-version: PHP 8.2+ / Symfony 6.4 | 7.4 | 8.0
last-verified: 2026-07-28
---

> Symfony AI is **experimental** : APIs may break between releases. Always check `UPGRADE.md` in the [symfony/ai monorepo](https://github.com/symfony/ai) before upgrading.

Route user messages to specialised sub-agents based on intent. A `MultiAgent` orchestrator picks the right sub-agent; `Chat` (or any consumer) wraps the whole thing for stateful persistence.

## Composes

- **`agent`** : `Symfony\AI\Agent\MultiAgent\MultiAgent` (the orchestrator), `MultiAgent\Handoff`, and per-domain `Agent` instances.
- **`chat`** : `Symfony\AI\Chat\Chat` for stateful persistence across HTTP requests.

## Installation

```bash
composer require symfony/ai-platform symfony/ai-agent symfony/ai-chat
composer require symfony/ai-open-ai-platform
composer require symfony/ai-bundle   # optional YAML wiring
```

## Critical API rules

From `src/agent/src/MultiAgent/MultiAgent.php` and `src/agent/src/MultiAgent/Handoff.php`:

```php
// MultiAgent::__construct(
//     AgentInterface $orchestrator,
//     array $handoffs,        // array of Handoff objects, NOT [name => Agent]
//     AgentInterface $fallback,
//     string $name = 'multi-agent',
//     LoggerInterface $logger = new NullLogger(),
// )

// Handoff::__construct(
//     AgentInterface $to,
//     array $when,            // non-empty list of trigger keywords
// )
```

- Handoffs are **objects**, not `[name => Agent]` arrays.
- Each `Handoff` needs at least one `when` keyword (validated in `Handoff::__construct`).
- `MultiAgent` requires at least one handoff (validated in `MultiAgent::__construct`).

## Sub-agent 1: research

```php
namespace App\AI;

use Symfony\AI\Agent\Toolbox\Attribute\AsTool;

#[AsTool(
    name: 'web_search',
    description: 'Search the web for a query. Returns the top results.',
    method: 'search',
)]
final class ResearchService
{
    public function search(string $query): array
    {
        // call your web search API and return results
        return ['results' => []];
    }
}
```

## Sub-agent 2: support

```php
namespace App\AI;

use Symfony\AI\Agent\Toolbox\Attribute\AsTool;

#[AsTool(
    name: 'get_order',
    description: 'Look up an order by ID. Returns status.',
    method: 'getOrder',
)]
final class SupportService
{
    public function getOrder(int $orderId): array
    {
        // return $this->orderRepository->find($orderId)->toArray();
        return ['id' => $orderId, 'status' => 'shipped'];
    }
}
```

## Building the MultiAgent manually

`Toolbox` takes an array (iterable-only), `Agent` takes processor lists, and `MultiAgent` takes an array of `Handoff` objects:

```php
use Symfony\AI\Agent\Agent;
use Symfony\AI\Agent\MultiAgent\Handoff;
use Symfony\AI\Agent\MultiAgent\MultiAgent;
use Symfony\AI\Agent\Toolbox\AgentProcessor;
use Symfony\AI\Agent\Toolbox\Toolbox;
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);

$researchAgent = new Agent(
    $platform,
    'gpt-4o-mini',
    [new AgentProcessor(new Toolbox([new ResearchService()]))],
    [new AgentProcessor(new Toolbox([new ResearchService()]))],
);

$supportAgent = new Agent(
    $platform,
    'gpt-4o-mini',
    [new AgentProcessor(new Toolbox([new SupportService()]))],
    [new AgentProcessor(new Toolbox([new SupportService()]))],
);

// Orchestrator — also an Agent; carries no tools of its own
$orchestrator = new Agent($platform, 'gpt-4o-mini');

// Fallback for unmatched queries
$fallback = $researchAgent;

$dispatcher = new MultiAgent(
    orchestrator: $orchestrator,
    handoffs: [
        new Handoff($researchAgent, ['research', 'search', 'find out']),
        new Handoff($supportAgent,  ['order', 'refund', 'shipping', 'support']),
    ],
    fallback: $fallback,
);

$result = $dispatcher->call('Where is my order #42?');
echo $result->getContent();
```

Internally, `MultiAgent::call()` (`src/agent/src/MultiAgent/MultiAgent.php`):

1. Sends a synthesised prompt to the orchestrator with `response_format => Decision::class` to pick an agent name.
2. Resolves the picked name against the registered `Handoff` list.
3. Calls the matched sub-agent (or `$fallback`) with the original user message.

If the orchestrator returns an empty `agentName` (no match), `MultiAgent` falls back to `$fallback`. If the orchestrator picks an unknown name, it also falls back.

> **Note** : `Symfony\AI\Agent\MultiAgent\Handoff\Decision` is marked `@internal` in the source. The orchestrator uses it under the hood as the `response_format` payload, but its public surface may change between minor releases. Rely on `MultiAgent::call()` and `Handoff::__construct()` instead of instantiating `Decision` directly in application code.

## YAML wiring (with the bundle)

`config/packages/ai.yaml` : verified against `src/ai-bundle/config/options.php` (`multi_agent` block):

```yaml
ai:
    platform:
        openai:
            api_key: '%env(OPENAI_API_KEY)%'

    agent:
        research:
            platform: 'ai.platform.openai'
            model: 'gpt-4o-mini'
            tools:
                services:
                    - service: 'App\AI\ResearchService'

        support:
            platform: 'ai.platform.openai'
            model: 'gpt-4o-mini'
            tools:
                services:
                    - service: 'App\AI\SupportService'

        orchestrator:
            platform: 'ai.platform.openai'
            model: 'gpt-4o-mini'

    multi_agent:
        dispatcher:
            orchestrator: 'orchestrator'
            handoffs:
                research:
                    - 'research'
                    - 'search'
                    - 'find out'
                support:
                    - 'order'
                    - 'refund'
                    - 'shipping'
            fallback: 'research'
```

The bundle compiles each agent (with its `AgentProcessor` wired around the toolbox), then builds `MultiAgent` from the `multi_agent.<name>` block. The `ai.multi_agent.dispatcher` service implements `AgentInterface`.

## Wrapping with Chat (persistence)

```php
namespace App\Controller;

use Symfony\AI\Agent\MultiAgent\MultiAgent;
use Symfony\AI\Chat\Bridge\Doctrine\DoctrineDbalMessageStore;
use Symfony\AI\Chat\Chat;
use Symfony\AI\Platform\Message\Message;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;
use Doctrine\DBAL\Connection;

final class ChatController
{
    public function __construct(
        private readonly MultiAgent $dispatcher,
        private readonly Connection $connection,
    ) {
    }

    #[Route('/chat', methods: ['POST'])]
    public function message(Request $request): Response
    {
        $text = (string) $request->request->get('message');

        $store = new DoctrineDbalMessageStore('chat_messages', $this->connection);
        $chat = new Chat($this->dispatcher, $store);

        $reply = $chat->submit(Message::ofUser($text));

        return new Response($reply->getContent());
    }
}
```

Each request: `Chat::submit()` loads prior context → routes via `MultiAgent` → the picked agent runs with its tools → response persists via `MessageStoreInterface::save()`. See [chat-with-memory-doctrine](chat-with-memory-doctrine.md) for the bundle-driven setup.

## Choosing between handoff and subagent-as-tool

```text
MultiAgent handoff:        the orchestrator picks ONE specialist; control transfers
                           to that specialist for the rest of the call.
Subagent tool:             the coordinator keeps control and invokes a specialist
                           as a __invoke(string $message) tool; other tools still run.
Neither mechanism is parallel fan-out or voting — both are single-path.
```

- Use `MultiAgent` when the request is unambiguously one domain (intent classification is feasible up front).
- Use `Subagent` when the coordinator should remain in charge across many tool calls and the subagent's text + sources are inputs to the next step.
- Both produce a `ResultInterface` from the agent that ran; combining outputs requires an outer aggregator (out of scope for `MultiAgent` and `Subagent`).

The tool entry point is `Subagent::__invoke(string $message): string`. `Subagent` implements `HasSourcesInterface`, so sources from the subagent are forwarded into the parent agent's `ToolResult`.

## Limiting classifier latency

The orchestrator adds one extra LLM call (~300ms) per request. For sub-second responses, route on keywords instead:

```php
namespace App\AI;

use Symfony\AI\Agent\AgentInterface;
use Symfony\AI\Platform\Message\Message;
use Symfony\AI\Platform\Message\MessageBag;
use Symfony\AI\Platform\Result\ResultInterface;

final class FastDispatcher
{
    public function __construct(
        private readonly AgentInterface $research,
        private readonly AgentInterface $support,
    ) {
    }

    public function dispatch(string $userMessage): ResultInterface
    {
        if (preg_match('/\b(order|refund|shipping)\b/i', $userMessage) === 1) {
            return $this->support->call(new MessageBag(Message::ofUser($userMessage)));
        }

        return $this->research->call(new MessageBag(Message::ofUser($userMessage)));
    }
}
```

Trade-off: faster, but lower accuracy on ambiguous queries. Use the LLM classifier only when intent is hard to detect from keywords.

## See also

- `agent` skill : `MultiAgent`, `InputProcessor`, memory providers, tool wiring
- `chat` skill : `Chat`, `MessageStoreInterface`, race conditions
- [chat-with-memory-doctrine](chat-with-memory-doctrine.md) : full Chat + Doctrine recipe
- [tool-calling-agent](tool-calling-agent.md) : per-sub-agent tool wiring
