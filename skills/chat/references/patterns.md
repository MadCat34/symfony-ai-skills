# Chat : Patterns

Six common, compile-ready patterns. Every snippet is grounded in the source files under `src/chat/src/`.

## In-memory

The simplest path. Useful for tests, single-process scripts, and quick experiments.

```php
use Symfony\AI\Agent\Agent;
use Symfony\AI\Chat\Chat;
use Symfony\AI\Chat\InMemory\Store;
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;
use Symfony\AI\Platform\Message\Message;
use Symfony\AI\Platform\Message\MessageBag;

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);
$agent = new Agent($platform, 'gpt-4o-mini');
$store = new Store(); // InMemory\Store implements both interfaces

$chat = new Chat($agent, $store);

// Optional: seed with a system prompt.
$chat->initiate(new MessageBag(Message::forSystem('You are concise.')));

$reply = $chat->submit(Message::ofUser('What is 2+2?'));
echo $reply->asText();

$reply = $chat->submit(Message::ofUser('What did I just ask?'));
echo $reply->asText(); // the agent sees the full history
```

In PHPUnit, instantiate the store in `setUp()` and call `reset()` in `tearDown()` to keep tests isolated.

```text
protected function setUp(): void
{
    $this->store = new Store();
    $this->chat = new Chat($this->agent, $this->store);
}

protected function tearDown(): void
{
    $this->store->reset();
}
```

## Doctrine DBAL

The Doctrine bridge uses **DBAL**, not the ORM. There is no `ChatMessage` entity : the bridge creates a flat table via DBAL schema introspection.

```php
use Doctrine\DBAL\DriverManager;
use Symfony\AI\Agent\Agent;
use Symfony\AI\Chat\Bridge\Doctrine\DoctrineDbalMessageStore;
use Symfony\AI\Chat\Chat;
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;
use Symfony\AI\Platform\Message\Message;

$connection = DriverManager::getConnection([
    'driver' => 'pdo_sqlite',
    'path' => '/tmp/chat.sqlite',
]);

$store = new DoctrineDbalMessageStore(
    'chat_messages',     // table name (positional)
    $connection,
);

$store->setup(); // creates the table if missing

$chat = new Chat(new Agent(OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']), 'gpt-4o-mini'), $store);
$chat->submit(Message::ofUser('Hello, persistent world!'));
```

Or run it once via the bundle's console command:

```bash
# The argument is the service id. The Doctrine branch inserts a `dbal`
# segment: ai.message_store.<type>.dbal.<name>.
php bin/console ai:message-store:setup ai.message_store.doctrine.dbal.support
```

The table is created with `(id BIGINT auto-increment, messages TEXT NOT NULL, added_at INTEGER NOT NULL)` and a primary key on `id`. `setup()` is idempotent: it returns early if the table already exists. `drop()` deletes the rows (not the table).

For multiple conversations in the same DB, use a different table name per session : the bridge is single-table by design.

## Chat wrapping an Agent with tools

`Chat` works with any `AgentInterface`. Build the agent with a `Toolbox` and pass it in unchanged.

```php
use Symfony\AI\Agent\Agent;
use Symfony\AI\Agent\Toolbox\Attribute\AsTool;
use Symfony\AI\Agent\Toolbox\Toolbox;
use Symfony\AI\Chat\Chat;
use Symfony\AI\Chat\InMemory\Store;
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;
use Symfony\AI\Platform\Message\Message;

#[AsTool(name: 'get_weather', description: 'Get current weather for a city.', method: 'getWeather')]
class Weather
{
    public function getWeather(string $city): string
    {
        return sprintf('Weather in %s: sunny, 22°C', $city);
    }
}

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);

// Toolbox takes an *iterable* of tools. Pass it to Agent via the named
// `toolbox` argument : Agent drives the tool-calling loop itself.
$agent = new Agent($platform, 'gpt-4o-mini', toolbox: new Toolbox([new Weather()]));

$chat = new Chat($agent, new Store());

$chat->submit(Message::ofUser('Weather in Paris?'));
$chat->submit(Message::ofUser('And in London?')); // sees the Paris reply
```

See the `agent` skill for full `#[AsTool]` patterns and tool-calling caveats.

## Streaming

Use `Chat::stream()` to receive `DeltaInterface` events. The final message is persisted automatically by `ChatStreamListener` once iteration completes.

```php
use Symfony\AI\Chat\Chat;
use Symfony\AI\Chat\InMemory\Store;
use Symfony\AI\Platform\Message\Message;
use Symfony\AI\Platform\Result\Stream\Delta\TextDelta;

$chat = new Chat($agent, new Store());

$buffer = '';
foreach ($chat->stream(Message::ofUser('Tell me a story.')) as $delta) {
    // DeltaInterface is an empty marker interface — it has no accessor at all.
    // Only the concrete delta types expose content; TextDelta is the one that
    // carries text (it is also Stringable).
    if (!$delta instanceof TextDelta) {
        continue;
    }

    $buffer .= $delta->getText();
    echo $delta->getText();   // echo incrementally
}

// At this point the assembled assistant message is persisted.
// A subsequent submit() will see it in the history.
```

**Gotcha**: if you `break` out of the loop early, `ChatStreamListener::onComplete()` never fires and the partial buffer is lost. The next `submit()` will not see a partial assistant message.

## Traceable

Use `TraceableChat` (decorator) and `TraceableMessageStore` to assert that calls were made in tests.

```php
use Symfony\AI\Chat\Chat;
use Symfony\AI\Chat\InMemory\Store;
use Symfony\AI\Chat\TraceableChat;
use Symfony\AI\Chat\TraceableMessageStore;
use Symfony\AI\Platform\Message\Message;

$inner = new Chat($agent, new Store());
$chat = new TraceableChat($inner);

$chat->submit(Message::ofUser('Hello'));
$chat->stream(Message::ofUser('World'));

$calls = $chat->getCalls();
// [['action' => 'submit', 'message' => $userMessage, 'submitted_at' => ...], ['action' => 'stream', ...]]
```

To trace the store:

```php
use Symfony\Component\Clock\MonotonicClock;

$store = new TraceableMessageStore(new Store(), new MonotonicClock());
$chat = new Chat($agent, $store);

$chat->submit(Message::ofUser('Hello'));

$store->getCalls(); // [['bag' => $messageBag, 'saved_at' => ...]]
```

## MessageStore vs MemoryProvider vs Vector Store

```text
MessageStore = conversation turns
MemoryProvider = relevant facts injected into context
Vector Store = possible infrastructure for memory or RAG
```

| Concern | `MessageStoreInterface` | `MemoryProviderInterface` | `StoreInterface` (vector) |
|---|---|---|---|
| What it persists | Full conversation turns (`MessageBag`) | A short list of `Memory` facts | Vector embeddings of documents |
| When written | Each `submit()` / completed `stream()` | Application code (or seeding step) | Ingestion step (`add()`) |
| Retention | Grows monotonically per session (no trim in `Chat` core) | App-owned; `StaticMemoryProvider` is immutable | App-owned |
| Isolation | Single-stream per instance; conversation partitioning happens in the application or in a custom store | App-owned | App-owned |
| Typical cost | Cheap (1 row of JSON per session) | Cheap (a few strings per call) | Expensive per query (embedding + vector search) |
| Used by | `Chat` directly | `MemoryInputProcessor` (system prompt only) | `EmbeddingProvider` and `Retriever` |
| Bridge examples | `InMemory\Store`, `DoctrineDbalMessageStore`, `Cache`, `Session`, `Redis`, `MongoDb`, … | `StaticMemoryProvider`, `EmbeddingProvider` | `InMemory\Store`, `Meilisearch`, `Postgres`, `Pinecone`, … |

A Vector Store can back a `MemoryProvider` through `EmbeddingProvider`, but it is not the same thing as a memory provider. `MemoryInputProcessor::processInput()` injects provider output into the system prompt, not into the user/assistant turn list, so memory content never becomes a "remembered conversation turn" : it is only injected context.

Conversation history and memory are independent dimensions: a chat can have persistence without memory, or memory without persistence.

## See also

- `agent` skill : for the underlying `Agent` and `Toolbox` patterns.
- `ai-bundle` skill : for Symfony DI wiring of `Chat` and bridge services.
- `references/gotchas.md` : for the per-bridge caveats.
