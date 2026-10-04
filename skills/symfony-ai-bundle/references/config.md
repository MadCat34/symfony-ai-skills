# YAML Config Reference

> **Source of truth**: `https://github.com/symfony/ai/tree/main/src/ai-bundle/config/options.php` is the canonical config tree. Per-platform and per-store schemas live in `config/platform/<provider>.php` and `config/store/<provider>.php`. Service wiring lives in `config/services.php`. This document only describes what actually exists in source.

## Contents

- Root tree (from `config/options.php`)
- `ai.platform`
  - Singleton providers (one platform per YAML key)
  - Named providers (multiple instances under one key)
- `ai.model`
- `ai.agent`
- `ai.multi_agent`
- `ai.store`
- `ai.vectorizer`
- `ai.retriever`
- `ai.indexer`
- `ai.chat`
- `ai.message_store`
- Aliases auto-created by the bundle
- Removed when optional packages are missing

## Root tree (from `config/options.php`)

```text
ai:
    platform:           # LLM providers
    model:              # extra models per platform
    agent:              # named agents
    multi_agent:        # orchestrator + handoffs
    store:              # vector stores, grouped by provider
    vectorizer:         # wraps a platform + model
    retriever:          # (vectorizer, store)
    indexer:            # (loader, source, transformers, filters, vectorizer, store)
    chat:               # (agent, message_store)
    message_store:      # persistent chat backends
```

There is **no** `ai.profiler.*` key. Profiling is gated by `kernel.debug`.

## `ai.platform`

Defined in `config/platform/*.php`. Each provider key is a top-level child of `ai.platform`. The 37 files under `config/platform/` are the exhaustive list. Singleton providers (one platform per YAML key): `albert`, `amazeeai`, `anthropic`, `cartesia`, `cerebras`, `cohere`, `decart`, `deepgram`, `deepseek`, `dockermodelrunner`, `edenai`, `elevenlabs`, `fireworks`, `gemini`, `higgsfield`, `huggingface`, `lmstudio`, `minimax`, `mistral`, `ollama`, `openai`, `openrouter`, `ovh`, `perplexity`, `scaleway`, `together`, `transformersphp`, `typesafe`, `venice`, `vertexai`, `voyage`. Named instances: `azure`, `bedrock`, `cache`, `failover`, `generic`, `openresponses`.

### Singleton providers (one platform per YAML key)

```yaml
ai:
    platform:
        openai:
            api_key: '%env(OPENAI_API_KEY)%'
            region: null   # null | 'EU' | 'US'  (config/platform/openai.php)
            http_client: 'http_client'   # service id

        anthropic:
            api_key: '%env(ANTHROPIC_API_KEY)%'
            version: null
            http_client: 'http_client'
            cache_retention: 'short'   # 'none' | 'short' | 'long'  (config/platform/anthropic.php)

        ollama:
            endpoint: 'http://127.0.0.1:11434'   # NOT 'base_url'
            api_key: null                         # optional (Ollama Cloud)
            http_client: 'http_client'

        gemini:
            api_key: '%env(GEMINI_API_KEY)%'
            http_client: 'http_client'

        vertexai:
            location: null
            project_id: null
            api_key: '%env(VERTEX_AI_API_KEY)%'
            http_client: 'http_client'
            # providing location + project_id activates ADC (google/auth required)

        openrouter:
            api_key: '%env(OPENROUTER_API_KEY)%'
            http_client: 'http_client'

        voyage:
            api_key: '%env(VOYAGE_API_KEY)%'
            http_client: 'http_client'

        # since 0.14 — each takes api_key + http_client; extra keys noted
        edenai:     { api_key: '%env(EDENAI_API_KEY)%' }
        fireworks:  { api_key: '%env(FIREWORKS_API_KEY)%' }
        together:   { api_key: '%env(TOGETHER_API_KEY)%', endpoint: null }   # null => https://api.together.xyz
        typesafe:   { api_key: '%env(TYPESAFE_API_KEY)%' }
        venice:     { api_key: '%env(VENICE_API_KEY)%', endpoint: 'https://api.venice.ai/api/v1/' }
        higgsfield: { api_key: '%env(HIGGSFIELD_API_KEY)%', api_secret: '%env(HIGGSFIELD_API_SECRET)%', base_url: null, model_catalog: null }
```

`config/platform/openai.php` exposes `api_key`, `region`, `http_client` only : there is **no `base_url`**. Same goes for `anthropic` (`api_key`, `version`, `http_client`, `cache_retention`) and most hosted providers.

### Named providers (multiple instances under one key)

```yaml
ai:
    platform:
        azure:
            my_deployment:
                api_key: '%env(AZURE_OPENAI_KEY)%'
                base_url: 'https://my-resource.openai.azure.com'
                deployment: 'gpt-4o'
                api_version: '2024-08-01-preview'   # optional
                http_client: 'http_client'

        cache:
            openai:
                platform: 'ai.platform.openai'   # service id of inner platform
                service: 'cache.app'
                cache_key: null   # default = platform name
                ttl: null

        failover:
            primary:
                platforms:   # service ids to wrap in failover
                    - 'ai.platform.openai'
                    - 'ai.platform.anthropic'
                rate_limiter: 'limiter.openai'   # optional service id (stringNode, cannotBeEmpty — not isRequired)

        generic:
            local_llm:
                base_url: 'http://localhost:1234/v1'
                api_key: null
                http_client: 'http_client'
                model_catalog: null   # optional service id
                supports_completions: true
                supports_embeddings: true
                completions_path: '/v1/chat/completions'
                embeddings_path: '/v1/embeddings'

        openresponses:
            local:
                base_url: 'http://localhost:9000'
                api_key: null
                http_client: 'http_client'
                model_catalog: null
                responses_path: '/v1/responses'   # this IS the default, not null

        bedrock:
            prod:
                api: invoke_model              # since 0.14: invoke_model (default, AWS SDK) | completions | responses | messages
                bedrock_runtime_client: null   # service id (null => SDK default); only with api: invoke_model
                model_catalog: null           # service id or default
            mantle:
                api: messages                  # a Bedrock Mantle route (Anthropic Messages here)
                api_key: '%env(BEDROCK_API_KEY)%'   # omit to sign with AWS SigV4 (credential_provider)
                region: 'us-west-2'            # default; Mantle base URL is derived from it
                cache_retention: 'short'       # only with api: messages
                # also: credential_provider, http_client, path, workspace (messages only)
```

Notes:

- The `cache` provider requires `symfony/ai-cache-platform`. The `failover` provider requires `symfony/ai-failover-platform`. Missing packages throw a `RuntimeException` with `composer require …` hint (`AiBundle::processPlatformConfig()`).
- VertexAI becomes project-scoped when both `location` and `project_id` are set, requiring `google/auth`.
- Bedrock: the Mantle options (`api_key`, `region`, `credential_provider`, `http_client`, `path`) and `bedrock_runtime_client` belong to different engines; mixing them fails at compile time, as does `cache_retention`/`workspace` outside `api: messages`.
- Asynchronous jobs (since 0.14): the bundle registers `ai.platform.job_runner` (autowired as `Symfony\AI\Platform\Job\JobRunner`, using the application clock) and, for every platform that runs async jobs (`openai` batches, `minimax`, `venice`, `higgsfield`, `edenai`), an `ai.platform.job_client.<name>` service tagged `ai.platform.job_client` and autowirable by argument name (`JobClientInterface $openai`, or `#[Target('openai')]`). Replicate has no bundle configuration: build its job client with `Replicate\Factory::createJobClient()`. Store the `JobHandle` in a Messenger message and resolve it from a worker with both services.

## `ai.model`

Adds custom `Model` subclasses (with capabilities) to a platform's `ModelCatalog` (see `AiBundle::processModelConfig()`). Structure: `<platform_name>: { <model_name>: { class, capabilities } }`. `class` must extend `Symfony\AI\Platform\Model`; `capabilities` is a non-empty list of `Symfony\AI\Platform\Capability` enum values (the `ai.model` node of `config/options.php`).

```yaml
ai:
    model:
        openai:
            'my-finetune-x':
                class: 'App\AI\Model\MyFinetuneX'
                capabilities: ['text-generation', 'tool-calling']
```

## `ai.agent`

Defined by the `ai.agent` node of `config/options.php`. The agent key is the agent's name; each agent has:

```yaml
ai:
    agent:
        default:
            platform: 'ai.platform.openai'   # default: PlatformInterface::class alias
            model: 'gpt-4o-mini'             # string OR { name: 'gpt-4o', options: { temperature: 0.7 } }
            memory: 'You are helpful.'        # string (StaticMemoryProvider) OR { service: 'App\Memory\Provider' }
            prompt: 'You are a helpful assistant.'   # string OR { text | file, include_tools, enable_translation, translation_domain }
            tools:                          # see the bare-list form just below; both are equally current
                enabled: true               # OR pass an explicit list:
                # services:
                #     - 'App\AI\WeatherService'   # bare string = { service: 'App\AI\WeatherService' }
                #     - service: 'App\AI\OtherService'
                #     - agent: 'default'           # wrap another agent as a sub-tool
                #       name: 'delegate'
                #       description: 'Delegate to the default agent.'
                #     - mcp_server: 'docs.readme'  # since 0.14: tools of a remote MCP server, "<client>.<server>" from mcp.clients
                #       prefix: 'readme_'          # optional, only with mcp_server; default "<server>_"
                # execution_strategy: fiber      # since 0.14: sequential (default) | fiber | custom ToolExecutorInterface service id
            exclude_tool_messages: false
            include_sources: false
            max_tool_calls: 50               # int or null
            fault_tolerant_toolbox: true     # boolean, default true
            speech:
                enabled: true
                text_to_speech_platform: 'ai.platform.elevenlabs'
                speech_to_text_platform: 'ai.platform.openai'
                tts_model: null
                tts_options: []
                stt_model: null
                stt_options: []
```

Notes:

- `prompt:` accepts a **string** (normalized to `{ text: '…' }`) **or** an array with `text`/`file` (mutually exclusive) plus `include_tools` (requires `tools.enabled: true`), `enable_translation` (requires `symfony/translation`), and `translation_domain`. See the `ai.agent.<name>.prompt` node of `config/options.php`.
- `model:` accepts a string (with optional query string of options, e.g. `gpt-4o?temperature=0.7`) or `{ name, options }`. Both forms cannot be combined.
- `tools:` has four acceptable YAML shapes: `true`, `false`, a bare list, or `{ enabled, services }` (see the `ai.agent.<name>.tools` node of `config/options.php`) : `$services = $v['services'] ?? $v` normalizes both list forms identically. The bare list is **not legacy** — it's the form the official `demo/` application uses for every one of its agents (`config/packages/ai.yaml`), e.g. `tools: ['App\AI\WeatherService', { service: clock, name: clock, description: '...', method: now }]`. Reach for `{ enabled, services }` only when you also need `enabled: true` to auto-pick every `ai.tool`-tagged service instead of listing them explicitly.
- Each `tools.services` entry needs **exactly one** of `service`, `agent` or `mcp_server`. `mcp_server` (since 0.14) requires `symfony/ai-mcp-tool` and `symfony/mcp-bundle`, and references a connection declared under `mcp.clients.<client>.servers.<server>` (see the `mcp-bundle` skill); the bundle reuses that connection instead of opening a second one. `prefix` is only accepted with `mcp_server`.
- `tools.execution_strategy` (since 0.14): `fiber` swaps the default `SequentialToolExecutor` for `FiberToolExecutor`, which only helps when tools cooperate via `SuspendableTrait` (see the `symfony-ai-agent` skill).
- `speech:` requires at least one of `text_to_speech_platform`/`speech_to_text_platform` and one of `tts_model`/`stt_model`.
- **`system_prompt` is NOT a valid key** : use `prompt:`.
- **`input_processors` / `output_processors` are NOT valid keys** : processors are auto-tagged via attributes/interfaces (see `references/processors.md`).
- **`max_tool_calls` IS a valid key** (the `ai.agent.<name>.max_tool_calls` node of `config/options.php`): int or `null` to disable, default `50`. `circuit_breaker_threshold` and similar names are **not** valid — the only other fault-tolerance key is `fault_tolerant_toolbox: bool`.

## `ai.multi_agent`

The `ai.multi_agent` node of `config/options.php`. Requires `ai.agent.*` to exist with the same names referenced in `orchestrator`, `fallback`, and `handoffs`.

```yaml
ai:
    multi_agent:
        router:
            orchestrator: 'default'      # must match an ai.agent.<name>
            fallback: 'default'           # must match an ai.agent.<name>
            handoffs:
                'specialist': ['specialist keyword', 'fallback phrase']
```

Validation (the root-level `validate()` rules at the end of `config/options.php`): duplicate agent/multi_agent names throw `InvalidArgumentException`. References to non-existent agents throw.

## `ai.store`

Defined in `config/store/*.php`. Each provider is a top-level child of `ai.store`; under it, named instances. Per-store schemas vary : the example below is `pinecone` (`config/store/pinecone.php`):

```yaml
ai:
    store:
        pinecone:
            default:
                client: 'Pinecone\Client'   # default: Probots\Pinecone\Client
                index_name: 'docs'           # required
                namespace: null
                filter: []
                top_k: null

        memory:
            default:
                strategy: 'cosine'   # DistanceStrategy

        cache:
            default:
                service: 'cache.app'
                cache_key: null
                strategy: 'cosine'

        qdrant:
            default:
                collection_name: null
                endpoint: null
                api_key: null
                http_client: 'http_client'
                dimensions: 1536
                distance: 'Cosine'
                async: false
```

`postgres` (`config/store/postgres.php`) is worth its own example : it's the store the official `demo/` application actually runs in production-shaped config.

```yaml
ai:
    store:
        postgres:
            symfony_blog:
                dbal_connection: 'doctrine.dbal.default_connection'   # OR dsn: '...' — exactly one of the two
                table_name: 'symfony_blog'
                vector_field: 'embedding'      # default
                distance: 'cosine'             # cosine | inner_product | l1 | l2 ; default l2
                lang: 'english'                # default; used for the tsvector language config
                setup_options:                 # only read by the `ai:store:setup` command
                    vector_type: 'vector'       # default
                    vector_size: 1536           # default
                    index_method: 'ivfflat'     # default
                    index_opclass: 'vector_cosine_ops'   # default
```

`dsn` and `dbal_connection` are mutually exclusive and one of them is required (validated at compile time). `username`/`password` are only meaningful with `dsn`.

Scoped-client stores (since 0.14): `clickhouse`, `elasticsearch`, `manticoresearch`, `milvus`, `neo4j`, `opensearch` and `supabase` are built through their bridge `StoreFactory`. Configure **either** the connection (`endpoint`; `dsn` for ClickHouse; `url` for Supabase) with its credentials, **or** an `http_client` service already scoped to the instance (e.g. from `framework.http_client.scoped_clients`). Credentials (`api_key`, `username`/`password`) require the endpoint; when both are set, the custom client is scoped to the endpoint.

```yaml
ai:
    store:
        elasticsearch:
            movies:
                http_client: 'elasticsearch.client'   # scoped client, no endpoint needed
                index_name: 'movies'
        milvus:
            docs:
                endpoint: 'http://localhost:19530'
                api_key: '%env(MILVUS_API_KEY)%'
                database: 'default'
                collection: 'docs'
```

Other supported providers (schemas in `config/store/<provider>.php`, not individually detailed here): `azuresearch`, `chromadb`, `clickhouse`, `cloudflare`, `elasticsearch`, `manticoresearch`, `mariadb`, `meilisearch`, `milvus`, `mongodb`, `neo4j`, `opensearch`, `redis`, `s3vectors`, `sqlite`, `supabase`, `surrealdb`, `typesense`, `vektor`, `weaviate`. Read the corresponding `config/store/<provider>.php` file directly when configuring one of these — the shape follows the same pattern (provider name as parent key, named instances under it) but options differ per backend.

**There is no `bridge:` sub-key.** The provider name (`pinecone`, `mongodb`, `postgres`, …) is the parent key in YAML. There is no `embedding_model:` or `transformers:` sub-key : embedding is configured via `ai.vectorizer.<name>` and used by indexer/retriever.

## `ai.vectorizer`

The `ai.vectorizer` node of `config/options.php`. Wraps `Symfony\AI\Store\Document\Vectorizer` over a platform and a model.

```yaml
ai:
    vectorizer:
        default:
            platform: 'ai.platform.openai'   # default: PlatformInterface::class
            model: 'text-embedding-3-small'   # same string|array schema as agent.model
```

## `ai.retriever`

The `ai.retriever` node of `config/options.php`.

```yaml
ai:
    retriever:
        default:
            vectorizer: 'ai.vectorizer.default'   # default: VectorizerInterface::class
            store: 'ai.store.pinecone.default'    # default: StoreInterface::class
```

## `ai.indexer`

The `ai.indexer` node of `config/options.php`. Builds either a `DocumentIndexer`, a `SourceIndexer`, or a `ConfiguredSourceIndexer` depending on which of `loader` / `source` are present (`AiBundle::processIndexerConfig()`).

```yaml
ai:
    indexer:
        docs:
            loader: null                  # service id of a LoaderInterface
            source: null                  # scalar source (path/URL) or list
            transformers: []              # list of transformer service ids
            filters: []                   # list of filter service ids
            vectorizer: 'ai.vectorizer.default'
            store: 'ai.store.pinecone.default'
```

If `loader` is null, the indexer is a `DocumentIndexer` (you pass documents at runtime). If `loader` is set and `source` is null, it is a `SourceIndexer` (you pass sources at runtime). If both are set, the bundle wires a `ConfiguredSourceIndexer` around `SourceIndexer`.

There is **no `delay_ms` / `batch_size` / `chunk_size`** : indexing semantics are owned by the store/loader packages.

## `ai.chat`

The `ai.chat` node of `config/options.php`. Persisted chat session wrapping one agent and one message store.

```yaml
ai:
    chat:
        support:
            agent: 'ai.agent.default'                   # required, non-empty
            message_store: 'ai.message_store.memory.support'   # required, non-empty
```

There is **no `chat_store.doctrine.entity` or `chat_store.doctrine.chat_id_field`** : chat storage is configured under `ai.message_store` (see next section), not as a sub-key of `ai.chat`.

## `ai.message_store`

Defined in `config/message_store/*.php`. Each provider is a top-level child of `ai.message_store`; under it, named instances.

`doctrine` (`config/message_store/doctrine.php`) is the DBAL-backed provider:

```yaml
ai:
    message_store:
        doctrine:
            dbal:
                support:
                    connection: 'default'   # Doctrine DBAL connection name (=> doctrine.dbal.default_connection)
                    table_name: null         # default = instance name
        cache:
            support:
                service: 'cache.app'
                key: null                   # default = instance name
                ttl: null
        memory:
            support:
                identifier: 'session_id'
        redis:
            support:
                # Exactly one of `client` / `connection_parameters` — the node
                # has two validators rejecting both-missing and both-present.
                client: 'my.redis'          # service id of a Redis client
                # connection_parameters: { host: '127.0.0.1', port: 6379 }
                endpoint: null
                index_name: 'chat_messages'
        session:
            support:
                identifier: 'app_session_id'
        mongodb:
            support:
                client: 'MongoDB\\Client'   # default: the client FQCN, used as a service id
                database: 'app'             # required
                collection: 'messages'      # required
        cloudflare:
            support:
                namespace: 'prod'
                account_id: '%env(CF_ACCOUNT_ID)%'
                api_key: '%env(CF_API_KEY)%'
                endpoint_url: null
        meilisearch:
            support:
                endpoint: '%env(MEILI_URL)%'
                api_key: '%env(MEILI_KEY)%'
                index_name: 'chat'
        pogocache:
            support:
                endpoint: '%env(POGO_ENDPOINT)%'
                password: '%env(POGO_PASSWORD)%'
                key: 'chat'
        surrealdb:
            support:
                endpoint: '%env(SURREAL_URL)%'
                username: 'root'
                password: '%env(SURREAL_PASS)%'
                namespace: 'app'
                database: 'chat'
                table: null   # default = instance name
                namespaced_user: null
```

## Aliases auto-created by the bundle

For each singleton platform, the bundle auto-aliases `PlatformInterface::class` when only one platform is configured (`AiBundle::loadExtension()`, `setAlias()` calls). Same for `AgentInterface::class`, `StoreInterface::class`, `MessageStoreInterface::class`, `ChatInterface::class`, `IndexerInterface::class`, `RetrieverInterface::class`. When several are configured, you must type-hint the named service (`ai.agent.default`, `ai.store.pinecone.default`, …) or use `#[Target('default')]`.

## Removed when optional packages are missing

`AiBundle::loadExtension()` removes services for missing optional packages:

| Missing package         | Removed                                                                                                                                              |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `symfony/security-core` | `ai.security.is_granted_attribute_listener` + `#[IsGrantedTool]` autoconfig (throws on compile)                                                      |
| `symfony/validator`     | `ai.tool.validate_tool_call_arguments_listener`, `ai.platform.structured_output.validator_subscriber`, `ai.platform.json_schema.describer.validator` |
| `symfony/ai-agent`      | tool/agent commands + toolbox wiring                                                                                                                 |
| `symfony/ai-store`      | store/indexer/retrieve commands                                                                                                                      |
| `symfony/ai-chat`       | message-store commands, `ai.chat.message_bag.normalizer`                                                                                             |
| `kernel.debug == false` | `ai.data_collector`, `ai.traceable_toolbox`                                                                                                          |

Compiler passes (registered in `AiBundle::build()`): `DebugCompilerPass`, `ProcessorCompilerPass`, `SchemaProviderValidationPass`.
