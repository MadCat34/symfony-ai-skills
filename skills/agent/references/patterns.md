# Agent : Patterns

Five end-to-end recipes, each one a complete, syntactically-valid PHP snippet. Source-of-truth: `src/agent/src/`.

## 1. Tool-calling agent (use `AgentProcessor`)

The toolbox is wrapped in an `AgentProcessor` and registered in both processor lists. Tools are objects with a `#[AsTool]` attribute on the **class**.

```php
use Symfony\AI\Agent\Agent;
use Symfony\AI\Agent\Toolbox\AgentProcessor;
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
$toolProcessor = new AgentProcessor($toolbox);

$agent = new Agent(
    $platform,
    'gpt-4o-mini',
    [$toolProcessor],   // inputProcessors
    [$toolProcessor],   // outputProcessors
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

## 2. Static, retrieval-only memory (pre-seeded)

`StaticMemoryProvider` takes an array of strings and returns them as a single `Memory` on `load()`. It is **immutable and read-only**. There is no `save()` : "Alice says hi then the agent remembers" does not work with this provider; seed the array up front.

```php
use Symfony\AI\Agent\Agent;
use Symfony\AI\Agent\InputProcessor\SystemPromptInputProcessor;
use Symfony\AI\Agent\Memory\MemoryInputProcessor;
use Symfony\AI\Agent\Memory\StaticMemoryProvider;
use Symfony\AI\Agent\Toolbox\AgentProcessor;
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
    [new AgentProcessor($toolbox)],
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

```php
public function processInput(Input $input): void
```

It has no `save()` method. It reads each provider with `MemoryProviderInterface::load(Input): array`, then injects the resulting facts into the system prompt rather than adding user/assistant turns. `EmbeddingProvider::load()` therefore returns `Memory[]`, not conversation turns; its underlying `StoreInterface` is a vector store that the application populates separately.

For retention, indexing, isolation, and cost differences, see [MessageStore vs MemoryProvider vs Vector Store](../../chat/references/patterns.md#messagestore-vs-memoryprovider-vs-vector-store) in the chat skill.

## 4. Multi-agent routing with `MultiAgent`

`MultiAgent` is itself an `AgentInterface`. It takes an **orchestrator** agent (used to pick), a list of `Handoff` objects (target + keyword triggers), and a **fallback** agent (used when the orchestrator returns no agent name). The orchestrator receives a `Decision` `response_format` constraint.

```php
use Symfony\AI\Agent\Agent;
use Symfony\AI\Agent\MultiAgent\Handoff;
use Symfony\AI\Agent\MultiAgent\MultiAgent;
use Symfony\AI\Agent\Toolbox\AgentProcessor;
use Symfony\AI\Agent\Toolbox\Toolbox;
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);

$researchAgent = new Agent(
    $platform, 'gpt-4o-mini',
    [], [new AgentProcessor(new Toolbox([]))],
    'research',
);
$supportAgent = new Agent(
    $platform, 'gpt-4o-mini',
    [], [new AgentProcessor(new Toolbox([]))],
    'support',
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

Use one dispatcher instance for `Toolbox` events and the `ToolCallsExecuted` event emitted by `AgentProcessor`. A source-aware application tool implements `HasSourcesInterface`; `HasSourcesTrait` exposes the public collection setter/getter and a private `addSource()` helper for the tool body.

```php
use Symfony\AI\Agent\Toolbox\AgentProcessor;
use Symfony\AI\Agent\Toolbox\Attribute\AsTool;
use Symfony\AI\Agent\Toolbox\Source\HasSourcesInterface;
use Symfony\AI\Agent\Toolbox\Source\HasSourcesTrait;
use Symfony\AI\Agent\Toolbox\Source\Source;
use Symfony\AI\Agent\Toolbox\Source\SourceCollection;
use Symfony\AI\Agent\Toolbox\Toolbox;
use Symfony\AI\Agent\Toolbox\ToolResult;
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

$dispatcher = new EventDispatcher();
$lookup = new InternalReleaseNotesLookup();
$toolbox = new Toolbox([$lookup], eventDispatcher: $dispatcher);
$toolProcessor = new AgentProcessor(
    $toolbox,
    eventDispatcher: $dispatcher,
    includeSources: true,
    maxToolCalls: 8,
);

// Toolbox builds the ToolResult (including the SourceCollection) automatically when it invokes the tool.
```

Register `$toolProcessor` in both processor lists of the `Agent`. With `includeSources: true`, it merges each `ToolResult::getSources()` collection and stores the final `SourceCollection` under the result metadata key `sources` after the outermost tool loop completes. For a streamed result, consume the stream completely before treating that metadata as final.

This flow records provenance metadata: source name, reference, and content associated with tool output. It does **not** establish phrase-level attribution, a guaranteed citation relationship, or the truth of either the source or generated answer. Symfony AI is experimental; check `UPGRADE.md` before upgrading.
