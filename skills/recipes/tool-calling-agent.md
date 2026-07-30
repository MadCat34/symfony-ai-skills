---
title: Tool-calling agent
composes: agent, ai-bundle
target-version: PHP 8.2+ / Symfony 6.4 | 7.4 | 8.0
last-verified: 2026-07-28
---

> Symfony AI is **experimental** : APIs may break between releases. Always check `UPGRADE.md` in the [symfony/ai monorepo](https://github.com/symfony/ai) before upgrading.

Build an AI agent that calls three tools (weather + calculator + admin), with one admin method gated by Symfony Security via `#[IsGrantedTool]`, and tests using `MockHttpClient`.

## Composes

- **`agent`** : `Symfony\AI\Agent\Agent`, `Symfony\AI\Agent\Toolbox\Toolbox`, `Toolbox\AgentProcessor`, `Toolbox\Attribute\AsTool`.
- **`ai-bundle`** : YAML config, auto-tag of `#[AsTool]` services, `#[IsGrantedTool]` security listener (`Symfony\AI\AiBundle\Security\Attribute\IsGrantedTool`).

## Installation

```bash
composer require symfony/ai-platform symfony/ai-agent symfony/ai-bundle
composer require symfony/ai-open-ai-platform
composer require symfony/security-bundle   # for #[IsGrantedTool] to do anything
```

## Critical API rules

These come straight from `src/agent/src/`:

- `#[AsTool]` is `TARGET_CLASS | IS_REPEATABLE` (`src/agent/src/Toolbox/Attribute/AsTool.php`). Put it on the **class**. For multiple methods, repeat the attribute on the same class.
- `Toolbox::__construct(iterable $tools, ...)` is **not** variadic. Always pass an array: `new Toolbox([new WeatherService()])`.
- `Agent::__construct(PlatformInterface $platform, string $model, iterable $inputProcessors = [], iterable $outputProcessors = [], string $name = 'agent')` has **no** `$toolboxes` parameter. Tools enter the pipeline via an `AgentProcessor` registered in both processor lists.

## Configuration

`config/packages/ai.yaml` : keys verified against `src/ai-bundle/config/options.php`:

```yaml
ai:
    platform:
        openai:
            api_key: '%env(OPENAI_API_KEY)%'

    agent:
        chatbot:
            platform: 'ai.platform.openai'
            model: 'gpt-4o-mini'
            tools:
                enabled: true   # auto-pick all services tagged `ai.tool`
                # Or be explicit:
                # services:
                #     - service: 'App\AI\Tools'   # repeated #[AsTool] on one class
            fault_tolerant_toolbox: true
            max_tool_calls: 50
```

When `fault_tolerant_toolbox: true` (default), the bundle wraps the `Toolbox` in a `FaultTolerantToolbox` so transient tool failures do not abort the agent loop.

## Three tools on a single class

`#[AsTool]` is class-targeted and `IS_REPEATABLE`, so you can declare all three tools on a single class : each `#[AsTool]` points at a different method. The positional args are `(string $name, string $description, string $method = '__invoke', array $metadata = [])`:

```php
namespace App\AI;

use Symfony\AI\Agent\Toolbox\Attribute\AsTool;
use Symfony\AI\AiBundle\Security\Attribute\IsGrantedTool;

#[AsTool(name: 'get_weather',  description: 'Get the current weather for a city. Returns a short string.', method: 'getWeather')]
#[AsTool(name: 'calculate',    description: 'Evaluate a basic arithmetic expression. Returns the result as a number.', method: 'calculate')]
#[AsTool(name: 'delete_user',  description: 'Delete a user by ID. Requires admin role.', method: 'deleteUser')]
final class Tools
{
    public function getWeather(string $city): string
    {
        // call your weather API
        return sprintf('Weather in %s: sunny, 22C', $city);
    }

    public function calculate(string $expression): float
    {
        // Use a safe expression parser
        return (float) (new \Symfony\Component\ExpressionLanguage\ExpressionLanguage())
            ->evaluate($expression, []);
    }

    #[IsGrantedTool(attribute: 'ROLE_ADMIN', message: 'Only admins can delete users.')]
    public function deleteUser(int $userId): string
    {
        // $this->userRepository->delete($userId);
        return sprintf('User %d deleted.', $userId);
    }
}
```

The `#[IsGrantedTool]` attribute lives at `Symfony\AI\AiBundle\Security\Attribute\IsGrantedTool`. The bundle's `IsGrantedToolAttributeListener` (subscribed to `ToolCallArgumentsResolved`) calls Symfony's `AuthorizationCheckerInterface` before the tool executes and **always throws** `AccessDeniedException` on denial : there is no `throwOnDenied` flag. The listener is automatically wired by the bundle; you do not need to register it.

## Manual wiring (without the bundle)

`Toolbox` is iterable-only : wrap your tools in an array:

```php
use Symfony\AI\Agent\Agent;
use Symfony\AI\Agent\Toolbox\AgentProcessor;
use Symfony\AI\Agent\Toolbox\Toolbox;
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);

$toolbox = new Toolbox([new Tools()]);   // ONE service, THREE methods declared via repeated #[AsTool]
$processor = new AgentProcessor($toolbox);

$agent = new Agent(
    $platform,
    'gpt-4o-mini',
    [$processor],   // inputProcessors
    [$processor],   // outputProcessors
);

$result = $agent->call("What's the weather in Paris?");
echo $result->getContent();
```

Without the bundle, the `#[IsGrantedTool]` listener is **not** wired : the `deleteUser` method will be invokable by anyone. Wire `IsGrantedToolAttributeListener` manually if you want the gate.

## Usage

```php
namespace App\Controller;

use Symfony\AI\Agent\AgentInterface;
use Symfony\AI\Platform\Message\Message;
use Symfony\AI\Platform\Message\MessageBag;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

final class ChatController
{
    public function __construct(private readonly AgentInterface $chatbot)
    {
    }

    #[Route('/chat', methods: ['POST'])]
    public function message(Request $request): Response
    {
        $text = (string) $request->request->get('message');

        $result = $this->chatbot->call(new MessageBag(Message::ofUser($text)));

        return new Response((string) $result->getContent());
    }
}
```

The agent picks the right tool based on the user's message:

- "What's the weather in Paris?" → calls `get_weather`
- "What's 42 * 17?" → calls `calculate`
- "Delete user 42" → calls `delete_user` (only if `ROLE_ADMIN`; otherwise `AccessDeniedException` propagates from the listener)

## Testing with MockHttpClient

Stub the LLM HTTP responses. `Toolbox` takes an array, and `Agent` takes processor lists:

```php
namespace App\Tests;

use PHPUnit\Framework\TestCase;
use Symfony\AI\Agent\Agent;
use Symfony\AI\Agent\Toolbox\AgentProcessor;
use Symfony\AI\Agent\Toolbox\Toolbox;
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;
use Symfony\AI\Platform\Message\Message;
use Symfony\AI\Platform\Message\MessageBag;
use Symfony\Component\HttpClient\MockHttpClient;
use Symfony\Component\HttpClient\Response\MockResponse;

final class ToolsTest extends TestCase
{
    public function testWeatherToolIsCalled(): void
    {
        $mock = new MockHttpClient([
            new MockResponse(json_encode([
                'choices' => [['message' => ['role' => 'assistant', 'content' => 'Weather is sunny, 22C.']]],
                'usage'   => ['prompt_tokens' => 10, 'completion_tokens' => 8, 'total_tokens' => 18],
            ], \JSON_THROW_ON_ERROR)),
        ]);

        $platform = OpenAiFactory::createPlatform('fake-key', httpClient: $mock);
        $agent = new Agent(
            $platform,
            'gpt-4o-mini',
            [new AgentProcessor(new Toolbox([new \App\AI\Tools()]))],
            [new AgentProcessor(new Toolbox([new \App\AI\Tools()]))],
        );

        $result = $agent->call(new MessageBag(Message::ofUser('Weather in Paris?')));
        $this->assertSame('Weather is sunny, 22C.', $result->getContent());
    }
}
```

(The same `AgentProcessor` instance must be registered in both processor lists : the input side publishes tool definitions, the output side runs the loop.)

## See also

- `agent` skill : `Toolbox`, `AgentProcessor`, `FaultTolerantToolbox`, memory providers
- `ai-bundle` skill : `#[IsGrantedTool]`, processors, profiler
- `platform` skill : raw tool calling from `Platform::invoke()`
- [chat-with-memory-doctrine](chat-with-memory-doctrine.md) : wrap the same agent in a persistent `Chat`
