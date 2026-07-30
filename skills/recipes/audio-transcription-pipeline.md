---
title: Audio transcription pipeline
composes: platform (Whisper bridge), agent (SpeechAgent)
target-version: PHP 8.2+ / Symfony 6.4 | 7.4 | 8.0
last-verified: 2026-07-28
---

> Symfony AI is **experimental** : APIs may break between releases. Always check `UPGRADE.md` in the [symfony/ai monorepo](https://github.com/symfony/ai) before upgrading.

Transcribe an audio file using OpenAI Whisper, then optionally summarise with an LLM via `SpeechAgent`. Cache results by content hash to avoid re-paying for identical audio.

## Composes

- **`platform`** : `Symfony\AI\Platform\Bridge\OpenAi\Factory` plus the `Whisper` model (`Symfony\AI\Platform\Bridge\OpenAi\Whisper`) and `Whisper\Task::TRANSCRIPTION`.
- **`agent`** : `Symfony\AI\Agent\SpeechAgent` (wraps an inner `Agent` with optional STT/TTS platforms) and `Speech\SpeechConfiguration`.

## Installation

```bash
composer require symfony/ai-platform symfony/ai-agent
composer require symfony/ai-open-ai-platform
composer require symfony/ai-bundle   # optional YAML wiring
```

## Critical API rules

From `src/agent/src/SpeechAgent.php`:

```php
// SpeechAgent::__construct(
//     AgentInterface $agent,                  // the inner agent doing the LLM work
//     SpeechConfiguration $configuration,     // tts_model, stt_model, options
//     ?PlatformInterface $speechToTextPlatform = null,
//     ?PlatformInterface $textToSpeechPlatform = null,
// )
```

`SpeechConfiguration` (`src/agent/src/Speech/SpeechConfiguration.php`) is built from four positional args: `($ttsModel, $ttsOptions, $sttModel, $sttOptions)`. STT and TTS are each optional and only fire if both their model **and** their platform are present.

The inner `Agent` does the LLM work; STT happens before the call, TTS happens after. The audio payload is consumed via `UserMessage::getAudioContent()` and replaced with the transcribed text before the agent sees it.

## Manual wiring (recommended)

Build the inner Agent, then wrap it. The OpenAI platform handles both Whisper (STT) and chat (LLM); pass it to both the Whisper client and the chat client. Here we use the OpenAI factory for both the STT platform and the LLM platform:

```php
use Symfony\AI\Agent\Agent;
use Symfony\AI\Agent\Speech\SpeechConfiguration;
use Symfony\AI\Agent\SpeechAgent;
use Symfony\AI\Platform\Bridge\OpenAi\Factory as OpenAiFactory;

$openai = OpenAiFactory::createPlatform($_ENV['OPENAI_API_KEY']);

$innerAgent = new Agent($openai, 'gpt-4o-mini');

$speechAgent = new SpeechAgent(
    agent: $innerAgent,
    configuration: new SpeechConfiguration(
        ttsModel: 'tts-1',         // optional, omit to disable TTS
        sttModel: 'whisper-1',     // required for STT
        // ttsOptions: ['voice' => 'alloy'],
        // sttOptions: ['language' => 'en'],
    ),
    speechToTextPlatform: $openai,   // can be the same platform instance
    textToSpeechPlatform: null,      // set to enable TTS
);
```

`SpeechAgent` checks `$configuration->supportsSpeechToText()` (`sttModel !== null`) **and** `$speechToTextPlatform instanceof PlatformInterface` before transcribing. Same dual-check for TTS.

## Sending an audio message

`SpeechAgent::call()` accepts `string|MessageBag|UserMessage` and replaces the audio content with its transcription before invoking the inner agent:

```php
use Symfony\AI\Platform\Message\Content\Audio;
use Symfony\AI\Platform\Message\Message;
use Symfony\AI\Platform\Message\MessageBag;

$audio = Audio::fromFile('/path/to/recording.mp3');
$bag = new MessageBag(
    Message::ofUser('Transcribe this audio and provide a 2-sentence summary.', $audio),
);

$result = $speechAgent->call($bag);
echo $result->getContent();
```

When TTS is configured, `SpeechAgent` invokes the TTS platform with the assistant's text and the `ttsModel`, then attaches the original text as `'text'` metadata on the resulting `DeferredResult`.

## YAML wiring (with the bundle)

`config/packages/ai.yaml` : keys verified against `src/ai-bundle/config/options.php` (`agent.<name>.speech` block):

```yaml
ai:
    platform:
        openai:
            api_key: '%env(OPENAI_API_KEY)%'

    agent:
        transcription:
            platform: 'ai.platform.openai'
            model: 'gpt-4o-mini'
            speech:
                enabled: true
                speech_to_text_platform: 'ai.platform.openai'
                stt_model: 'whisper-1'
                stt_options:
                    language: 'en'
                # Optional TTS:
                # text_to_speech_platform: 'ai.platform.openai'
                # tts_model: 'tts-1'
                # tts_options:
                #     voice: 'alloy'
```

The bundle compiles the configured `Agent` and wraps it in a `SpeechAgent` (`ai.agent.transcription`).

## CLI command

```php
namespace App\Command;

use Symfony\AI\Agent\SpeechAgent;
use Symfony\AI\Agent\AgentInterface;
use Symfony\AI\Platform\Message\Content\Audio;
use Symfony\AI\Platform\Message\Message;
use Symfony\AI\Platform\Message\MessageBag;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;

#[AsCommand('app:audio:transcribe', 'Transcribe an audio file and summarise.')]
final class TranscribeCommand extends Command
{
    public function __construct(private readonly AgentInterface $transcription)
    {
        parent::__construct();
    }

    protected function execute(\Symfony\Component\Console\Input\InputInterface $input, \Symfony\Component\Console\Output\OutputInterface $output): int
    {
        $file = (string) $input->getArgument('file');

        $bag = new MessageBag(
            Message::ofUser('Transcribe this audio and provide a 2-sentence summary.', Audio::fromFile($file)),
        );

        $result = $this->transcription->call($bag);
        $output->writeln((string) $result->getContent());

        return Command::SUCCESS;
    }

    protected function configure(): void
    {
        $this->addArgument('file', \Symfony\Component\Console\Input\InputArgument::REQUIRED);
    }
}
```

```bash
php bin/console app:audio:transcribe /path/to/recording.mp3
```

The injected `AgentInterface` is the bundle-wrapped `SpeechAgent` (`ai.agent.transcription`).

## Caching by content hash

Wrap in a PSR-6 cache to dedupe identical audio (avoids repeat transcription costs):

```php
namespace App\Audio;

use Symfony\AI\Agent\AgentInterface;
use Symfony\AI\Platform\Message\Content\Audio;
use Symfony\AI\Platform\Message\Message;
use Symfony\AI\Platform\Message\MessageBag;
use Symfony\Contracts\Cache\CacheInterface;
use Symfony\Contracts\Cache\ItemInterface;

final class CachedTranscriber
{
    public function __construct(
        private readonly AgentInterface $speechAgent,
        private readonly CacheInterface $cache,
    ) {
    }

    public function transcribe(string $file): string
    {
        $hash = hash_file('sha256', $file);

        return $this->cache->get("transcription.$hash", function (ItemInterface $item) use ($file): string {
            $item->expiresAfter(86400 * 30);   // 30 days

            $bag = new MessageBag(
                Message::ofUser('Transcribe:', Audio::fromFile($file)),
            );

            return (string) $this->speechAgent->call($bag)->getContent();
        });
    }
}
```

Re-running on the same audio = instant cache hit, no API cost.

## Audio format compatibility

| Provider | Accepted formats | Max size |
|---|---|---|
| OpenAI Whisper | MP3, MP4, M4A, WAV, WEBM | 25 MB / ~1 hour |

For unsupported formats, pre-convert with `ffmpeg`:

```bash
ffmpeg -i input.aac -ac 1 -ar 16000 output.wav
```

## Variants: STT-only, TTS-only, full pipeline

### STT-only

Configure `sttModel` without a `ttsModel`, and pass `null` for the TTS platform. The configured `transcribe()` path replaces the audio-bearing user message with text before the inner agent runs; the assistant's reply is a normal text `ResultInterface`.

```php
$speechAgent = new SpeechAgent(
    agent: $innerAgent,
    configuration: new SpeechConfiguration(sttModel: 'whisper-1'),
    speechToTextPlatform: $openai,
    textToSpeechPlatform: null,
);
```

### TTS-only

Configure `ttsModel` without an `sttModel`, and pass `null` for the STT platform. The inner agent sees a normal text user message and its response is synthesised as audio.

```php
$speechAgent = new SpeechAgent(
    agent: $innerAgent,
    configuration: new SpeechConfiguration(
        ttsModel: 'tts-1',
        ttsOptions: ['voice' => 'alloy'],
    ),
    speechToTextPlatform: null,
    textToSpeechPlatform: $openai,
);
```

### Full STT → agent → TTS

Provide both platforms and both models. `SpeechAgent` runs transcription first, passes the resulting text to the inner agent, and synthesises the assistant response last.

```php
$speechAgent = new SpeechAgent(
    agent: $innerAgent,
    configuration: new SpeechConfiguration(
        ttsModel: 'tts-1',
        ttsOptions: ['voice' => 'alloy'],
        sttModel: 'whisper-1',
    ),
    speechToTextPlatform: $openai,
    textToSpeechPlatform: $openai,
);
```

To use another provider, pass its platform for STT or TTS. To archive transcripts for semantic search, combine this pipeline with the `store` skill.

## Working with `BinaryResult` artifacts

The relevant `BinaryResult` surface is `getMimeType()`, `getContent(): string`, `asFile(string $path): void`, `toBase64()`, and `toDataUri(?string $mimeType)`.

When TTS is enabled, `SpeechAgent::call()` returns `DeferredResult::getResult()` from the TTS platform, which is typically a `BinaryResult`. Persist or embed that artifact, for example:

```php
$binary->asFile('/var/audio/'.$messageId.'.mp3');
$dataUri = $binary->toDataUri('audio/mpeg');
```

`asFile()` writes the raw bytes for filesystem storage and throws `IOException` if the target directory is missing or not writable, or if writing fails. `toDataUri('audio/mpeg')` is suitable for embedding in an HTML response. You can also pipe `$binary->getContent()` into an HTTP response body without first writing a file.

Symfony AI does not provide chunked audio streaming out of the box; persist the artifact, then serve it via your HTTP stack.

## See also

- `platform` skill : bridges for OpenAI Whisper, Deepgram, ElevenLabs
- `agent` skill : `SpeechAgent`, `SpeechConfiguration`, custom processors
- `store` skill : if archiving transcripts for semantic search
