# AI Bundle : Security Reference

> **Source of truth**: `https://github.com/symfony/ai/tree/main/src/ai-bundle/src/Security/Attribute/IsGrantedTool.php` and `…/EventListener/IsGrantedToolAttributeListener.php`. Autoconfiguration registered in `AiBundle::loadExtension()` lines 368-374. Listener is wired in `config/services.php` lines 267-272 (`ai.security.is_granted_attribute_listener`).

The bundle ships **one** security hook: `#[IsGrantedTool]`. It is a PHP attribute on tool methods (or classes) that consults Symfony's `AuthorizationCheckerInterface` just before the tool is invoked.

## Contents

- Real namespace : `Symfony\AI\AiBundle\Security\Attribute`
- `throwOnDenied` does NOT exist
- Example
- Symfony Security voter integration
- Required dependency
- Async / Messenger context
- Audit trail

## Real namespace : `Symfony\AI\AiBundle\Security\Attribute`

```php
namespace Symfony\AI\AiBundle\Security\Attribute;   // <-- NOT Symfony\Component\Security\Http\Attribute

#[\Attribute(\Attribute::IS_REPEATABLE | \Attribute::TARGET_CLASS | \Attribute::TARGET_METHOD)]
final class IsGrantedTool
{
    public function __construct(
        public string|Expression $attribute,
        public array|string|Expression|\Closure|null $subject = null,
        public ?string $message = null,
        public ?int $exceptionCode = null,
    ) {}
}
```

Real parameters (no `throwOnDenied` : see below):

| Param | Type | Purpose |
| --- | --- | --- |
| `$attribute` | `string\|Expression` | Role, custom attribute string, or `ExpressionLanguage` expression |
| `$subject` | `array\|string\|Expression\|\Closure\|null` | Subject passed to voters; if `string`, it is looked up in the tool's arguments; `Closure` receives `($arguments, $tool)`; `Expression` is evaluated against `{ tool, args }` |
| `$message` | `string\|null` | Custom denial message |
| `$exceptionCode` | `int\|null` | Exception code; defaults to `403` |

The attribute is repeatable (`IS_REPEATABLE`) and can target both the tool class (`TARGET_CLASS`) and its invocable method (`TARGET_METHOD`). The listener merges class + method attributes and runs them all (lines 41-86).

## `throwOnDenied` does NOT exist

The audited previous skill mentioned `throwOnDenied: true`. The actual listener (`IsGrantedToolAttributeListener::__invoke()` lines 73-83) **always** throws `AccessDeniedException` on denial : there is no soft path. If you need the agent to receive a denial as a tool result, write a custom listener or wrap `AuthorizationCheckerInterface` instead.

There is also **no `throw_on_tool_denied` key** in `ai.agent.<name>` : `fault_tolerant_toolbox: true` (default) controls whether the agent keeps running when a tool call itself raises (not authorization), but `IsGrantedTool` denial throws before that wrapper engages.

## Example

```php
namespace App\AI;

use Symfony\AI\Agent\Toolbox\Attribute\AsTool;
use Symfony\AI\AiBundle\Security\Attribute\IsGrantedTool;
use Symfony\Component\ExpressionLanguage\Expression;

// #[AsTool] is TARGET_CLASS and IS_REPEATABLE: one attribute per exposed
// method, all of them on the class. #[IsGrantedTool] is TARGET_METHOD and
// stays where the check applies.
#[AsTool(name: 'delete_user', description: 'Delete a user by ID.', method: 'deleteUser')]
#[AsTool(name: 'view_user', description: 'View a user profile.', method: 'viewUser')]
final class AdminService
{
    #[IsGrantedTool('ROLE_ADMIN')]
    public function deleteUser(int $userId): string
    {
        return sprintf('User %d deleted.', $userId);
    }

    #[IsGrantedTool(
        attribute: new Expression("is_granted('ROLE_USER') and subject.isOwnedBy(user)"),
        subject: 'userId',
        message: 'You may only view your own profile.',
        exceptionCode: 403,
    )]
    public function viewUser(int $userId): array
    {
        return ['id' => $userId];
    }
}
```

When `$subject` is a string (`'userId'`), the listener requires the tool method to have a parameter named `userId`; the value of that argument becomes the subject. Missing keys throw `RuntimeException` (line 107). Closures receive `($arguments, $tool)` and may return any subject.

## Symfony Security voter integration

Standard voters are invoked via `AuthorizationCheckerInterface::isGranted($attribute, $subject)`. Use them as you would in any Symfony controller:

```php
namespace App\Security\Voter;

use Symfony\Component\Security\Core\Authentication\Token\TokenInterface;
use Symfony\Component\Security\Core\Authorization\Voter\Voter;

final class ToolVoter extends Voter
{
    protected function supports(string $attribute, mixed $subject): bool
    {
        return 'TOOL_DELETE_USER' === $attribute;
    }

    protected function voteOnAttribute(string $attribute, mixed $subject, TokenInterface $token): bool
    {
        return null !== $token->getUser();
    }
}
```

```text
#[IsGrantedTool(new Expression("is_granted('TOOL_DELETE_USER')"))]
public function deleteUser(int $userId): string { ... }
```

## Required dependency

The listener requires `symfony/security-core`. If it is not installed, `AiBundle::loadExtension()` lines 368-374 remove `ai.security.is_granted_attribute_listener` and replace `#[IsGrantedTool]` autoconfiguration with a closure that throws `InvalidArgumentException('Using #[IsGrantedTool] attribute requires additional dependencies. Try running "composer install symfony/security-core".')`. Add the package to your composer.json to enable gating.

## Async / Messenger context

The listener reads the current `AuthorizationCheckerInterface` from the container, which itself reads the `TokenStorage`. In Messenger handlers without an HTTP context, `getToken()` returns `null` and voters will deny unless you set a token first. The bundle does **not** propagate the HTTP token into Messenger envelopes; you must do it in your middleware.

The skill version that claims you can inject `#[Target] Security $security` into a tool method to bypass this is wrong: the listener runs **before** the tool method body, so injecting `Security` does not help you authorize the call.

## Audit trail

There is no built-in Monolog channel called `ai` shipped by the bundle. If you want to log denials, register a Monolog processor on your own channel or wrap the authorization checker. The data collector's profile (`Profiler\DataCollector::lateCollect()`) records every granted tool call (with arguments, result, latency) when `kernel.debug` is true; it does not record denials specifically.

## See also

- `references/config.md` : agent YAML
- `references/patterns.md` : full gated-tool example
- `references/gotchas.md` : async / messenger pitfalls
