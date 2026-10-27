# YAML Config Reference

> **Source of truth**: `https://github.com/symfony/ai/tree/main/src/ai-bundle/config/options.php` is the canonical config tree. Per-platform and per-store schemas live in `config/platform/<provider>.php` and `config/store/<provider>.php`. Service wiring lives in `config/services.php`. This document only describes what actually exists in source.

## Contents

- Root tree (from `config/options.php`)
- `ai.platform`
  - Singleton providers (one platform per YAML key)
  - Named providers (multiple instances under one key)
  - `model_catalog` (every platform, 1.0)
- `ai.agent`
- `ai.multi_agent`
- `ai.store`
- `ai.vectorizer`
- `ai.retriever`
- `ai.indexer`
- `ai.message_store`
- Aliases auto-created by the bundle
- Removed when optional packages are missing

## Root tree (from `config/options.php`)

```text
ai:
    platform:           # LLM providers (extra models: <provider>.model_catalog.models)
    agent:              # named agents
    multi_agent:        # orchestrator + handoffs
    store:              # vector stores, grouped by provider
    vectorizer:         # wraps a platform + model
    retriever:          # (vectorizer, store)
    indexer:            # (loader, source, transformers, filters, vectorizer, store)
    message_store:      # conversation stores, referenced by ai.agent.<name>.message_store
```

There is **no** `ai.profiler.*` key. Profiling is gated by `kernel.debug`. 1.0 removed the root `chat` key (with the Chat component; use the agent's `message_store` option) and the root `model` key (use the platform's `model_catalog.models`).

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
        higgsfield: { api_key: '%env(HIGGSFIELD_API_KEY)%', api_secret: '%env(HIGGSFIELD_API_SECRET)%', base_url: null }

        huggingface:
            api_key: '%env(HF_TOKEN)%'
            provider: null        # 0.15: null (was 'hf-inference'); HF picks the provider; chat completion only
            model_catalog:
                api: true         # 1.0 (was api_catalog: true): resolve models through the Hub API (ModelApiCatalog)
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
                # model_catalog: 'App\AI\MyCatalog'   # optional, see model_catalog below
                supports_completions: true
                supports_embeddings: true
                completions_path: '/v1/chat/completions'
                embeddings_path: '/v1/embeddings'

        openresponses:
            local:
                base_url: 'http://localhost:9000'
                api_key: null
                http_client: 'http_client'
                responses_path: '/v1/responses'   # this IS the default, not null

        bedrock:
            prod:
                api: invoke_model              # since 0.14: invoke_model (default, AWS SDK) | completions | responses | messages
                bedrock_runtime_client: null   # service id (null => SDK default); only with api: invoke_model
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

### `model_catalog` (every platform, 1.0)

Every platform, singleton or named, takes a `model_catalog` node (`config/platform/model_catalog.php`); a plain string is short for `service`. It replaces the root `ai.model` key, the `huggingface` `api_catalog` option and the `ai.platform.model_catalog.amazeeai` / `.aimlapi` / `.meta` / `.replicate` services (register such a catalog class as your own service instead).

```yaml
ai:
    platform:
        lmstudio:
            host_url: '%env(LMSTUDIO_HOST_URL)%'
            model_catalog:
                service: ~                  # id of a custom ModelCatalogInterface, instead of the bridge's own
                models:                     # added in front of the catalog, same name wins
                    qwen3-coder-next:
                        class: 'Symfony\AI\Platform\Bridge\Generic\CompletionsModel'   # default Symfony\AI\Platform\Model
                        capabilities: ['input-messages', 'output-text']             # Capability values, at least one
                cache: false                # true, or { service: 'cache.app', ttl: 3600 }: CachedModelCatalog
```

- `api` (`huggingface`, `openrouter`, `edenai` only): fetch the models from the provider API instead of the bundled list; it cannot be combined with `service`.
- Platforms whose catalog always comes from the API (`amazeeai`, `deepgram`, `elevenlabs`, `fireworks`, `higgsfield`, `ollama`, `together`, `venice`) take `service`, `models` and `cache`, but no `api`.
- `cache` only makes sense for an API or custom catalog: on a bundled list it fails with `Caching the model catalog requires a custom "service" or "api: true", the bundled list needs no cache.`
- A `class` that does not exist or does not extend `Symfony\AI\Platform\Model` fails the config (`The model class "…" does not exist.` / `… must extend Symfony\AI\Platform\Model.`).

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
                #                                  # its McpToolbox is tagged kernel.reset (0.15): the tool list is re-fetched per request/message
                #       prefix: 'readme_'          # optional, only with mcp_server; default "<server>_"
                # execution_strategy: fiber      # since 0.14: sequential (default) | fiber | custom ToolExecutorInterface service id
            include_sources: false
            message_store: null              # 1.0: service id of an ai.message_store, e.g. 'ai.message_store.redis.chats'
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
- `message_store` (1.0) passes that service to the `Agent`'s `messageStore` argument: the agent loads and saves each conversation under the id of the `MessageBag` it is called with (`MessageBag::forId()`, see the `symfony-ai-agent` skill). It replaces the 0.x `ai.chat` node. `exclude_tool_messages` is gone: tool messages never reach the caller's bag.
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

Defined in `config/store/*.php`. Each provider is a top-level child of `ai.store`; under it, named instances. Since 1.0 the names must be unique across all store types (`blog_store` and `blogStore` count as the same): `The stores "…" have conflicting names, store names must be unique across all store types.` Per-store schemas vary : the example below is `pinecone` (`config/store/pinecone.php`):

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
                dimensions: 1536             # 1.0: plain keys, read by `ai:store:setup` (were setup_options.dimension, …)
                metric: 'cosine'             # cosine | euclidean | dotproduct
                cloud: 'aws'
                region: 'us-east-1'

        memory:
            main:
                strategy: 'cosine'   # DistanceStrategy (in-process scoring)

        cache:
            cached:
                service: 'cache.app'
                cache_key: null
                strategy: 'cosine'

        qdrant:
            documents:
                collection_name: null
                endpoint: null
                api_key: null
                http_client: 'http_client'
                dimensions: 1536
                metric: 'Cosine'     # 1.0, was `distance`
                async: false
```

1.0 replaced the `setup_options` of `mariadb`, `mongodb`, `pinecone`, `postgres`, `redis`, `s3vectors` and `surrealdb` by store keys, and renamed the metric and size keys everywhere:

| Store | Before 1.0 | 1.0 |
| --- | --- | --- |
| `mariadb` | `setup_options.dimensions`, `distance` | `dimensions`, `metric` |
| `mongodb` | `setup_options.fields`, `similarity` | `index_fields`, `metric` |
| `pinecone` | `setup_options.dimension`, `.metric`, `.cloud`, `.region` | `dimensions`, `metric`, `cloud`, `region` |
| `postgres` | `setup_options.vector_size`, `.vector_type`, `.index_method`, `.index_opclass`, `distance` | `dimensions`, `vector_type`, `index_method`, `index_opclass`, `metric` |
| `redis` | `setup_options.vector_size`, `distance` | `dimensions`, `metric` |
| `s3vectors` | `setup_options.dimension`, `.distance_metric` | `dimensions`, `metric` |
| `surrealdb` | `setup_options.force_database_creation`, `strategy` | `ai:store:setup <name> --option forceDatabaseCreation=true`, `metric` |
| `elasticsearch`, `manticoresearch` | `similarity` | `metric` |
| `milvus` | `metric_type` | `metric` |
| `neo4j`, `qdrant` | `distance` | `metric` |
| `opensearch` | `space_type` | `metric` |
| `sqlite` | `distance`, `vector_dimension` | `metric`, `dimensions` |
| `supabase` | `vector_dimension` | `dimensions` |

`redis` now creates a 1536-dimensional index by default (was 3072): set `dimensions: 3072` to keep Gemini-sized vectors, documents of another size are not indexed. `pinecone` and `s3vectors` no longer require the dimensions (1536 by default).

`postgres` (`config/store/postgres.php`) is worth its own example : it's the store the official `demo/` application actually runs in production-shaped config.

```yaml
ai:
    store:
        postgres:
            symfony_blog:
                dbal_connection: 'doctrine.dbal.default_connection'   # OR dsn: '...' — exactly one of the two
                table_name: 'symfony_blog'
                vector_field: 'embedding'      # default
                metric: 'cosine'               # cosine | inner_product | l1 | l2 ; default l2 (was `distance`)
                lang: 'english'                # default; used for the tsvector language config
                dimensions: 1536               # store default 1536 (was setup_options.vector_size)
                vector_type: 'vector'          # vector | halfvec
                # index_method: 'hnsw'         # unset = the store default, hnsw (0.15; was ivfflat)
                # index_opclass: ~             # unset = the opclass of `metric` (vector_cosine_ops here)
```

`ai:store:setup symfony_blog` creates an `hnsw` index with the operator class matching `metric` (before 0.15: `ivfflat` with `vector_cosine_ops` whatever the distance). HNSW needs pgvector 0.5.0+. An existing index is kept as is; drop it and rerun `ai:store:setup` to rebuild it.

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

`redis`, `mongodb`, `s3vectors` and `surrealdb` in 1.0:

```yaml
ai:
    store:
        redis:
            vectors:
                client: 'my.redis'          # OR connection_parameters: {...} — exactly one
                index_name: 'docs'
                metric: 'COSINE'            # COSINE | L2 | IP; default COSINE
                dimensions: 3072            # unset = the store default, 1536 (3072 before 1.0)
        mongodb:
            atlas:
                client: 'MongoDB\Client'    # default
                database: 'app'             # required
                collection: 'docs'
                index_name: 'vector_index'  # required
                dimensions: 1536            # vector index size; store default 1536
                metric: 'cosine'            # euclidean | cosine | dotProduct; store default euclidean
                index_fields: []            # filter fields of the index (was setup_options.fields)
        s3vectors:
            aws:
                vector_bucket_name: 'my-bucket'
                index_name: 'docs'
                dimensions: 1536            # optional since 1.0
                metric: 'cosine'            # cosine | euclidean
        surrealdb:
            surreal:
                endpoint: '%env(SURREAL_URL)%'
                username: 'root'
                password: '%env(SURREAL_PASS)%'
                namespace: 'app'
                database: 'rag'
                # SurrealDB 3 no longer creates them on first use:
                # php bin/console ai:store:setup surreal --option forceDatabaseCreation=true
```

`doctrine` (1.0, `symfony/ai-doctrine-store`) keeps the vectors in an `#[Embedding]` field of a Doctrine entity and registers the `vector` DBAL type and the `VECTOR_DISTANCE` DQL function:

```yaml
ai:
    store:
        doctrine:
            articles:
                entity: 'App\Entity\Article'
                metric: 'cosine'                              # cosine | euclidean | inner_product
                entity_manager: 'doctrine.orm.entity_manager' # default
                vectorizer: 'ai.vectorizer.openai_embeddings' # embeds on flush and registers the `articles` indexer
            products:
                entity: 'App\Entity\Product'                 # #[Embedding] on the class
                vectorizer: 'ai.vectorizer.openai_embeddings'
                mirror_to: 'ai.store.qdrant.catalog'          # no OrmStore: a mirror listener, an indexer and ai.retriever.products
```

With `mirror_to`, a `retriever` or `indexer` of the same name is not allowed. Mapping, indexes and write semantics are in the `symfony-ai-store` skill (`references/bridges.md` → *Doctrine*).

Other supported providers (schemas in `config/store/<provider>.php`, not individually detailed here): `azuresearch`, `chromadb`, `clickhouse`, `cloudflare`, `elasticsearch`, `manticoresearch`, `mariadb`, `meilisearch`, `milvus`, `mongodb`, `neo4j`, `opensearch`, `redis`, `s3vectors`, `sqlite`, `supabase`, `surrealdb`, `typesense`, `vektor`, `weaviate`. Read the corresponding `config/store/<provider>.php` file directly when configuring one of these — the shape follows the same pattern (provider name as parent key, named instances under it) but options differ per backend.

**There is no `bridge:` sub-key.** The provider name (`pinecone`, `mongodb`, `postgres`, …) is the parent key in YAML. There is no `embedding_model:` or `transformers:` sub-key : embedding is configured via `ai.vectorizer.<name>` and used by indexer/retriever.

The `ai:store:setup`, `ai:store:drop` and `ai:store:clear` commands take the configured name since 1.0 (`ai:store:drop default --force`, was `ai.store.chromadb.default`), like `ai:store:index` and `ai:store:retrieve`; `setup` and `drop` accept `--option name=value`. The `store:` option of `ai.indexer` and `ai.retriever` still takes a service id.

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

## `ai.message_store`

Defined in `config/message_store/*.php`. Each provider is a top-level child of `ai.message_store`; under it, named instances. Since 1.0 they are the message stores of the Agent component (`Symfony\AI\Agent\MessageStore\MessageStoreInterface`, classes under `Symfony\AI\Agent\Bridge\*`), used through an agent's `message_store` option; names must be unique across message-store types (`The message stores "…" have conflicting names, …`).

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
            support: ~                  # 1.0: no `identifier`, conversations are kept by their id
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

Service ids are `ai.message_store.<type>.<name>`, except Doctrine: `ai.message_store.doctrine.dbal.<name>` (the shorter `ai.message_store.doctrine.<name>` is only a named-argument alias). That id is what an agent's `message_store` and the `ai:message-store:setup <id>` / `ai:message-store:drop <id> --force` commands take. The `cache`, `pogocache`, `session` and `memory` stores have nothing to set up. Each store receives the application's `serializer`, on which the bundle registers `ai.platform.message_normalizer` (renamed from `ai.chat.message_bag.normalizer`), `ai.platform.message_bag_normalizer` and `ai.agent.source_collection_normalizer`.

The 1.0 stores keep one serialized `MessageBag` per conversation and do not read what the 0.x Chat stores wrote; for Doctrine, drop the old table and run `ai:message-store:setup` again (`setup()` keeps an existing table).

## Aliases auto-created by the bundle

For each singleton platform, the bundle auto-aliases `PlatformInterface::class` when only one platform is configured (`AiBundle::loadExtension()`, `setAlias()` calls). Since 0.15 every service tagged `ai.platform` also gets a `#[Target]` alias named after its tag (dots replaced by underscores): `#[Target('openai')]` for a singleton provider, `#[Target('cache_<name>')]` for a cache instance, `#[Target('<name>')]` for a failover instance. A failover service's `ai.platform` tag now carries its instance name instead of the hardcoded `failover`, which only matters to code reading that tag attribute. Same for `AgentInterface::class`, `StoreInterface::class`, `MessageStoreInterface::class`, `IndexerInterface::class`, `RetrieverInterface::class`. When several are configured, you must type-hint the named service (`ai.agent.default`, `ai.store.pinecone.default`, …) or use `#[Target('default')]`. Stores and message stores are also autowirable by their configured name (`StoreInterface $documents`, `MessageStoreInterface $support`); 1.0 removed the type-prefixed aliases (`StoreInterface $chromadbDocuments`). A `failover` platform must not be named like another platform (`The platforms "…" and "…" have conflicting names, platform names must be unique.`).

## Removed when optional packages are missing

`AiBundle::loadExtension()` removes services for missing optional packages:

| Missing package         | Removed                                                                                                                                              |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `symfony/security-core` | `ai.security.is_granted_attribute_listener` + `#[IsGrantedTool]` autoconfig (throws on compile)                                                      |
| `symfony/validator`     | `ai.tool.validate_tool_call_arguments_listener`, `ai.platform.structured_output.validator_subscriber`, `ai.platform.json_schema.describer.validator` |
| `symfony/ai-agent`      | tool/agent commands, toolbox wiring, `ai.agent.source_collection_normalizer`                                                                         |
| `symfony/ai-store`      | store/indexer/retrieve commands                                                                                                                      |
| no `ai.message_store`   | `ai:message-store:setup` / `ai:message-store:drop` (`ai.command.setup_message_store`, `ai.command.drop_message_store`)                               |
| `kernel.debug == false` | `ai.data_collector`, `ai.traceable_toolbox`                                                                                                          |

Compiler passes (registered in `AiBundle::build()`): `DebugCompilerPass`, `ProcessorCompilerPass`, `SchemaProviderValidationPass`.
