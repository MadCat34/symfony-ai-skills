# AI Bundle : Patterns

> All snippets below compile against the **real** config tree (`https://github.com/symfony/ai/tree/main/src/ai-bundle/config/options.php`) and the **real** namespaces. Run them inside a Symfony app with `symfony/ai-bundle` installed and `_defaults: { autoconfigure: true }` in `services.yaml`.

## 1. Multi-platform config

Define multiple providers and route agents per use case. Each provider is a top-level child of `ai.platform`.

```yaml
# config/packages/ai.yaml
ai:
    platform:
        openai:
            api_key: '%env(OPENAI_API_KEY)%'
            http_client: 'http_client'
        anthropic:
            api_key: '%env(ANTHROPIC_API_KEY)%'
            cache_retention: 'short'
            http_client: 'http_client'
        ollama:
            endpoint: 'http://127.0.0.1:11434'   # 'endpoint', NOT 'base_url'
            http_client: 'http_client'

    agent:
        chat:
            platform: 'ai.platform.openai'
            model: 'gpt-4o-mini'
            tools:
                enabled: true
        summariser:
            platform: 'ai.platform.anthropic'
            model: 'claude-3-5-haiku-20241022'
        local:
            platform: 'ai.platform.ollama'
            model: 'llama3.2'
            fault_tolerant_toolbox: true
```

Inject as named services. With multiple agents configured, `AgentInterface::class` is **not** aliased : you must use `#[Target('chat')]` or inject by service id:

```php
use Symfony\Component\DependencyInjection\Attribute\Target;
use Symfony\AI\Agent\AgentInterface;

final class AgentRouter
{
    public function __construct(
        #[Target('chat')]      private AgentInterface $chat,
        #[Target('summariser')] private AgentInterface $summariser,
        #[Target('local')]      private AgentInterface $local,
    ) {}
}
```

The single-agent shortcut (`ai.agent.default` and no other agents) still aliases `AgentInterface::class` automatically (`AiBundle::loadExtension()` lines 219-221).

## 2. Dev profiler (no setup)

The `ai.data_collector` is registered by `config/services.php` line 275 and removed only when `kernel.debug` is false (`AiBundle::loadExtension()` lines 381-384). When `kernel.debug` is true, the `DebugCompilerPass` decorates every `ai.platform`, `ai.message_store`, `ai.chat`, `ai.toolbox`, `ai.agent`, `ai.store` with the matching `Traceable*` decorator (`DebugCompilerPass::process()` lines 36-101), and the data collector harvests them in `lateCollect()`.

In dev, open the Web Debug Toolbar, click "AI" : you will see:

- Per-call latency, input, output, options, and metadata for every platform call.
- Tool calls (name, arguments, result) per toolbox.
- Agent calls.
- Chat calls.
- Store / indexer / retriever calls (when configured).

No YAML keys are needed. There is no `ai.profiler.*` key.

## 3. Security-gated tool

Gates a single method (or the whole class) with Symfony Security. The listener always throws on denial:

```php
namespace App\AI;

use Symfony\AI\Agent\Toolbox\Attribute\AsTool;
use Symfony\AI\AiBundle\Security\Attribute\IsGrantedTool;

// #[AsTool] is TARGET_CLASS and IS_REPEATABLE: one attribute per exposed
// method, all of them on the class. #[IsGrantedTool] is TARGET_METHOD and
// stays where the check applies.
#[AsTool(name: 'refund_order', description: 'Refund an order. Requires admin.', method: 'refundOrder')]
#[AsTool(name: 'view_order', description: 'View an order.', method: 'viewOrder')]
final class AdminService
{
    #[IsGrantedTool('ROLE_ADMIN')]
    public function refundOrder(int $orderId, int $amount): string
    {
        return sprintf('Refunded %d for order %d', $amount, $orderId);
    }

    #[IsGrantedTool(
        attribute: "is_granted('ROLE_USER') and subject.ownerId == user.id",
        subject: 'orderId',
    )]
    public function viewOrder(int $orderId): array
    {
        return ['id' => $orderId];
    }
}
```

The listener (`IsGrantedToolAttributeListener::__invoke()`) reads class + method attributes, evaluates the subject, and calls `AuthorizationCheckerInterface::isGranted()`. Denials throw `AccessDeniedException` with the optional custom message and `403` (or `exceptionCode`) default. There is no soft mode.

Requires `symfony/security-core`.

## 4. Custom processor auto-tagging

Either implement the interface (global, priority `0`) or use the attribute (scoped + prioritised):

```php
namespace App\AI;

use Symfony\AI\Agent\Attribute\AsInputProcessor;
use Symfony\AI\Agent\Input;
use Symfony\AI\Agent\InputProcessorInterface;
use Symfony\AI\Platform\Message\Message;

#[AsInputProcessor(agent: 'ai.agent.support', priority: 50)]
final class SupportContextProcessor implements InputProcessorInterface
{
    public function processInput(Input $input): void
    {
        $input->setMessageBag(
            $input->getMessageBag()->with(Message::forSystem('You are handling support tickets.')),
        );
    }
}
```

The `agent` tag binds to a specific service id; leave it `null` to apply to all agents. The compiler pass (`ProcessorCompilerPass::process()` lines 36-62) iterates over `ai.agent` services and assigns processors whose `agent` tag matches the service id or is null. Sorted by priority descending.

## 5. RAG: indexer + retriever

```yaml
ai:
    platform:
        openai:
            api_key: '%env(OPENAI_API_KEY)%'
            http_client: 'http_client'

    vectorizer:
        default:
            platform: 'ai.platform.openai'
            model: 'text-embedding-3-small'

    store:
        pinecone:
            default:
                index_name: 'docs'
                namespace: 'prod'

    indexer:
        docs:
            loader: 'App\AI\Loader\MarkdownDirectoryLoader'   # your own LoaderInterface service
            source: '%kernel.project_dir%/docs'
            transformers: ['App\AI\Transformer\ChunkTextTransformer']
            filters: []
            vectorizer: 'ai.vectorizer.default'
            store: 'ai.store.pinecone.default'

    retriever:
        default:
            vectorizer: 'ai.vectorizer.default'
            store: 'ai.store.pinecone.default'
```

Then run `bin/console ai:store:index docs` to populate the store (the `ai.command.index` service is wired in `config/services.php` lines 312-316).

## 6. Persistent chat

```yaml
ai:
    platform:
        openai: { api_key: '%env(OPENAI_API_KEY)%' }

    agent:
        support:
            platform: 'ai.platform.openai'
            model: 'gpt-4o-mini'

    message_store:
        doctrine:
            dbal:
                support:
                    connection: 'default'
                    table_name: 'ai_support_messages'

    chat:
        support:
            agent: 'ai.agent.support'
            # The Doctrine branch inserts a `dbal` segment into the service id
            # (AiBundle.php:2329). The shorter ai.message_store.doctrine.support
            # is only a named-argument alias, not a service.
            message_store: 'ai.message_store.doctrine.dbal.support'
```

Then inject `ChatInterface $supportChat` (auto-aliased because there is exactly one chat) and call `$supportChat->submit(...)`.

## See also

- `references/config.md`
- `references/processors.md`
- `references/security.md`
- `references/gotchas.md`
