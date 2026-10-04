---
name: symfony-mcp-bundle
description: 'Use when a Symfony application must expose its own tools, prompts or resources to external AI clients as an MCP (Model Context Protocol) server over HTTP or STDIO, or call remote MCP servers from its services. Triggers on `#[McpTool]`, `#[McpPrompt]`, `#[McpResource]`, `#[AsMcpApp]`, `mcp:server`, `debug:mcp`, `McpClientInterface`. Not for letting a coding assistant debug the running app (`symfony-ai-mate`) or giving an agent remote MCP tools (`symfony-ai-bundle`).'
license: MIT
metadata:
  author: Romain Bastide <madcat34@gmail.com>
  url: https://github.com/MadCat34
  version: 0.14.1
  tags: symfony, php, mcp, model-context-protocol, mcp-server, mcp-client, ai-tools, symfony-bundle
---

# Symfony MCP Bundle

## Purpose

Run MCP (Model Context Protocol) servers inside a Symfony application, and
reach remote MCP servers as a client. The bundle wraps the official
[`mcp/sdk`](https://github.com/modelcontextprotocol/php-sdk): `#[McpTool]`,
`#[McpPrompt]`, `#[McpResource]` and `#[McpResourceTemplate]` come from the SDK
namespace `Mcp\Capability\Attribute\`. The bundle adds service-based discovery,
an HTTP controller, a STDIO command, `debug:mcp`, a Profiler collector, and the
`#[AsMcpApp]` / `#[AsMcpAppTool]` UI-resource layer. Root namespace:
`Symfony\AI\McpBundle\`.

## When to use

- Exposing the application's own domain to external agents (Claude Code,
  Cursor, MCP-compatible editors, hosted agents) as MCP tools, prompts or resources.
- Shipping a product feature with an MCP integration, over HTTP
  (`/mcp/<name>`) or STDIO (`mcp:server`).
- Serving several MCP servers from one application, each with its own registry.
- Calling a remote MCP server from a Symfony service (`mcp.clients`).

## When not to use

- Letting the current coding assistant read the running application's logs,
  profiler or container in development: use `symfony-ai-mate`. The two must not
  be used together.
- Giving an AI agent the tools of a remote MCP server: use the `mcp_server` tool
  entry of `symfony-ai-bundle` (it reuses the connection declared under `mcp.clients`).
- `#[AsTool]` tools for an agent's tool-calling loop: use `symfony-ai-agent`;
  that is a different concept from MCP.

## Prerequisites

Symfony 7.3+ or 8.x with FrameworkBundle, and the bundle, which pulls
`mcp/sdk ^0.8.1` (the source of every attribute, transport and the
`Mcp\Server` runtime):

```bash
composer require symfony/mcp-bundle
composer require symfony/twig-bundle   # only for template-based MCP Apps (#[AsMcpApp])
```

Classes carrying MCP attributes must be services with autoconfiguration
(the default `App\:` resource in `config/services.yaml`). The Profiler panel
only exists when `kernel.debug` is true.

## Examples

A tool, written with the SDK attribute:

```php
namespace App\Mcp\Weather;

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

`config/packages/mcp.yaml`: every server-related option lives under a named
entry in `mcp.servers`, and **nothing is exposed until the server's `registry`
lists it** (`'*'` = everything of that kind):

```yaml
mcp:
    servers:
        weather:
            name: 'weather-mcp'                 # advertised name (default: the config key)
            version: '1.0.0'
            instructions: 'Use the tools in metric units.'
            transports:
                stdio: false                    # true enables `mcp:server weather`
                http: true                      # default true; enables the HTTP route
            http:
                path: '/mcp/weather'            # default: "/mcp/<name>"
                allowed_hosts: ~                # null = SDK default (localhost only), list, or false
            session:
                store: 'file'                   # file|memory|cache|framework, default "file"
            registry: ['App\Mcp\Weather\']      # required: what this server exposes
```

`registry` takes one list for every kind, or a map per kind
(`tools`, `prompts`, `resources`, `resource_templates`, `apps`). Entries match a
service id, an FQCN, or a namespace prefix ending in `\`.

`config/routes.yaml` loads one route per HTTP-enabled server
(`_mcp_endpoint_<name>`):

```yaml
mcp:
    resource: .
    type: mcp
```

## Transports

- **HTTP (streamable)**, on by default: `mcp.server.<name>.controller` builds the
  SDK `StreamableHttpTransport` per request; SSE responses are streamed. The
  SDK's DNS-rebinding protection allows localhost only unless
  `http.allowed_hosts` lists hosts (or is `false`). Sessions use the server's
  store, isolated per server by default (`%kernel.cache_dir%/mcp-sessions/<name>`).
- **STDIO**, opt-in with `transports.stdio: true`: the client (Claude Code,
  Cursor, …) spawns `php bin/console mcp:server <name>` and pipes JSON-RPC over
  stdin/stdout. One process serves one server; the name can be omitted only when
  a single server enables STDIO.
- **Client side**: `mcp.clients.<name>.servers.<server>` declares remote servers
  (`transport: http` + `url`, or `transport: stdio` + `command`). Each client is
  `mcp.client.<name>`, autowired as `McpClientInterface $<name>` or with
  `#[Target('<name>')]`.

## Key gotchas

- **Registry and service registration are both mandatory.** A class with an MCP
  attribute that is not a service, or that no server's `registry` matches, is
  not exposed; `debug:mcp` lists the latter under "Not exposed by any server".
- **The STDIO command is `mcp:server`, not `mcp:serve`.**
- **Nothing may write to stdout under STDIO.** `echo`, `var_dump`, or a Monolog
  handler on stdout corrupts the JSON-RPC stream; log to stderr.
- **Tool errors are JSON-RPC errors.** The SDK converts a thrown exception into
  a JSON-RPC error envelope; Symfony HTTP exceptions and error pages do not
  reach the client.
- **The default session store is `file`.** On several processes (FrankenPHP,
  RoadRunner) or an ephemeral filesystem, switch to `cache` (shared pool) or
  `framework` (shared session handler).
- **Resource templates are listed, not routed.** `#[McpResourceTemplate]`
  appears in `resources/templates/list`, but reading `users://{id}` still needs
  a handler that parses the URI.
- **Resource-subscription notifications are off by default**
  (`mcp.servers.<name>.subscriptions.bus: none`).

## Troubleshooting

| Error | Cause | Fix |
| --- | --- | --- |
| `The class "…" uses #[Mcp\Capability\Attribute\McpTool] as a class-level attribute but has no "__invoke()" method. …` (same for the other MCP attributes) | A class-level MCP attribute needs `__invoke()`. | Add `__invoke()`, or move the attribute to a method. |
| `The following MCP element patterns do not match any registered service: "…". …` | A `registry` entry has a typo, or the class is not a service. | Fix the pattern; make sure the class is a registered, autoconfigured service. |
| `An MCP server must expose at least one of "tools", "prompts", "resources", "resource_templates" or "apps". Use "*" to expose everything.` | The server has no `registry`. | Add `registry: '*'` or explicit entries. |
| `The MCP servers "…" and "…" share the same session storage. …` | Two servers resolve to one session directory or cache prefix. | Give each server its own `session.directory` / `session.prefix`. |
| `The MCP servers "…" and "…" are both configured on the HTTP path "…". …` | Two servers declare the same `http.path`. | Give each server its own path. |
| `Several MCP servers expose the STDIO transport, name the one to run: …` | More than one server enables STDIO. | Run `php bin/console mcp:server <name>`. |
| A tool does not appear in the client | The service carries the attribute but no `registry` matches it. | Run `php bin/console debug:mcp`, then add the class to the server's registry. |
| An editor connection hangs | The editor speaks STDIO while the server only serves HTTP, or the reverse. | Match `transports` to the client: editors spawn STDIO, hosted clients use HTTP. |

## Limitations

- The bundle is experimental: configuration and behaviour change between minor
  versions. Pin `symfony/mcp-bundle` and read `UPGRADE.md` in the monorepo
  before upgrading.
- No built-in authentication: protect HTTP endpoints at a reverse proxy or a
  firewall, and check permissions in each tool (`Security::isGranted()`); STDIO
  trusts the OS user that spawned the process.
- Every HTTP server also answers the 2026-07-28 protocol revision, which has no
  server-initiated requests: `$gateway->sample()` / `listRoots()` fail for
  clients speaking it.
- One STDIO process serves exactly one server.

## Usage

- **HTTP server with one tool**: `references/patterns.md` → *HTTP server with one tool*.
- **STDIO server for an editor**: `references/patterns.md` → *STDIO server for editor integration*.
- **Prompt + tool**: `references/patterns.md` → *Prompt + tool combination*.
- **MCP App (UI resource)**: `references/patterns.md` → *MCP App (UI resource)*;
  enable it with the `apps` registry kind.
- **Call a remote MCP server**: `references/patterns.md` → *Consuming a remote MCP server (client)*.
- **Check what is exposed**: `php bin/console debug:mcp` (`--server=<name>`,
  `--client=<name>`, `--clients`).

## References

- Read [`references/api-reference.md`](references/api-reference.md) when
  writing a capability class or checking exact signatures: SDK and bundle
  attributes, bundle classes, the compiler passes, the client API, the full
  config tree, service ids.
- Read [`references/patterns.md`](references/patterns.md) when the user wants a
  working recipe: HTTP tool, STDIO server, prompts, resources, MCP Apps, a
  remote client, diagnostics.
- Read [`references/gotchas.md`](references/gotchas.md) before touching
  transports, sessions or the registry, or when a recipe misbehaves: transport
  mismatch, JSON-RPC error codes, DNS rebinding, auth, STDIO lifecycle,
  protocol revisions, subscriptions.

## See also

- `symfony-ai-mate`: the inverse use case (the assistant reads the application).
- `symfony-ai-bundle`: `mcp_server` tool entries that hand a remote server's tools to an agent.
- `symfony-ai-agent`: `#[AsTool]` for AI tool calling (not MCP).
