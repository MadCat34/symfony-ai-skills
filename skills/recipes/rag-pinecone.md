---
title: RAG with Pinecone
composes: platform, store, agent
target-version: PHP 8.2+ / Symfony 6.4 | 7.4 | 8.0
last-verified: 2026-07-28
---

> Symfony AI is **experimental** : APIs may break between releases. Always check `UPGRADE.md` in the [symfony/ai monorepo](https://github.com/symfony/ai) before upgrading.

Build a Retrieval-Augmented Generation (RAG) pipeline: OpenAI provides embeddings and chat, Pinecone stores vectors, an `Agent` orchestrates the tool-calling loop that retrieves context and answers.

## Composes

- **`platform`** : `Symfony\AI\Platform\Bridge\OpenAi\Factory` for chat and the `text-embedding-3-small` embedding model.
- **`store`** : `Symfony\AI\Store\Bridge\Pinecone\Store` (managed, supports `VectorQuery`) plus `Indexer\DocumentIndexer` to push `TextDocument` instances through `Document\Vectorizer`.
- **`agent`** : `Agent`, `Toolbox`, and `Toolbox\AgentProcessor` to register a similarity-search tool that the model can call.

## Installation

```bash
composer require symfony/ai-platform symfony/ai-store symfony/ai-agent
composer require symfony/ai-open-ai-platform
composer require symfony/ai-pinecone-store
composer require symfony/ai-bundle   # optional, only if you want YAML wiring
```

## Environment

```dotenv
OPENAI_API_KEY=sk-...
PINECONE_API_KEY=pcsk-...
```

The Pinecone client is created by the bridge; only `PINECONE_API_KEY` is required at the application layer.

## Configuration

`config/packages/ai.yaml` : keys verified against `src/ai-bundle/config/options.php` and `config/store/pinecone.php`:

```yaml
ai:
    platform:
        openai:
            api_key: '%env(OPENAI_API_KEY)%'

    store:
        pinecone:
            my_index:
                index_name: 'symfony-ai-rag'
                # Optional: namespace, filter, top_k
                namespace: ''

    vectorizer:
        my_vectorizer:
            platform: 'ai.platform.openai'
            model: 'text-embedding-3-small'

    indexer:
        my_indexer:
            vectorizer: 'ai.vectorizer.my_vectorizer'
            store: 'ai.store.pinecone.my_index'
            # Optional: transformers, filters, loader

    agent:
        rag:
            platform: 'ai.platform.openai'
            model: 'gpt-4o-mini'
            tools:
                services:
                    - service: 'App\AI\SimilaritySearchTool'
```

## Service: the similarity search tool

`#[AsTool]` is `TARGET_CLASS | IS_REPEATABLE` (see `src/agent/src/Toolbox/Attribute/AsTool.php`); put it on the **class**, not on a method. The positional args are `(string $name, string $description, string $method = '__invoke', array $metadata = [])`.

```php
namespace App\AI;

use Symfony\AI\Agent\Toolbox\Attribute\AsTool;
use Symfony\AI\Platform\PlatformInterface;
use Symfony\AI\Platform\Vector\Vector;
use Symfony\AI\Store\Query\VectorQuery;
use Symfony\AI\Store\StoreInterface;

#[AsTool(
    name: 'search_knowledge',
    description: 'Search the knowledge base for documents relevant to a query. Returns the top-K most relevant passages.',
)]
final class SimilaritySearchTool
{
    public function __construct(
        private readonly StoreInterface $store,
        private readonly PlatformInterface $platform,
        private readonly string $embeddingModel = 'text-embedding-3-small',
        private readonly int $topK = 5,
    ) {
    }

    public function __invoke(string $query): string
    {
        /** @var Vector $vector */
        $vector = $this->platform->invoke($this->embeddingModel, $query)->asVectors()[0];

        $documents = $this->store->query(new VectorQuery($vector), ['topK' => $this->topK]);

        $chunks = [];
        foreach ($documents as $document) {
            $chunks[] = sprintf(
                "%s:\n%s",
                $document->getMetadata()['source'] ?? 'unknown',
                $document->getMetadata()['_text'] ?? '',
            );
        }

        return implode("\n\n---\n\n", $chunks);
    }
}
```

The tool lives in a service registered with the bundle (`services.yaml` autoconfiguration is enough; the `ai.tool` tag is auto-attached when the class carries `#[AsTool]`).

## Manual wiring (without the bundle)

If you skip `ai-bundle`, wire the same tool directly with `Toolbox` + `AgentProcessor`. `Toolbox` is **not** variadic : pass an iterable:

```php
use Symfony\AI\Agent\Agent;
use Symfony\AI\Agent\Toolbox\AgentProcessor;
use Symfony\AI\Agent\Toolbox\Toolbox;
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);

$toolbox = new Toolbox([new SimilaritySearchTool($store, $platform)]);
$processor = new AgentProcessor($toolbox);

$agent = new Agent(
    $platform,
    'gpt-4o-mini',
    [$processor],   // inputProcessors
    [$processor],   // outputProcessors
);
```

## CLI command: ingest documents

```php
namespace App\Command;

use Symfony\AI\Platform\PlatformInterface;
use Symfony\AI\Store\Document\TextDocument;
use Symfony\AI\Store\Document\Metadata;
use Symfony\AI\Store\Indexer\DocumentIndexer;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;

#[AsCommand('app:rag:ingest', 'Ingest markdown files into the vector store.')]
final class IngestCommand extends Command
{
    public function __construct(
        private readonly DocumentIndexer $indexer,
        private readonly string $projectDir,
    ) {
        parent::__construct();
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        foreach (glob($this->projectDir.'/*.md') as $file) {
            $text = (string) file_get_contents($file);

            $this->indexer->index(new TextDocument(
                id: $file,
                content: $text,
                metadata: new Metadata(['source' => basename($file)]),
            ));
        }

        return Command::SUCCESS;
    }
}
```

```bash
php bin/console app:rag:ingest
```

The configured `Indexer` (in `ai.yaml`) injects the vectorizer and store automatically; `$indexer->index()` accepts a single `EmbeddableDocumentInterface` or an iterable (see `src/store/src/Indexer/DocumentIndexer.php`).

## CLI command: query

The bundle ships an interactive `ai:agent:call <agent>` command that you can point at the configured `rag` agent:

```bash
php bin/console ai:agent:call rag
```

Or wire a custom one-liner:

```php
namespace App\Command;

use Symfony\AI\Agent\AgentInterface;
use Symfony\AI\Platform\Message\Message;
use Symfony\AI\Platform\Message\MessageBag;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;

#[AsCommand('app:rag:query', 'Ask a question against the knowledge base.')]
final class QueryCommand extends Command
{
    public function __construct(private readonly AgentInterface $agent)
    {
        parent::__construct();
    }

    protected function execute(\Symfony\Component\Console\Input\InputInterface $input, \Symfony\Component\Console\Output\OutputInterface $output): int
    {
        $query = (string) $input->getArgument('query');

        $result = $this->agent->call(new MessageBag(Message::ofUser($query)));
        $output->writeln($result->getContent());

        return Command::SUCCESS;
    }

    protected function configure(): void
    {
        $this->addArgument('query', \Symfony\Component\Console\Input\InputArgument::REQUIRED);
    }
}
```

```bash
php bin/console app:rag:query "What is Symfony's HTTP client?"
```

The model invokes `search_knowledge` → the tool embeds the question → queries Pinecone → returns the top-5 passages → the model composes the answer.

## Variants

- **Postgres pgvector** instead of Pinecone: see [rag-postgres-pgvector](rag-postgres-pgvector.md)
- **Hybrid retrieval + rerank**: query with `HybridQuery` and wire a `Reranker` (Cohere / Voyage) into a `RerankerListener` listening to `PostQueryEvent`
- **Streaming responses**: pass `'stream' => true` to `Agent::call()` and iterate `$result->asStream()`

## See also

- `platform` skill (embeddings, failover, structured output)
- `store` skill (24 vector store bridges, transformers)
- `agent` skill (tool-calling, multi-agent, memory)
- `ai-bundle` skill (YAML config, security-gated tools, profiler)
