# AI Bundle : Processors Reference

> **Source of truth**: `https://github.com/symfony/ai/tree/main/src/agent/src/Attribute/AsInputProcessor.php`, `…/AsOutputProcessor.php`. Autoconfiguration is registered in `AiBundle::loadExtension()` lines 341-358 and resolved at compile time by `ProcessorCompilerPass::process()`.

Processors transform `MessageBag` (input) and `ResultInterface` (output). They are **never** listed in YAML under `ai.agent.<name>.input_processors` / `ai.agent.<name>.output_processors`. They are auto-registered when:

1. A service implements `Symfony\AI\Agent\InputProcessorInterface` (or `OutputProcessorInterface`); OR
2. A class is annotated with `#[AsInputProcessor]` (or `#[AsOutputProcessor]`).

## Built-in processors (registered by the bundle)

The bundle registers these processors itself, not via attributes (see `AiBundle::processAgentConfig()` lines 1240-1410). Both are scoped to the agent they belong to (the `agent` tag on the processor matches `ai.agent.<name>`).

| Processor | Class | Tag / scope | Default priority |
| --- | --- | --- | --- |
| `ToolProcessor` (the toolbox executor) | `Symfony\AI\Agent\Toolbox\AgentProcessor` | `ai.agent.input_processor` + `ai.agent.output_processor` on the agent | `-10` |
| `SystemPromptInputProcessor` | `Symfony\AI\Agent\InputProcessor\SystemPromptInputProcessor` | `ai.agent.input_processor` (only when `ai.agent.<name>.prompt` is set) | `-30` |
| `MemoryInputProcessor` | `Symfony\AI\Agent\Memory\MemoryInputProcessor` | `ai.agent.input_processor` (only when `ai.agent.<name>.memory` is set) | `-40` |

Higher priority runs first on the input chain and last on the output chain (`ProcessorCompilerPass::process()` lines 64-66 sort descending). Priorities are integers; `0` is the default for unannotated custom processors.

The bundle does **not** register a `MemoryOutputProcessor` / `JsonExtractorOutputProcessor` / `ModelOverrideInputProcessor`. Those names come from training data and are **not present in this bundle**.

## Attributes (REAL namespaces : `Symfony\AI\Agent\Attribute`)

Source: `https://github.com/symfony/ai/tree/main/src/agent/src/Attribute/AsInputProcessor.php`:

```php
namespace Symfony\AI\Agent\Attribute;

#[\Attribute(\Attribute::TARGET_CLASS | \Attribute::IS_REPEATABLE)]
final class AsInputProcessor
{
    public function __construct(
        public readonly ?string $agent = null,   // service id of the target agent, null = all agents
        public readonly int $priority = 0,
    ) {}
}
```

`AsOutputProcessor` has the same constructor.

These attributes live in `Symfony\AI\Agent\Attribute`, **not** `Symfony\Component\DependencyInjection\Attribute`.

## Global custom processor (PHP)

```php
namespace App\AI;

use Symfony\AI\Agent\Attribute\AsInputProcessor;
use Symfony\AI\Agent\Input;
use Symfony\AI\Agent\InputProcessorInterface;
use Symfony\AI\Platform\Message\Message;

#[AsInputProcessor]   // applied to every agent; priority defaults to 0
final class TimestampInputProcessor implements InputProcessorInterface
{
    public function processInput(Input $input): void
    {
        $input->setMessageBag(
            $input->getMessageBag()->with(Message::forSystem('Current time: '.(new \DateTime())->format(\DateTime::ATOM))),
        );
    }
}
```

## Scoped custom processor (PHP)

```php
#[AsInputProcessor(agent: 'ai.agent.support', priority: 50)]
final class SupportContextProcessor implements InputProcessorInterface { ... }
```

`ProcessorCompilerPass` matches the `agent` tag against the service id. If you want to bind to a single agent that is itself a `MultiAgent` instance, use the full service id (`ai.agent.router`) : the compiler pass skips services whose class is `Symfony\AI\Agent\MultiAgent\MultiAgent` (line 30) but still binds processors tagged for that id.

## Interface-only registration (no attribute)

If you only need a global processor and want the attribute namespace to stay clean, you can drop `#[AsInputProcessor]` and rely on the interface autoconfiguration (`AiBundle::loadExtension()` lines 355-358):

```php
use Symfony\AI\Agent\Input;
use Symfony\AI\Agent\InputProcessorInterface;

final class RateLimitProcessor implements InputProcessorInterface
{
    public function processInput(Input $input): void
    {
        // mutate $input via setModel(), setMessageBag(), setOptions()
    }
}
```

Any class implementing `InputProcessorInterface` (or `OutputProcessorInterface`) is automatically tagged `ai.agent.input_processor` (or `…output_processor`) with `tagged_by: 'interface'` and `priority: 0`. The compiler pass dedupes interface-tagged services so a class with both an attribute and the interface gets a single tag (lines 38-40).

## Disabling a processor

There is no `remove`/`disable` key. Two ways to opt out:

1. **Skip the autoconfiguration** by marking the class `final` but registering it manually with `autoconfigure: false` in `services.yaml` and not tagging it.
2. **Use the `agent:` filter** on the attribute so it never reaches the agent you care about.

Built-in processors (`SystemPromptInputProcessor`, `MemoryInputProcessor`, `ToolProcessor`) are not optional individually : they are created only when the corresponding YAML key (`prompt:`, `memory:`, `tools.enabled:`) is set, so omitting those keys is how you opt out.

## See also

- `references/config.md` : how `ai.agent.<name>.prompt` / `memory` / `tools.enabled` wire built-in processors
- `references/security.md` : `IsGrantedToolAttributeListener` is registered as an event listener, not a processor
- `references/gotchas.md` : processor ordering pitfalls
