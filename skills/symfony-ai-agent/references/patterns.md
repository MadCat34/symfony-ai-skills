# Agent : Patterns

End-to-end recipes, each one a complete, syntactically-valid PHP snippet. Source-of-truth: `src/agent/src/`.

## Contents

- 1. Tool-calling agent (pass a `toolbox` to `Agent`)
- 2. Static, retrieval-only memory (pre-seeded)
- 3. Embedding-based memory (vector store)
- Conversation history vs semantic memory
- 4. Multi-agent routing with `MultiAgent`
- 5. Speech + chat with `SpeechAgent`
- 6. Shared lifecycle dispatcher and source propagation
- 7. Conversation kept across requests (message store)
- 8. Conversation without a store (`getMessages()`)
- 9. Streamed answer saved to the store
- 10. Message store in tests

## 1. Tool-calling agent (pass a `toolbox` to `Agent`)

The `Toolbox` is passed directly to `Agent` via the named `toolbox` constructor argument; `Agent` drives the tool-calling loop itself. Tools are objects with a `#[AsTool]` attribute on the **class**.

```php
use Symfony\AI\Agent\Agent;
use Symfony\AI\Agent\Toolbox\Attribute\AsTool;
use Symfony\AI\Agent\Toolbox\Toolbox;
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;

#[AsTool('get_weather', 'Get the current weather for a city.', method: '__invoke')]
final class WeatherService
{
    public function __invoke(string $city): string
    {
        return sprintf('Weather in %s: sunny, 22C', $city);
    }
}

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);
$toolbox = new Toolbox([new WeatherService()]);

$agent = new Agent(
    $platform,
    'gpt-4o-mini',
    toolbox: $toolbox,
);

$result = $agent->call("What's the weather in Paris?");
echo $result->getContent();
```

Tool with multiple exposed methods (one `#[AsTool]` attribute per method):

```php
use Symfony\AI\Agent\Toolbox\Attribute\AsTool;

#[AsTool('filesystem_read', 'Read the content of a file.', method: 'read')]
#[AsTool('filesystem_write', 'Write content to a file.', method: 'write')]
final class Filesystem
{
    public function read(string $path): string  { return file_get_contents($path); }
    public function write(string $path, string $content): string { file_put_contents($path, $content); return 'ok'; }
}
```

A `write`/`delete`/`move` tool like this lets the model overwrite or remove arbitrary files with no confirmation — this is illustrative, not production-ready. The bundled `Filesystem\Filesystem` bridge (`references/api-reference.md`) exposes the same destructive operations; pair it with `Filesystem\PathValidator` to restrict writable paths, and/or deny the call from a `ToolCallRequested` listener (`ToolCallRequested::deny()`) before enabling it against a real filesystem.

Streaming, or observing the run, via the `Execution` that `call()` returns:

```php
use Symfony\AI\Agent\Execution\Update\Progress;
use Symfony\AI\Platform\Result\Stream\Delta\TextDelta;

// Eager, unchanged — drives the execution and returns the final answer.
$text = $agent->call('What is the weather in Paris?')->getContent();

// Streamed — getContent() yields deltas as they arrive; only TextDelta carries text.
$result = $agent->call('What is the weather in Paris?', ['stream' => true]);
foreach ($result->getContent() as $delta) {
    if ($delta instanceof TextDelta) {
        echo $delta->getText();
    }
}

// Observe every update (model requests, tool calls, deltas) without caring about streaming.
foreach ($agent->call('What is the weather in Paris?') as $update) {
    // $update is an Execution\Update\Progress or the terminal Execution\Update\Result
    if ($update instanceof Progress && Progress::STAGE_TOOL_CALL === $update->getStage()) {
        echo 'Calling '.$update->getPayload()->getName().PHP_EOL; // payload is the ToolCall
    }
}

// Structured output through an agent: the class argument asserts and types the result (0.15).
$report = $agent->call('Weather in Paris?', ['response_format' => WeatherReport::class])
    ->asObject(WeatherReport::class);
```

## 2. Static, retrieval-only memory (pre-seeded)

`StaticMemoryProvider` takes an array of strings and returns them as a single `Memory` on `load()`. It is **immutable and read-only**. There is no `save()` : "Alice says hi then the agent remembers" does not work with this provider; seed the array up front.

```php
use Symfony\AI\Agent\Agent;
use Symfony\AI\Agent\InputProcessor\SystemPromptInputProcessor;
use Symfony\AI\Agent\Memory\MemoryInputProcessor;
use Symfony\AI\Agent\Memory\StaticMemoryProvider;
use Symfony\AI\Agent\Toolbox\Toolbox;
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);
$toolbox = new Toolbox([]);   // no tools in this example

$memoryProvider = new StaticMemoryProvider([
    'The user prefers metric units.',
    'The user lives in Paris.',
]);

$agent = new Agent(
    $platform,
    'gpt-4o-mini',
    [
        new SystemPromptInputProcessor('You answer concisely.'),
        new MemoryInputProcessor([$memoryProvider]),
    ],
    [],
    toolbox: $toolbox,
);

echo $agent->call('What unit system should I use?')->getContent();
```

Tip: order matters. Place `SystemPromptInputProcessor` **before** `MemoryInputProcessor` so memory is appended to (not before) the system context.

## 3. Embedding-based memory (vector store)

`EmbeddingProvider` embeds the latest user message and queries a `StoreInterface`. It needs a `PlatformInterface` (for the embedding call) and a `Model` object (the embedding model identifier, **not** a string).

```php
use Symfony\AI\Agent\Agent;
use Symfony\AI\Agent\Memory\EmbeddingProvider;
use Symfony\AI\Agent\Memory\MemoryInputProcessor;
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;
use Symfony\AI\Platform\Model;
use Symfony\AI\Store\InMemory\Store;

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);
$embeddingModel = new Model('text-embedding-3-small');
$store = new Store();

$memoryProvider = new EmbeddingProvider($platform, $embeddingModel, $store);

$agent = new Agent(
    $platform,
    'gpt-4o-mini',
    [new MemoryInputProcessor([$memoryProvider])],
    [],
);

echo $agent->call('What did we discuss about Paris last week?')->getContent();
```

You populate `$store` separately (typically by adding an output-processor hook in your application code that writes every turn into the store).

## Conversation history vs semantic memory

```text
MessageStore = conversation turns
MemoryProvider = relevant facts injected into context
Vector Store = possible infrastructure for memory or RAG
```

`MemoryInputProcessor` has this processing signature:

```text
public function processInput(Input $input): void
```

It has no `save()` method. It reads each provider with `MemoryProviderInterface::load(Input): array`, then injects the resulting facts into the system prompt rather than adding user/assistant turns. `EmbeddingProvider::load()` therefore returns `Memory[]`, not conversation turns; its underlying `StoreInterface` is a vector store that the application populates separately.

| Concern | `MessageStoreInterface` | `MemoryProviderInterface` | `StoreInterface` (vector) |
| --- | --- | --- | --- |
| What it persists | Full conversation turns (`MessageBag`) | A short list of `Memory` facts | Vector embeddings of documents |
| When written | By `Agent::call()`: input, each tool round, answer | Application code (or seeding step) | Ingestion step (`add()`) |
| Retention | Grows per conversation (no trimming) | App-owned; `StaticMemoryProvider` is immutable | App-owned |
| Isolation | One conversation per `MessageBag` id | App-owned | App-owned |
| Typical cost | Cheap (one serialized bag per conversation) | Cheap (a few strings per call) | Expensive per query (embedding + vector search) |
| Used by | `Agent`'s `messageStore` argument | `MemoryInputProcessor` (system prompt only) | `EmbeddingProvider`, `SimilaritySearch`, `Retriever` |

Conversation history and memory are independent: an agent can keep history without memory, or memory without history.

## 4. Multi-agent routing with `MultiAgent`

`MultiAgent` is itself an `AgentInterface`. It takes an **orchestrator** agent (used to pick), a list of `Handoff` objects (target + keyword triggers), and a **fallback** agent (used when the orchestrator returns no agent name). The orchestrator receives a `Decision` `response_format` constraint.

```php
use Symfony\AI\Agent\Agent;
use Symfony\AI\Agent\MultiAgent\Handoff;
use Symfony\AI\Agent\MultiAgent\MultiAgent;
use Symfony\AI\Agent\Toolbox\Toolbox;
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);

$researchAgent = new Agent(
    $platform, 'gpt-4o-mini',
    [], [],
    'research',
    toolbox: new Toolbox([]),
);
$supportAgent = new Agent(
    $platform, 'gpt-4o-mini',
    [], [],
    'support',
    toolbox: new Toolbox([]),
);
$orchestrator = new Agent(
    $platform, 'gpt-4o-mini',
    [], [],
    'orchestrator',
);

$router = new MultiAgent(
    $orchestrator,
    [
        new Handoff($researchAgent, ['research', 'paper', 'study']),
        new Handoff($supportAgent, ['help', 'error', 'broken']),
    ],
    $orchestrator,                 // fallback agent
);

echo $router->call('I found a bug in the docs')->getContent();
```

The orchestrator MUST return a structured `Decision` for routing. If parsing fails, `MultiAgent` falls back to calling the orchestrator directly. If the orchestrator picks an agent name that is not in the handoff list, the fallback agent is used.

## 5. Speech + chat with `SpeechAgent`

`SpeechAgent` wraps any `AgentInterface`. It transcribes the latest user audio (when an STT platform + model are configured), runs the chat, then optionally synthesises a TTS response. The wrapped agent handles the chat; `SpeechAgent` only handles audio endpoints.

```php
use Symfony\AI\Agent\Agent;
use Symfony\AI\Agent\Speech\SpeechConfiguration;
use Symfony\AI\Agent\SpeechAgent;
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;

$chatPlatform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);
$sttPlatform  = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);
$ttsPlatform  = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);

$chat = new Agent($chatPlatform, 'gpt-4o-mini', [], []);

$speechAgent = new SpeechAgent(
    $chat,
    new SpeechConfiguration(
        ttsModel: 'tts-1',
        ttsOptions: ['voice' => 'alloy'],
        sttModel: 'whisper-1',
    ),
    $sttPlatform,
    $ttsPlatform,
);

$result = $speechAgent->call($audioMessageBag);
echo $result->getContent();   // final text result if TTS disabled, else audio
```

Pass a `MessageBag` containing a `UserMessage` whose content includes `Audio`. `SpeechAgent::transcribe()` replaces the audio-bearing user message with its text transcription before calling the inner agent. If `ttsModel` is `null` (default), no synthesis step runs.

## 6. Shared lifecycle dispatcher and source propagation

Use one dispatcher instance for `Toolbox` events and the `ToolCallsExecuted` event emitted by `Agent`. A source-aware application tool implements `HasSourcesInterface`; `HasSourcesTrait` exposes the public collection setter/getter and a private `addSource()` helper for the tool body.

```php
use Symfony\AI\Agent\Agent;
use Symfony\AI\Agent\Toolbox\Attribute\AsTool;
use Symfony\AI\Agent\Toolbox\Source\HasSourcesInterface;
use Symfony\AI\Agent\Toolbox\Source\HasSourcesTrait;
use Symfony\AI\Agent\Toolbox\Source\Source;
use Symfony\AI\Agent\Toolbox\Source\SourceCollection;
use Symfony\AI\Agent\Toolbox\Toolbox;
use Symfony\AI\Agent\Toolbox\ToolResult;
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;
use Symfony\AI\Platform\Result\ToolCall;
use Symfony\Component\EventDispatcher\EventDispatcher;

#[AsTool('lookup_internal_release_notes', 'Look up an internal release note.', method: '__invoke')]
final class InternalReleaseNotesLookup implements HasSourcesInterface
{
    use HasSourcesTrait;

    public function __invoke(string $version): string
    {
        $this->addSource(new Source(
            'Internal release notes',
            sprintf('releases/%s', $version),
            sprintf('Release %s passed compatibility review.', $version),
        ));

        return sprintf('Release %s passed compatibility review.', $version);
    }
}

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);
$dispatcher = new EventDispatcher();
$lookup = new InternalReleaseNotesLookup();
$toolbox = new Toolbox([$lookup], eventDispatcher: $dispatcher);

$agent = new Agent(
    $platform,
    'gpt-4o-mini',
    toolbox: $toolbox,
    eventDispatcher: $dispatcher,
    includeSources: true,
    maxToolCalls: 8,
);

// Toolbox builds the ToolResult (including the SourceCollection) automatically when it invokes the tool.
```

With `includeSources: true` on `Agent`, it merges each `ToolResult::getSources()` collection and stores the final `SourceCollection` under the result metadata key `sources` after the outermost tool loop completes. For a streamed result, consume the stream completely before treating that metadata as final.

This flow records provenance metadata: source name, reference, and content associated with tool output. It does **not** establish phrase-level attribution, a guaranteed citation relationship, or the truth of either the source or generated answer. Symfony AI is experimental; check `UPGRADE.md` before upgrading.

## 7. Conversation kept across requests (message store)

Since 1.0 this replaces `symfony/ai-chat`'s `Chat`. One store holds every conversation, each under the id of its `MessageBag`; the agent loads it, adds the new messages, and saves after the input, after each tool round and with the answer.

```php
use Doctrine\DBAL\DriverManager;
use Symfony\AI\Agent\Agent;
use Symfony\AI\Agent\Bridge\Doctrine\DoctrineDbalMessageStore;
use Symfony\AI\Agent\InputProcessor\SystemPromptInputProcessor;
use Symfony\AI\Agent\Toolbox\Toolbox;
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;
use Symfony\AI\Platform\Message\MessageBag;
use Symfony\Component\Uid\Uuid;

$connection = DriverManager::getConnection(['driver' => 'pdo_sqlite', 'path' => '/tmp/conversations.sqlite']);
$store = new DoctrineDbalMessageStore('conversations', $connection);
$store->setup(); // once: creates the table when it does not exist

$agent = new Agent(
    OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']),
    'gpt-4o-mini',
    [new SystemPromptInputProcessor('You are a concise travel assistant.')],
    toolbox: new Toolbox([new WeatherService()]),
    messageStore: $store,
);

// Request 1: a new conversation. Keep $id with the user (session, URL, database row).
$id = Uuid::v7();
echo $agent->call(MessageBag::forId($id, 'Weather in Paris?'))->asText();

// Request 2, maybe in another process: same id, only the new message.
echo $agent->call(MessageBag::forId($id, 'And in London?'))->asText(); // sees the Paris turn

// Read or forget a conversation.
$history = $store->load($id);   // MessageBag without the system prompt
$store->delete($id);
```

The id comes from the caller: resolve it from the current user and check ownership before passing it. A `ConflictException` on `call()` means another request saved the same conversation in the meantime; retry the turn.

## 8. Conversation without a store (`getMessages()`)

When the application keeps the history itself (or for a CLI loop), continue from what the execution returns. The agent never changes the bag you pass.

```php
use Symfony\AI\Platform\Message\Message;
use Symfony\AI\Platform\Message\MessageBag;

$messages = new MessageBag(Message::ofUser('What time is it?'));
$messages = $agent->call($messages)->getMessages();       // + tool calls, tool results, answer; same bag id

$messages = $messages->with(Message::ofUser('And in Tokyo?'));
$messages = $agent->call($messages)->getMessages();
```

## 9. Streamed answer saved to the store

With a store, the streamed answer is saved once the stream is drained. Iterate to the end, even if the client is gone (or call `$execution->cancel()` and accept that the answer is not saved).

```php
use Symfony\AI\Platform\Message\MessageBag;
use Symfony\AI\Platform\Result\Stream\Delta\TextDelta;

$execution = $agent->call(MessageBag::forId($id, 'Tell me a story.'), ['stream' => true]);

foreach ($execution->asStream() as $delta) {
    if ($delta instanceof TextDelta) {
        echo $delta->getText();
    }
}
// Only now is the assistant message in the store.
```

## 10. Message store in tests

```php
use Symfony\AI\Agent\Agent;
use Symfony\AI\Agent\MessageStore\InMemoryMessageStore;
use Symfony\AI\Agent\MessageStore\TraceableMessageStore;
use Symfony\AI\Platform\Message\MessageBag;
use Symfony\AI\Platform\Test\MockPlatformFactory;
use Symfony\Component\Clock\MockClock;
use Symfony\Component\Uid\Uuid;

$store = new TraceableMessageStore(new InMemoryMessageStore(), new MockClock());
$agent = new Agent(MockPlatformFactory::createPlatform('Hello Alice'), 'gpt-4o-mini', messageStore: $store);

$id = Uuid::v7();
$agent->call(MessageBag::forId($id, 'I am Alice.'))->getResult();

\assert(2 === \count($store->load($id)));   // the user message and the answer
\assert([] !== $store->getCalls());          // one entry per save()
$store->reset();                             // between tests
```
