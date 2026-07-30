---
name: mcp-bundle
description: 'Use when building an MCP (Model Context Protocol) server inside a Symfony application : registering tools, prompts, or resources via the official MCP SDK, serving over HTTP or STDIO. Do NOT trigger when the goal is to expose a running Symfony app to an external AI assistant for inspection/debugging : use the `mate` skill for that. Triggers on `#[McpTool]`, `#[McpPrompt]`, `#[McpResource]`, `#[McpResourceTemplate]`, `#[AsMcpApp]`, `#[AsMcpAppTool]`, `mcp:server`, `debug:mcp`, `Symfony\AI\McpBundle\`.'
license: MIT
metadata:
  author: MadCat34
  email: madcat34@gmail.com
  url: https://github.com/MadCat34
  version: "0.13.0"
---

# MCP Bundle

> ⚠️ **Symfony AI is experimental** : APIs may break between releases. Always check `UPGRADE.md` in the [symfony/ai monorepo](https://github.com/symfony/ai) before upgrading. The bundle itself is also marked experimental in the source `README.md` and not covered by Symfony's Backward Compatibility Promise.

Build an MCP (Model Context Protocol) server inside your Symfony application. The bundle WRAPS the official [`mcp/sdk`](https://github.com/modelcontextprotocol/php-sdk) : `#[McpTool]`, `#[McpPrompt]`, `#[McpResource]`, `#[McpResourceTemplate]` come from the SDK namespace `Mcp\Capability\Attribute\`, not from this bundle. The bundle adds Symfony service auto-discovery (replacing the SDK's file-based discovery), container compilation of handlers, an HTTP controller, a STDIO console command, a debug command, a Profiler data collector, and the `#[AsMcpApp]` / `#[AsMcpAppTool]` UI-resource layer.

Source of truth: `https://github.com/symfony/ai/tree/main/src/mcp-bundle/`. Root namespace: `Symfony\AI\McpBundle\` (PSR-4 prefix from `composer.json`).

## When to use MCP Bundle vs Mate

These two skills MUST NOT be used together; their descriptions contain mutually-exclusive trigger clauses.

Use **MCP Bundle** when:

- You want to expose YOUR app's domain to external agents (Claude Code, Cursor, MCP-compatible editors) as MCP tools, prompts, or resources.
- You are building a product with an MCP integration.
- You need HTTP transport (`/_mcp`) and/or STDIO transport (`mcp:server`).

Use **Mate** (see `mate` skill) when:

- You want the CURRENT AI assistant to read YOUR app's logs / profiler / container / source code.
- It is dev-only, never deployed in production.

## Installation

```bash
composer require symfony/mcp-bundle
```

The bundle pulls `mcp/sdk ^0.7` as a hard dependency. `mcp/sdk` is the source of every attribute, every transport, and the `Mcp\Server` runtime : the bundle only adds Symfony glue (autoconfiguration, compiler pass, controller, command, profiler, route loader, DI container).

For UI-resource MCP Apps (the `#[AsMcpApp]` flow), also install Twig:

```bash
composer require symfony/twig-bundle
```

For the Profiler panel to show MCP capabilities on every request: keep `kernel.debug = true` : the data collector is registered conditionally on that flag (`McpBundle::loadExtension` lines 184-192).

## Quick reference

A tool : use the SDK attribute, not a bundle attribute:

```php
namespace App\MCP;

use Mcp\Capability\Attribute\McpTool;

class WeatherService
{
    #[McpTool(name: 'get_weather', description: 'Get current weather for a city.')]
    public function getWeather(string $city): array
    {
        return ['city' => $city, 'temp' => 22, 'sky' => 'sunny'];
    }
}
```

Make sure the class is a registered service with autoconfiguration enabled (the default in `config/services.yaml`). `#[McpTool]` works on a method OR on a class with `__invoke()` (McpBundle's autoconfig in `registerMcpAttributes` enforces this; a class-level attribute without `__invoke()` throws `LogicException`).

`config/packages/mcp.yaml`:

```yaml
mcp:
    app: 'weather-mcp'                      # server name (default: "app")
    version: '1.0.0'
    description: 'Weather tools for the agent'
    pagination_limit: 50                   # default 50
    instructions: 'Use the tools in metric units.'
    client_transports:
        stdio: true                        # enables `mcp:server` command
        http:  true                        # enables `/_mcp` HTTP route
    http:
        path: '/_mcp'                      # default; controller only registered if http=true
        allowed_hosts: ~                   # null=SDK default (localhost only), list, or false
        session:
            store: 'file'                  # file|memory|cache|framework
            directory: '%kernel.cache_dir%/mcp-sessions'
            cache_pool: 'cache.mcp.sessions'
            prefix: 'mcp-'
            ttl: 3600
    apps:
        enabled: ~                         # null=auto (true if at least one #[AsMcpApp]), true, or false
```

Routes config (`config/routes.yaml`):

```yaml
mcp:
    resource: .
    type: mcp
```

The bundle's `RouteLoader` only adds a route when `client_transports.http` is true (`RouteLoader::load`). It registers one route `_mcp_endpoint` at `mcp.http.path` (default `/_mcp`) accepting GET, POST, DELETE, OPTIONS, dispatched to `mcp.server.controller::handle`.

## What the bundle does to your classes

The autoconfiguration + compiler pass flow replaces the SDK's file-based discovery with container-driven discovery:

1. `McpBundle::loadExtension` calls `registerMcpAttributes()`, which registers attribute autoconfiguration for the four SDK attributes (`Mcp\Capability\Attribute\McpTool`, `McpPrompt`, `McpResource`, `McpResourceTemplate`). Each autoconfig callback adds a tag (`mcp.tool`, `mcp.prompt`, `mcp.resource`, `mcp.resource_template`) carrying the method name (or `__invoke` for class-level attributes).
2. `#[AsMcpApp]` autoconfiguration adds the tag `mcp.app`.
3. At compile time, `McpAppPass` (priority 10) walks services tagged `mcp.app`, registers the UI resource + linked tool on the `Mcp\Server\Builder`, tags the service `mcp.tool` / `mcp.resource` (template-based apps share a single `McpAppResourceRenderer`), and stores the `toolTemplates` map in the `mcp.apps.tool_templates` parameter.
4. `McpPass` then walks services tagged `mcp.tool` / `mcp.prompt` / `mcp.resource` / `mcp.resource_template`, reads the SDK attribute, generates the input schema with `Mcp\Capability\Discovery\SchemaGenerator`, and calls the matching `Builder::add*()` method. It also builds the service locator the SDK `ReferenceHandler` resolves handler instances from at runtime : so element services are only instantiated when actually invoked.
5. The default service config (`App\:` with `autoconfigure: true`) is sufficient. No extra wiring required.

## Transports

### HTTP (streamable)

Enabled when `mcp.client_transports.http: true`. The bundle's `McpController` constructs an SDK `Mcp\Server\Transport\StreamableHttpTransport` per request (`McpController::handle`), runs the server with it, and adapts the PSR-7 response back to a Symfony `Response` (`httpFoundationFactory->createResponse`). SSE responses (`text/event-stream`) are returned as streamed responses.

```bash
curl -X POST http://localhost:8000/_mcp \
     -H 'Content-Type: application/json' \
     -H 'Accept: application/json, text/event-stream' \
     -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"curl","version":"0"}}}'
```

DNS-rebinding protection: the SDK's `StreamableHttpTransport` ships a `DnsRebindingProtectionMiddleware` enabled by default (localhost only). The bundle's `MiddlewareFactory` keeps that default, restricts it to a list of hostnames, or disables it entirely depending on `mcp.http.allowed_hosts` (null | list<string> | false).

Session store: HTTP transport requires a session store (`mcp.session.store`). The bundle configures one of four backends based on `mcp.http.session.store`:

- `file` (default) : `Mcp\Server\Session\FileSessionStore`, writing under `mcp.http.session.directory`.
- `memory` : `Mcp\Server\Session\InMemorySessionStore`, in-process only.
- `cache` : `Mcp\Server\Session\Psr16SessionStore`, wrapping the configured PSR-16 pool (a `cache.mcp.sessions` pool wrapping `cache.app` is auto-created when missing).
- `framework` : `Symfony\AI\McpBundle\Session\FrameworkSessionStore`, wrapping Symfony's `SessionHandlerInterface` (lazy `gc()`, expiry enforced on `read()`).

For multi-process deployments (FrankenPHP, Roadrunner) or containers with ephemeral filesystems, switch from `file` to `cache` (with a shared Redis pool) or `framework` (with a shared session handler).

### STDIO

Enabled when `mcp.client_transports.stdio: true`. The bundle registers `mcp:server` (`Command\McpCommand`):

```bash
php bin/console mcp:server
```

The command constructs an SDK `Mcp\Server\Transport\StdioTransport` and runs the server (`McpCommand::execute`). It is intended to be launched by an MCP-compatible client (Claude Code, Cursor, etc.) : the client spawns the process and pipes JSON-RPC over stdin/stdout.

The HTTP and STDIO transports are independent. A session id from one is meaningless to the other. STDIO does not use the `mcp.session.store` service : sessions live in the SDK transport itself.

## Attribute catalogue (from the SDK)

| Attribute | Namespace | Target | Required args |
|---|---|---|---|
| `#[McpTool]` | `Mcp\Capability\Attribute\McpTool` | method or class (`__invoke`) | none : all parameters optional, schema derived from method signature |
| `#[McpPrompt]` | `Mcp\Capability\Attribute\McpPrompt` | method or class (`__invoke`) | none |
| `#[McpResource]` | `Mcp\Capability\Attribute\McpResource` | method or class (`__invoke`) | `string $uri` (only required arg) |
| `#[McpResourceTemplate]` | `Mcp\Capability\Attribute\McpResourceTemplate` | method or class (`__invoke`) | `string $uriTemplate` (only required arg) |

Plus the bundle's own UI-resource attributes:

| Attribute | Namespace | Target | Purpose |
|---|---|---|---|
| `#[AsMcpApp]` | `Symfony\AI\McpBundle\Attribute\AsMcpApp` | class | Register an MCP App (UI resource + linked tool) |
| `#[AsMcpAppTool]` | `Symfony\AI\McpBundle\Attribute\AsMcpAppTool` | method | Register an additional tool on an `#[AsMcpApp]` class |

The bundle's autoconfiguration `registerMcpAttributes()` (in `McpBundle.php`) tags every method that carries an SDK attribute with `mcp.tool` / `mcp.prompt` / `mcp.resource` / `mcp.resource_template`, then `McpPass` (compiler pass) reflects the tagged methods and calls `addTool()` / `addPrompt()` / `addResource()` / `addResourceTemplate()` on the SDK `Mcp\Server\Builder`.

Real signatures (taken from `Mcp\Capability\Attribute\`):

```php
use Mcp\Capability\Attribute\McpTool;
use Mcp\Capability\Attribute\McpPrompt;
use Mcp\Capability\Attribute\McpResource;
use Mcp\Capability\Attribute\McpResourceTemplate;

#[McpTool(name: 'greet', description: 'Greet a user.')]
public function greet(string $name): string { /* ... */ }

#[McpPrompt(name: 'code_review', description: 'Prompt the agent to review code.')]
public function codeReview(string $language): array { /* ... */ }

#[McpResource(uri: 'docs://readme', mimeType: 'text/markdown')]
public function readme(): string { /* ... */ }

#[McpResourceTemplate(uriTemplate: 'docs://{slug}', mimeType: 'text/markdown')]
public function doc(string $slug): string { /* ... */ }
```

Note: `McpTool` has no `parameters:` argument; `McpPrompt` has no `arguments:` argument. Both are derived from the method signature. `McpResource` requires only `uri`; `McpResourceTemplate` requires only `uriTemplate`.

## Capability discovery

List what is actually registered : useful to verify a class was picked up:

```bash
php bin/console debug:mcp
php bin/console debug:mcp get_weather   # details (input/output schema, handler, ...)
```

`debug:mcp` (in `Command\DebugCommand`) triggers `Mcp\Server\Builder::build()` to populate the registry, then prints Tools / Prompts / Resources / Resource Templates tables with their handlers. An empty result prints a warning pointing you at "make sure the classes are registered as services with autoconfiguration enabled".

The `Symfony\AI\McpBundle\Profiler\DataCollector` provides the same view in the Web Profiler panel. It is registered only when `kernel.debug = true` AND at least one of `client_transports.{stdio,http}` is true. It implements `LateDataCollectorInterface` so the registry is built (and the server is `build()`-ed) on every profiled request, not only on requests actually serving the MCP endpoint.

## Key gotchas

- **Root namespace is `Symfony\AI\McpBundle\`, not `Symfony\Mcp\Bundle\`.** Anything `use Symfony\Mcp\Bundle\...` is wrong : that namespace does not exist.
- **The four capability attributes come from the SDK (`Mcp\Capability\Attribute\`), not the bundle.** Their constructors are permissive: `McpTool`/`McpPrompt` take all-optional parameters; `McpResource`/`McpResourceTemplate` only require `uri` / `uriTemplate`. There is no `parameters:` or `arguments:` argument.
- **The bundle does NOT define `McpServer`, `HttpTransport`, or `StdioTransport` classes.** `Mcp\Server` is built via `Mcp\Server::builder()` and the bundle uses the SDK's `StreamableHttpTransport` / `StdioTransport`.
- **Default HTTP path is `/_mcp`, not `/mcp`.** (`config/options.php` line 53.)
- **STDIO command is `mcp:server`, not `mcp:serve`.** (Constant on `#[AsCommand('mcp:server', ...)]` in `Command\McpCommand`.)
- **Transport mismatch.** HTTP clients cannot talk to STDIO servers and vice-versa. Pick exactly one of `mcp.client_transports.http` / `stdio` (or both : the controller and command are registered independently).
- **No bundle-level `McpException` class.** The bundle exposes `Symfony\AI\McpBundle\Exception\ExceptionInterface` (interface) and `Symfony\AI\McpBundle\Exception\LogicException` (extends `\LogicException`). JSON-RPC errors are SDK types at `Mcp\Schema\JsonRpc\Error` with constants like `INVALID_PARAMS = -32602`.
- **Class-level attribute without `__invoke()` throws `LogicException`.** The `registerMcpAttributes` autoconfig requires `__invoke()` when the attribute is on a class. Move the attribute to a method or add `__invoke()`.
- **Service registration is mandatory.** A class carrying `#[McpTool]` must also be a registered (autoconfigured) service, otherwise it never reaches `McpPass` and `debug:mcp` shows "No MCP capabilities are registered".
- **Resource templates** are still informational (the SDK's `addResourceTemplate` is for `resources/templates/list`). Treat them as discovery-only.
- **DNS-rebinding protection is ON by default** (localhost only). Set `mcp.http.allowed_hosts` to a list or to `false` for a public HTTP server; otherwise requests from a public host will be rejected at the middleware layer.

## Common tasks

- **HTTP server with one tool**: see `references/patterns.md#http-server-with-one-tool`.
- **STDIO server for editor integration**: see `references/patterns.md#stdio-server-for-editor-integration`.
- **Prompt + tool combination**: see `references/patterns.md#prompt-tool-combination`.
- **MCP App (UI resource)**: see `references/patterns.md#mcp-app-ui-resource-asmcpapp`.
- **Class has no capabilities**: see `references/gotchas.md` #12 ("Service registration is mandatory") and `references/patterns.md` "Diagnostic recipes".

## References

- **Full API surface, attribute signatures, config tree**: [references/api.md](references/api.md)
- **Patterns (HTTP tool, STDIO server, prompts, MCP Apps)**: [references/patterns.md](references/patterns.md)
- **Gotchas (transport mismatch, JSON-RPC errors, auth, lifecycle)**: [references/gotchas.md](references/gotchas.md)

## See also

- `mate` skill : for the inverse use case (assistant reads your app)
- `ai-bundle` skill : for general Symfony AI integration
- `agent` skill : `#[AsTool]` for AI tool-calling (not MCP, different concept)
