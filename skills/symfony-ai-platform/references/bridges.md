# Platform : Bridges

All 43 platform bridges verified by reading every
`https://github.com/symfony/ai/tree/main/src/platform/src/Bridge/<Dir>/composer.json`.
Each bridge is a separate Composer package : install only what you use.

To regenerate the table from source, run `ls -1 src/platform/src/Bridge/` and
read the `name` field of each `composer.json`.

## Contents

- Full table
- Grouped by category
  - Commercial frontier / hosted
  - Cloud-provider proxies / hosts
  - Local / self-hosted
  - Audio / specialised modalities
  - Aggregators / orchestrators
  - Subprocess-based agents (process wrappers)
  - Decorator / cross-cutting bridges
- Reranking : where to find it
- Installation pattern

## Full table

| Dir               | Composer package                          | Notes                                           |
| ----------------- | ----------------------------------------- | ----------------------------------------------- |
| AiMlApi           | `symfony/ai-ai-ml-api-platform`           | AI/ML API                                       |
| Albert            | `symfony/ai-albert-platform`              | Etalab Albert (French gov)                      |
| AmazeeAi          | `symfony/ai-amazee-ai-platform`           | Amazee.AI                                       |
| Anthropic         | `symfony/ai-anthropic-platform`           | Claude (Haiku, Sonnet, Opus)                    |
| Azure             | `symfony/ai-azure-platform`               | Azure OpenAI + Meta + Responses                 |
| Bedrock           | `symfony/ai-bedrock-platform`             | AWS Bedrock (Anthropic, Meta, Nova)             |
| Cache             | `symfony/ai-cache-platform`               | `CachePlatform` decorator                       |
| Cartesia          | `symfony/ai-cartesia-platform`            | Cartesia TTS / voice                            |
| Cerebras          | `symfony/ai-cerebras-platform`            | Cerebras inference                              |
| ClaudeCode        | `symfony/ai-claude-code-platform`         | Claude Code agent subprocess                    |
| Codex             | `symfony/ai-codex-platform`               | OpenAI Codex subprocess                         |
| Cohere            | `symfony/ai-cohere-platform`              | Embeddings + Rerank + LLM + STT                 |
| Decart            | `symfony/ai-decart-platform`              | Decart video                                    |
| DeepSeek          | `symfony/ai-deep-seek-platform`           | DeepSeek                                        |
| Deepgram          | `symfony/ai-deepgram-platform`            | Deepgram STT                                    |
| DockerModelRunner | `symfony/ai-docker-model-runner-platform` | Docker Model Runner                             |
| EdenAi            | `symfony/ai-eden-ai-platform`             | Eden AI gateway + OCR/STT/TTS/image (async jobs) |
| ElevenLabs        | `symfony/ai-eleven-labs-platform`         | ElevenLabs TTS                                  |
| Failover          | `symfony/ai-failover-platform`            | `FailoverPlatform` decorator                    |
| Fireworks         | `symfony/ai-fireworks-platform`           | Fireworks AI: chat + embeddings + rerank        |
| Gemini            | `symfony/ai-gemini-platform`              | Google Gemini direct                            |
| Generic           | `symfony/ai-generic-platform`             | OpenAI-compatible completions + embed           |
| Higgsfield        | `symfony/ai-higgsfield-platform`          | Higgsfield image/video generation (async jobs)  |
| HuggingFace       | `symfony/ai-hugging-face-platform`        | HF Inference API (multi-task)                   |
| LmStudio          | `symfony/ai-lm-studio-platform`           | LM Studio local                                 |
| Meta              | `symfony/ai-meta-platform`                | Llama (Llama.php + prompt converter)            |
| MiniMax           | `symfony/ai-mini-max-platform`            | MiniMax provider (video / async TTS are jobs)   |
| Mistral           | `symfony/ai-mistral-platform`             | Mistral + Embeddings + OCR                      |
| ModelsDev         | `symfony/ai-models-dev-platform`          | models.dev catalogue aggregator                 |
| Ollama            | `symfony/ai-ollama-platform`              | Ollama local                                    |
| OpenAi            | `symfony/ai-open-ai-platform`             | OpenAI GPT + Embeddings + Image + TTS + Whisper |
| OpenResponses     | `symfony/ai-open-responses-platform`      | OpenAI Responses API                            |
| OpenRouter        | `symfony/ai-open-router-platform`         | OpenRouter aggregator + Rerank + Speech         |
| Ovh               | `symfony/ai-ovh-platform`                 | OVHcloud AI Endpoints                           |
| Perplexity        | `symfony/ai-perplexity-platform`          | Perplexity search LLM                           |
| Replicate         | `symfony/ai-replicate-platform`           | Replicate (every call is an async job)          |
| Scaleway          | `symfony/ai-scaleway-platform`            | Scaleway GenAI (LLM + Embeddings + Responses)   |
| Together          | `symfony/ai-together-platform`            | Together: chat, embed, image, TTS, STT, rerank  |
| TransformersPhp   | `symfony/ai-transformers-php-platform`    | TransformersPHP local pipeline                  |
| TypeSafe          | `symfony/ai-type-safe-platform`           | TypeSafe typed-question evaluation (Jev models) |
| Venice            | `symfony/ai-venice-platform`              | Venice AI: chat, embed, image, TTS, STT, video  |
| VertexAi          | `symfony/ai-vertex-ai-platform`           | Vertex AI (Embeddings + Gemini)                 |
| Voyage            | `symfony/ai-voyage-platform`              | Voyage embeddings                               |

## Grouped by category

### Commercial frontier / hosted

These target major commercial APIs and require a vendor API key.

- `symfony/ai-open-ai-platform` : OpenAI (GPT, Embeddings, Image generation,
  Text-to-Speech, Whisper). `Factory::createProvider()` and
  `Factory::createPlatform()` are the canonical reference shape.
- `symfony/ai-anthropic-platform` : Anthropic Claude. `Factory::createPlatform()`
  accepts a `cacheRetention` parameter (`'none'|'short'|'long'`, default
  `'short'`) that controls Anthropic prompt caching. Since 0.14 the
  `server_tools` option maps `web_search` and `code_execution` to their
  versioned Anthropic tool spec (`['server_tools' => ['web_search' => ['max_uses' => 3]]]`);
  unmapped names throw. A web search comes back as a `Result\WebSearchResult`
  part of a `MultiPartResult` (read with `asMultiPart()`).
- `symfony/ai-mistral-platform` : Mistral chat + Embeddings + OCR.
- `symfony/ai-cohere-platform` : Cohere chat + Embeddings + Rerank + Speech-to-Text.
  This is the **canonical reranking bridge** in this codebase (see
  `Reranker` with models `rerank-v3.5`, `rerank-v4.0-fast`, `rerank-v4.0-pro`,
  `rerank-english-v3.0`, `rerank-multilingual-v3.0`).
- `symfony/ai-deep-seek-platform` : DeepSeek.
- `symfony/ai-gemini-platform` : Google Gemini direct.
- `symfony/ai-vertex-ai-platform` : Vertex AI (Embeddings + Gemini).
- `symfony/ai-perplexity-platform` : Perplexity search-augmented LLM.
- `symfony/ai-ai-ml-api-platform` : AI/ML API.
- `symfony/ai-albert-platform` : Etalab Albert (French government).
- `symfony/ai-amazee-ai-platform` : Amazee.AI.
- `symfony/ai-cerebras-platform` : Cerebras inference.
- `symfony/ai-mini-max-platform` : MiniMax (its own provider; **not** an
  Anthropic alias). Video generation and `async: true` speech return a
  `JobResult` since 0.14 : resolve with `Factory::createJobClient()` +
  `JobRunner` (see `api-reference.md` → Asynchronous jobs).
- `symfony/ai-venice-platform` : Venice AI (chat with `venice_parameters`,
  embeddings, image generation/editing/upscaling, TTS, STT, async video jobs).
- `symfony/ai-type-safe-platform` : TypeSafe, evaluates typed questions
  (choice, score, …) against a state with the Jev models; not a chat LLM.
- `symfony/ai-decart-platform` : Decart video.
- `symfony/ai-models-dev-platform` : models.dev catalogue aggregator (provides
  `ProviderRegistry` + `CapabilityMapper`, not its own HTTP transport).

### Cloud-provider proxies / hosts

Models hosted inside hyperscalers, addressed via their own IAM/region
plumbing.

- `symfony/ai-azure-platform` : Azure OpenAI + Meta + Responses.
- `symfony/ai-bedrock-platform` : AWS Bedrock (subdirs `Anthropic/`, `Meta/`,
  `Nova/`).
- `symfony/ai-scaleway-platform` : Scaleway (LLM + Embeddings + Responses).
- `symfony/ai-ovh-platform` : OVHcloud AI Endpoints.

### Local / self-hosted

Inference you run yourself.

- `symfony/ai-ollama-platform` : Ollama.
- `symfony/ai-lm-studio-platform` : LM Studio.
- `symfony/ai-docker-model-runner-platform` : Docker Model Runner.
- `symfony/ai-transformers-php-platform` : TransformersPHP (PHP-native pipeline
  via `PipelineExecution` + `RawPipelineResult`).
- `symfony/ai-meta-platform` : **not an inference bridge.** It ships no `Factory`
  and no `ModelClient` — only the `Llama` model class, a `LlamaPromptConverter`,
  a `ModelCatalog` and a `Contract/`. Use it to format prompts for Llama models
  served through another platform (Bedrock, Ollama, …), not to run them.

### Audio / specialised modalities

- `symfony/ai-cartesia-platform` : Cartesia TTS / voice.
- `symfony/ai-deepgram-platform` : Deepgram STT.
- `symfony/ai-eleven-labs-platform` : ElevenLabs TTS.
- `symfony/ai-replicate-platform` : Replicate. Every model runs as a
  prediction, so since 0.14 **every** invocation returns a `JobResult` : call
  `->asJob()` and resolve through `Factory::createJobClient()` + `JobRunner`.
- `symfony/ai-higgsfield-platform` : Higgsfield asynchronous image and video
  generation (job client).
- `symfony/ai-eden-ai-platform` : Eden AI gateway : OpenAI-compatible chat and
  embeddings, plus expert models (OCR, document parsing, TTS, async
  speech-to-text, image analysis/generation).

### Aggregators / orchestrators

- `symfony/ai-open-router-platform` : OpenRouter (includes `RerankModel` and a
  `Speech` namespace; this is the second canonical reranking bridge).
- `symfony/ai-hugging-face-platform` : HuggingFace Inference API.
- `symfony/ai-generic-platform` : Generic OpenAI-compatible completion +
  embeddings (for self-hosted proxies).
- `symfony/ai-fireworks-platform` : Fireworks AI (OpenAI-compatible chat,
  embeddings, reranking).
- `symfony/ai-together-platform` : Together AI (chat, embeddings, image
  generation, TTS, STT, reranking).

### Subprocess-based agents (process wrappers)

These bridges spawn a subprocess rather than calling an HTTP API. They live
under the Platform component but model themselves after an agent process.

- `symfony/ai-claude-code-platform` : Claude Code subprocess, with its own
  `RawProcessResult` + `Exception` namespace.
- `symfony/ai-codex-platform` : OpenAI Codex subprocess, same pattern.

### Decorator / cross-cutting bridges

These wrap any `PlatformInterface`; they do not target a vendor themselves.

- `symfony/ai-failover-platform` : `FailoverPlatform` (rate-limited,
  multi-platform). Not bundled with `symfony/ai-platform`; install separately.
- `symfony/ai-cache-platform` : `CachePlatform` (opt-in via
  `options['prompt_cache_key']`). Not bundled with `symfony/ai-platform`;
  install separately.
- `symfony/ai-open-responses-platform` : speaks the OpenResponses wire
  protocol against any compliant server.

## Reranking : where to find it

Cohere and OpenRouter ship dedicated rerank models; Fireworks and Together
(since 0.14) also serve reranking through `asReranking()`. There is **no** Voyage rerank.

- `symfony/ai-cohere-platform` : `Bridge\Cohere\Reranker` with models
  `rerank-v3.5`, `rerank-v4.0-fast`, `rerank-v4.0-pro`, `rerank-english-v3.0`,
  `rerank-multilingual-v3.0`. Result type: `Result\RerankingResult` containing
  `RerankingEntry` (`getIndex(): int`, `getScore(): float`).
- `symfony/ai-open-router-platform` : `Bridge\OpenRouter\RerankModel` plus a
  `Rerank/` subnamespace.

`symfony/ai-voyage-platform` ships embeddings only.

## Installation pattern

Pick one (or more) inference bridge plus optionally the decorators:

```bash
composer require symfony/ai-platform
composer require symfony/ai-open-ai-platform       # or any other inference bridge
composer require symfony/ai-failover-platform      # optional, for multi-provider failover
composer require symfony/ai-cache-platform         # optional, for response caching
```

Each bridge is a separate Composer package and only pulls in the SDK / vendor
HTTP client it actually needs. Do not install the vendor PHP SDK yourself :
the bridge depends on it.

```php
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;

$platform = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);
```

## See also

- `references/api-reference.md` : Platform, Model, Contract, Message, Tool, Result,
  TokenUsage, FinishReason
- `references/patterns.md` : Failover, structured output, tool calling,
  multi-modal, streaming
- `references/embeddings.md` : Embeddings contract (different from text
  generation)
- `references/gotchas.md` : Provider quirks, retries, multimodal edge cases
