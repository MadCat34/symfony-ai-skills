---
title: Chat with persistence on Doctrine DBAL
composes: chat, agent, ai-bundle, doctrine (DBAL message store bridge)
target-version: PHP 8.2+ / Symfony 6.4 | 7.4 | 8.0
last-verified: 2026-07-28
---

> Symfony AI is **experimental** : APIs may break between releases. Always check `UPGRADE.md` in the [symfony/ai monorepo](https://github.com/symfony/ai) before upgrading.

Stateful chatbot with messages persisted to a SQL database via Doctrine DBAL. The Agent runs tool-calling loops; `Chat` wraps it with persistence across HTTP requests.

## Composes

- **`chat`** : `Symfony\AI\Chat\Chat` (submit / stream / initiate) plus `Symfony\AI\Chat\MessageStoreInterface` and `ManagedStoreInterface`.
- **`agent`** : the underlying `Agent` driving the model and any tool loop.
- **`ai-bundle`** : YAML config; auto-tags services carrying `#[AsTool]`; wires `Chat` services.
- **Doctrine DBAL** : the message store bridge is `symfony/ai-doctrine-message-store` (Doctrine **DBAL**, not ORM). It serialises the `MessageBag` to a single `messages` column.

## What this recipe is : and is not

The Doctrine DBAL message store persists conversation history (the full
`MessageBag` across HTTP requests). It is not semantic memory: it does not
embed, retrieve, or rank facts. To add memory to this chat, register a
`MemoryProviderInterface` on the Agent's `MemoryInputProcessor`.

## Installation

```bash
composer require symfony/ai-platform symfony/ai-agent symfony/ai-chat symfony/ai-bundle
composer require symfony/ai-open-ai-platform
composer require symfony/ai-doctrine-message-store
```

## Configuration

`config/packages/ai.yaml` : keys verified against `src/ai-bundle/config/options.php` and `src/ai-bundle/config/message_store/doctrine.php`:

```yaml
ai:
    platform:
        openai:
            api_key: '%env(OPENAI_API_KEY)%'

    agent:
        chatbot:
            platform: 'ai.platform.openai'
            model: 'gpt-4o-mini'
            # Optional: tools, prompt, memory

    message_store:
        doctrine:
            dbal:
                my_store:
                    connection: 'default'   # Doctrine DBAL connection name
                    table_name: 'chat_messages'

    chat:
        my_chat:
            agent: 'ai.agent.chatbot'
            message_store: 'ai.message_store.doctrine.dbal.my_store'
```

The store service is `ai.message_store.doctrine.dbal.<subname>` : note the two-level nesting (`doctrine.dbal.<name>`). The bundle compiles this into a `DoctrineDbalMessageStore` (see `src/chat/src/Bridge/Doctrine/DoctrineDbalMessageStore.php`).

## Schema

`DoctrineDbalMessageStore::setup()` creates the table on demand:

| Column | Type | Notes |
|---|---|---|
| `id` | `BIGINT` autoincrement | primary key |
| `messages` | `TEXT` NOT NULL | JSON-encoded `MessageBag` |
| `added_at` | `INTEGER` NOT NULL | Unix timestamp from `ClockInterface` |

Run once via the bundle command:

```bash
php bin/console ai:message-store:setup ai.message_store.doctrine.dbal.my_store
```

(Or call `ManagedStoreInterface::setup()` programmatically.) To remove a store through the console, `ai:message-store:drop` requires the `--force` option. The store implementation handles every supported Doctrine DBAL platform, including Oracle's sequence/trigger quirk.

## Service: a tool the agent can call

`#[AsTool]` is `TARGET_CLASS | IS_REPEATABLE` (`src/agent/src/Toolbox/Attribute/AsTool.php`):

```php
namespace App\AI;

use Symfony\AI\Agent\Toolbox\Attribute\AsTool;

#[AsTool(
    name: 'get_weather',
    description: 'Get the current weather for a city. Returns a short string.',
)]
final class WeatherService
{
    public function __invoke(string $city): string
    {
        // call your weather API
        return sprintf('Weather in %s: sunny, 22C', $city);
    }
}
```

Register it with the agent in YAML (the bundle tags it automatically via `#[AsTool]`):

```yaml
ai:
    agent:
        chatbot:
            tools:
                enabled: true   # auto-pick all services tagged `ai.tool`
```

Or be explicit:

```yaml
ai:
    agent:
        chatbot:
            tools:
                services:
                    - service: 'App\AI\WeatherService'
```

## Controller

`Chat::submit()` takes a `UserMessage` (no `chatId` parameter : chat-id scoping is done in your own code or via a `MessageStore` that filters by id):

```php
namespace App\Controller;

use Symfony\AI\Chat\ChatInterface;
use Symfony\AI\Chat\MessageStoreInterface;
use Symfony\AI\Platform\Message\Message;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

final class ChatController
{
    public function __construct(
        private readonly ChatInterface $chat,
        private readonly MessageStoreInterface $store,
    ) {
    }

    #[Route('/chat/message', methods: ['POST'])]
    public function message(Request $request): Response
    {
        $text = (string) $request->request->get('message');

        $reply = $this->chat->submit(Message::ofUser($text));

        return new Response($reply->getContent());
    }

    #[Route('/chat/history', methods: ['GET'])]
    public function history(): JsonResponse
    {
        $bag = $this->store->load();

        return new JsonResponse(array_map(
            static fn ($message) => ['role' => $message->getRole()->value, 'content' => $message->getContent()],
            $bag->getMessages(),
        ));
    }
}
```

Use the injected `MessageStoreInterface` (via `Symfony\AI\Chat\Bridge\Doctrine\DoctrineDbalMessageStore`) for history reads: `$store->load(): MessageBag`.

## Manual wiring (without the bundle)

If you skip `ai-bundle`, build the same chain with PHP:

```php
use Symfony\AI\Agent\Agent;
use Symfony\AI\Agent\Toolbox\AgentProcessor;
use Symfony\AI\Agent\Toolbox\Toolbox;
use Symfony\AI\Chat\Bridge\Doctrine\DoctrineDbalMessageStore;
use Symfony\AI\Chat\Chat;
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;
use Doctrine\DBAL\Connection;

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);
$toolbox = new Toolbox([new WeatherService()]);
$processor = new AgentProcessor($toolbox);

$agent = new Agent($platform, 'gpt-4o-mini', [$processor], [$processor]);

$store = new DoctrineDbalMessageStore('chat_messages', $connection);
$store->setup();   // creates the table

$chat = new Chat($agent, $store);

// $reply = $chat->submit(Message::ofUser('Hi'));
// echo $reply->getContent();
```

## Gotchas

- **`Chat::submit()` returns `AssistantMessage`.** Use `$reply->getContent()` for the text (or `Message::ofAssistant($result)` semantics).
- **No `chatId` argument.** Conversation partitioning must happen at the `MessageStoreInterface` layer; the framework `Chat` class is single-stream.
- **`Chat::initiate(MessageBag)` is the clean way to seed a conversation** : it calls `$store->drop()` then `$store->save($messages)`.
- **Streaming**: `Chat::stream(UserMessage)` returns a `Generator<DeltaInterface>` for SSE consumers.

## See also

- `chat` skill (`Chat`, `MessageStoreInterface`, `ManagedStoreInterface`, full API)
- `agent` skill (tool-calling, memory)
- `ai-bundle` skill (YAML config, processors, profiler)
- [tool-calling-agent](tool-calling-agent.md) : extend this with tools
