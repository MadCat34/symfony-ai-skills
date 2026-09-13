---
name: mcp-bundle
description: 'Use when building an MCP (Model Context Protocol) server inside a Symfony application : registering tools, prompts, or resources via the official MCP SDK, serving over HTTP or STDIO, or consuming remote MCP servers as a client. Do NOT trigger when the goal is to expose a running Symfony app to an external AI assistant for inspection/debugging : use the `mate` skill for that. Triggers on `#[McpTool]`, `#[McpPrompt]`, `#[McpResource]`, `#[McpResourceTemplate]`, `#[AsMcpApp]`, `#[AsMcpAppTool]`, `mcp:server`, `debug:mcp`, `McpClientInterface`, `Symfony\AI\McpBundle\`.'
license: MIT
metadata:
  author: Romain Bastide <madcat34@gmail.com>
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
- You need HTTP transport (`/mcp/<name>`) and/or STDIO transport (`mcp:server`).

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

For the Profiler panel to show MCP capabilities on every request: keep `kernel.debug = true` : the data collector is registered conditionally on that flag (in `McpBundle::configureClient()`, lines 184-192, called from `loadExtension()`).

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

The bundle supports several MCP servers per application. Every server-related option lives under a named entry in `mcp.servers`, and **capabilities are not exposed automatically** : each server declares what it exposes via a required `registry` key (`['*']` = everything of that kind).

`config/packages/mcp.yaml`:

```yaml
mcp:
    servers:
        weather:
            name: 'weather-mcp'                 # advertised name (default: the config key, "weather")
            version: '1.0.0'
            description: 'Weather tools for the agent'
            pagination_limit: 50                # default 50
            instructions: 'Use the tools in metric units.'
            transports:
                stdio: false                    # enables `mcp:server weather`
                http: true                      # default true; enables the HTTP route
            http:
                path: '/mcp/weather'            # default: "/mcp/<name>"
                allowed_hosts: ~                # null=SDK default (localhost only), list, or false
            session:
                store: 'file'                   # file|memory|cache|framework, default "file"
                directory: '%kernel.cache_dir%/mcp-sessions/weather'
                cache_pool: 'cache.mcp.sessions'
                prefix: 'mcp-weather-'
                ttl: 3600
            registry: ['App\Mcp\Weather\']      # required: what this server exposes
```

`registry` accepts either one list covering every kind (tools, prompts, resources, resource templates, apps), or a map narrowing each kind separately:

```yaml
mcp:
    servers:
        public:
            http: { path: /mcp/public }
            registry:
                tools: ['App\Mcp\Public\']
                resources: ['*']
        internal:
            http: { path: /mcp/internal }
            registry: '*'                        # everything of every kind
```

Entries match a service id, an FQCN, or a namespace prefix (trailing `\`). A pattern matching **no service at all** on its server is a compile-time error (almost always a typo). A service carrying an MCP attribute that no server's registry matches is simply not exposed — `debug:mcp` reports it under "Not exposed by any server".

Routes config (`config/routes.yaml`) is unchanged:

```yaml
mcp:
    resource: .
    type: mcp
```

The bundle's `RouteLoader` adds one route per server that has `transports.http: true`, named `_mcp_endpoint_<name>`, at `http.path` (default `/mcp/<name>` — always derived from the server name, so adding a second server never moves an existing endpoint), dispatched to `mcp.server.<name>.controller::handle`.

## What the bundle does to your classes

The autoconfiguration + compiler pass flow replaces the SDK's file-based discovery with container-driven discovery:

1. `McpBundle::loadExtension` calls `registerMcpAttributes()`, which registers attribute autoconfiguration for the four SDK attributes (`Mcp\Capability\Attribute\McpTool`, `McpPrompt`, `McpResource`, `McpResourceTemplate`). Each autoconfig callback adds a tag (`mcp.tool`, `mcp.prompt`, `mcp.resource`, `mcp.resource_template`) carrying the method name (or `__invoke` for class-level attributes).
2. `#[AsMcpApp]` autoconfiguration adds the tag `mcp.app`.
3. At compile time, `McpAppPass` (priority 10) walks services tagged `mcp.app`, registers the UI resource + linked tool on the `Mcp\Server\Builder`, tags the service `mcp.tool` / `mcp.resource` (template-based apps share a single `McpAppResourceRenderer`), and stores the `toolTemplates` map in the `mcp.apps.tool_templates` parameter.
4. `McpPass` then walks services tagged `mcp.tool` / `mcp.prompt` / `mcp.resource` / `mcp.resource_template`, reads the SDK attribute, generates the input schema with `Mcp\Capability\Discovery\SchemaGenerator`, and calls the matching `Builder::add*()` method. It also builds the service locator the SDK `ReferenceHandler` resolves handler instances from at runtime : so element services are only instantiated when actually invoked.
5. The default service config (`App\:` with `autoconfigure: true`) is sufficient. No extra wiring required.

## Transports

Each server's transports are configured independently under `mcp.servers.<name>.transports`.

### HTTP (streamable)

Enabled when `transports.http: true` (default). The bundle's per-server `McpController` (service id `mcp.server.<name>.controller`) constructs an SDK `Mcp\Server\Transport\StreamableHttpTransport` per request, runs that server with it, and adapts the PSR-7 response back to a Symfony `Response`. SSE responses (`text/event-stream`) are returned as streamed responses.

```bash
curl -X POST http://localhost:8000/mcp/weather \
     -H 'Content-Type: application/json' \
     -H 'Accept: application/json, text/event-stream' \
     -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"curl","version":"0"}}}'
```

DNS-rebinding protection: the SDK's `StreamableHttpTransport` ships a `DnsRebindingProtectionMiddleware` enabled by default (localhost only). The bundle's per-server `MiddlewareFactory` keeps that default, restricts it to a list of hostnames, or disables it entirely depending on `mcp.servers.<name>.http.allowed_hosts` (null | list<string> | false).

Session store: HTTP transport requires a session store (`mcp.server.<name>.session.store`), isolated per server by default (`%kernel.cache_dir%/mcp-sessions/<name>` and the `mcp-<name>-` cache prefix). Two servers resolving to the **same** storage is rejected at compile time : session ids are not namespaced by server, so a shared store would let a session minted on one server be accepted by another. The bundle configures one of four backends based on `mcp.servers.<name>.session.store`:

- `file` (default) : `Mcp\Server\Session\FileSessionStore`, writing under `session.directory`.
- `memory` : `Mcp\Server\Session\InMemorySessionStore`, in-process only.
- `cache` : `Mcp\Server\Session\Psr16SessionStore`, wrapping the configured PSR-16 pool (a `cache.mcp.sessions` pool wrapping `cache.app` is auto-created when missing).
- `framework` : `Symfony\AI\McpBundle\Session\FrameworkSessionStore`, wrapping Symfony's `SessionHandlerInterface` (lazy `gc()`, expiry enforced on `read()`).

For multi-process deployments (FrankenPHP, Roadrunner) or containers with ephemeral filesystems, switch from `file` to `cache` (with a shared Redis pool) or `framework` (with a shared session handler).

Every HTTP server also answers the 2026-07-28 revision automatically alongside the handshake era, with no config change. That revision drops server-initiated requests : `$gateway->sample()`/`listRoots()` inside a handler now fails for clients speaking it. See `references/gotchas.md` #15.

### STDIO

Enabled per server via `transports.stdio: true`. The bundle registers a single `mcp:server` command (`Command\McpCommand`) shared by every STDIO-enabled server, taking the server name as an optional argument:

```bash
php bin/console mcp:server weather
```

The argument is required as soon as more than one server enables STDIO (one process can only serve one of them — the transport owns the process' STDIN/STDOUT); with exactly one STDIO-enabled server it can be omitted. The command constructs an SDK `Mcp\Server\Transport\StdioTransport` and runs the named server with it. It is intended to be launched by an MCP-compatible client (Claude Code, Cursor, etc.) : the client spawns the process and pipes JSON-RPC over stdin/stdout.

The HTTP and STDIO transports are independent. A session id from one is meaningless to the other. STDIO does not use the session store service : sessions live in the SDK transport itself.

## MCP clients (consuming remote MCP servers)

The bundle can also act as a **client**, reaching MCP servers outside your application (a third-party MCP server, or another instance of your own app). This is a separate axis from `mcp.servers` : both can be configured in the same application, but "server" (exposing your app to others) and "client" (your app reaching another server) are unrelated roles.

```yaml
mcp:
    clients:
        research:                              # client name — the container alias
            client_info:
                name: 'my-app'                 # defaults to the config key
            forward_server_logs: true          # default true; forwards remote log notifications to the "mcp" channel
            servers:
                docs:                           # one client can reach several remote servers
                    transport: http
                    url: 'https://docs.example.com/mcp'
                    headers:
                        Authorization: 'Bearer %env(DOCS_MCP_TOKEN)%'
                filesystem:
                    transport: stdio
                    command: ['npx', '-y', '@modelcontextprotocol/server-filesystem', '/tmp']
```

Each client is registered as `mcp.client.<name>` (`Symfony\AI\McpBundle\Client\McpClient`, implementing `McpClientInterface`) and autowired **under its own name**, not `<name>Client`:

```php
final class OneWay
{
    public function __construct(
        private McpClientInterface $research,   // matches the "research" client by argument name
    ) {
    }
}

// or, when the argument is named for its role rather than for the client:
final class TheOtherWay
{
    public function __construct(
        #[Target('research')] private McpClientInterface $client,
    ) {
    }
}
```

When exactly **one** client is configured, a plain `McpClientInterface` type hint (no name match needed) also resolves to it. `transport: stdio` requires `command`; `transport: http` requires `url`; mixing stdio-only and http-only options on the wrong transport is a compile-time error. `debug:mcp --client=research` connects and lists what the remote server(s) advertise; `debug:mcp --clients` lists configured clients without connecting.

## Attribute catalogue and capability discovery

The four SDK capability attributes (`#[McpTool]`, `#[McpPrompt]`, `#[McpResource]`, `#[McpResourceTemplate]`) plus the bundle's own `#[AsMcpApp]` / `#[AsMcpAppTool]` : full signatures, required args, and a runnable example : are in **[references/api.md](references/api.md)**. Read it when writing a new capability class or checking whether an argument name (`parameters:`, `arguments:`) actually exists.

To verify what got picked up, `php bin/console debug:mcp` (optionally `--server=<name>`, `--client=<name>`, `--clients`) lists every registered tool/prompt/resource with its handler, plus a "Not exposed by any server" section — see `references/api.md` for the full command reference and the Profiler data collector it shares a data path with.

## Key gotchas

The 17 gotchas below have real fixes with source citations in **[references/gotchas.md](references/gotchas.md)** — read it whenever a recipe misbehaves or before touching transports, sessions, or the registry. Headline list, in order: transport mismatch (STDIO vs HTTP), default HTTP path is always `/mcp/<name>`, STDIO command is `mcp:server` not `mcp:serve`, capability negotiation is automatic (don't hand-roll `initialize`), JSON-RPC errors not Symfony HTTP exceptions, STDIO stdout pollution, DNS-rebinding protection defaults, auth via reverse proxy, resource-template discovery-only limitation, STDIO lifecycle/SIGTERM, class-level attribute needs `__invoke()`, service registration + registry match are both mandatory, default session store is `file`, MCP Apps need the `apps` registry kind, the 2026-07-28 revision drops server-initiated requests, resource-subscription notifications need an explicit `subscriptions.bus`, and the bundle is experimental.

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
