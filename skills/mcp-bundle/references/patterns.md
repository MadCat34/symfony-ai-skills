# MCP Bundle : Patterns

Read this when the user wants a concrete working recipe: HTTP tool, STDIO server, prompt + tool combo, or an MCP App UI resource.

All patterns rely on the bundle auto-discovering methods on autoconfigured services. The default `config/services.yaml` (`App\:` with `autoconfigure: true`) is enough : no extra wiring required.

## HTTP server with one tool

`config/packages/mcp.yaml`:

```yaml
mcp:
    app: 'demo-mcp'
    version: '0.1.0'
    description: 'One-tool HTTP MCP server'
    client_transports:
        http: true
    http:
        path: '/_mcp'           # default; explicit for clarity
```

`config/routes.yaml`:

```yaml
mcp:
    resource: .
    type: mcp
```

`src/MCP/WeatherService.php`:

```php
namespace App\MCP;

use Mcp\Capability\Attribute\McpTool;

class WeatherService
{
    #[McpTool(
        name: 'get_weather',
        description: 'Get current weather for a city (metric units).',
    )]
    public function getWeather(string $city): array
    {
        // Real implementation would call a provider.
        return ['city' => $city, 'temperature_c' => 22, 'sky' => 'sunny'];
    }
}
```

`App\MCP\WeatherService` is auto-discovered (autoconfigure on `App\`) and auto-tagged `mcp.tool` by the bundle's `registerMcpAttributes()`. `McpPass` reflects `getWeather`, derives the input schema `{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}`, and calls `Builder::addTool()`.

Test with curl:

```bash
# initialize
curl -sX POST http://localhost:8000/_mcp \
     -H 'Content-Type: application/json' \
     -H 'Accept: application/json, text/event-stream' \
     -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"curl","version":"0"}}}'

# list tools
curl -sX POST http://localhost:8000/_mcp \
     -H 'Content-Type: application/json' \
     -H 'Accept: application/json, text/event-stream' \
     -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'

# call tool
curl -sX POST http://localhost:8000/_mcp \
     -H 'Content-Type: application/json' \
     -H 'Accept: application/json, text/event-stream' \
     -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_weather","arguments":{"city":"Paris"}}}'
```

Sanity-check that the tool is registered:

```bash
php bin/console debug:mcp
php bin/console debug:mcp get_weather
```

## STDIO server for editor integration

`config/packages/mcp.yaml`:

```yaml
mcp:
    app: 'demo-mcp'
    version: '0.1.0'
    client_transports:
        stdio: true
```

`src/MCP/WeatherService.php`: same as the HTTP pattern : the same `#[McpTool]` method serves both transports, the choice is which transport the client connects to.

Claude Code `~/.claude.json` (or `mcp.json`):

```json
{
    "mcpServers": {
        "weather": {
            "type": "stdio",
            "command": "php",
            "args": ["bin/console", "mcp:server"],
            "cwd": "/absolute/path/to/your/symfony/app"
        }
    }
}
```

The client spawns the process and pipes JSON-RPC over stdin/stdout. The bundle's `McpCommand` constructs an `Mcp\Server\Transport\StdioTransport` and runs the server; the SDK handles the JSON-RPC framing. Keep the same warning about stdout pollution (see gotchas).

## Prompt + tool combination

A single class can expose both a prompt and a tool : two methods, two different attributes. Useful when the prompt is a template that instructs the agent to call the tool:

```php
namespace App\MCP;

use Mcp\Capability\Attribute\McpPrompt;
use Mcp\Capability\Attribute\McpTool;

class TripPlanner
{
    #[McpTool(
        name: 'find_flights',
        description: 'Search flights between two cities on a given date.',
    )]
    public function findFlights(string $from, string $to, string $date): array
    {
        return [['flight' => 'AF123', 'from' => $from, 'to' => $to, 'date' => $date]];
    }

    #[McpPrompt(
        name: 'plan_a_trip',
        description: 'Plan a trip: instruct the agent to call find_flights with the user-provided cities.',
    )]
    public function planATrip(string $from, string $to): array
    {
        return [
            ['role' => 'user', 'content' => "Plan a trip from {$from} to {$to}."],
            ['role' => 'assistant', 'content' => null,
             'tool_calls' => [['name' => 'find_flights', 'arguments' => ['from' => $from, 'to' => $to, 'date' => '2026-08-15']]]],
        ];
    }
}
```

`#[McpPrompt]` has no `arguments` parameter : the prompt's argument list is derived from the method signature, just like tool input schemas. The method itself returns the messages array.

## Resource (single, fixed URI)

```php
namespace App\MCP;

use Mcp\Capability\Attribute\McpResource;

class DocsService
{
    #[McpResource(
        uri: 'docs://readme',
        name: 'readme',
        description: 'Project README.',
        mimeType: 'text/markdown',
    )]
    public function readme(): string
    {
        return file_get_contents(__DIR__.'/../../README.md');
    }
}
```

`uri` is the only required `#[McpResource]` argument; `name`, `title`, `description`, `mimeType`, `size`, `annotations`, `icons`, `meta` are all optional.

## MCP App (UI resource) : `#[AsMcpApp]`

UI resources are HTML bodies served at `ui://...` URIs (mime type `text/html;profile=mcp-app`) that an MCP host renders in an iframe, plus a tool that feeds them. Requires `symfony/twig-bundle`.

`config/packages/mcp.yaml`:

```yaml
mcp:
    client_transports:
        http: true
    apps:
        enabled: true     # or leave null for auto (true if any #[AsMcpApp] exists)
```

`templates/mcp/dashboard.html.twig`:

```twig
<div class="dashboard">
    <h1>{{ title }}</h1>
    <p>Rows: {{ rows|length }}</p>
</div>
```

`src/MCP/DashboardApp.php`:

```php
namespace App\MCP;

use Symfony\AI\McpBundle\Attribute\AsMcpApp;
use Symfony\AI\McpBundle\Attribute\AsMcpAppTool;

#[AsMcpApp(
    uri: 'ui://dashboard',
    name: 'show_dashboard',
    title: 'Operations dashboard',
    description: 'Render the operations dashboard for the given period.',
    template: '@App/mcp/dashboard.html.twig',
    method: 'render',                                 # default; the handler method
    prefersBorder: true,
    cspConnect: ['https://api.example.com'],
)]
class DashboardApp
{
    public function __construct(private readonly DashboardRepository $repo) {}

    /**
     * Returns a context array; the bundle renders the template with this context.
     * The result `html` field is added by {@see \Symfony\AI\McpBundle\App\McpAppReferenceHandler}.
     */
    public function render(string $period): array
    {
        return ['title' => ucfirst($period), 'rows' => $this->repo->rows($period)];
    }

    /**
     * Additional tool, visible to model + app by default. Set `appOnly: true` to hide from the model.
     */
    #[AsMcpAppTool(
        name: 'export_dashboard',
        description: 'Export the dashboard as CSV.',
    )]
    public function export(string $period): string
    {
        return $this->repo->csv($period);
    }
}
```

How it gets wired:

1. `McpAppPass` (priority 10) reads `#[AsMcpApp]`, enforces `ui://` scheme, registers the UI resource (with `_meta.ui` descriptor marker from `Mcp\Schema\Extension\Apps\McpApps::resourceMarker()`), tags the service `mcp.resource` for the template-based shared renderer.
2. `McpAppPass` registers the primary tool (`render` by default) with `ui` link = `Mcp\Schema\Extension\Apps\UiToolMeta::class` pointing at the app URI, visibility `[ToolVisibility::Model, ToolVisibility::App]`, and tags the service `mcp.tool`.
3. `McpAppPass` walks methods for `#[AsMcpAppTool]` and registers each as another tool on the same app (visibility follows `appOnly`).
4. `McpPass` (runs after) collects the tagged services into the handler service locator and wires `McpAppReferenceHandler` only when at least one tool has a `template` (HTML-over-the-wire) : that handler decorates the SDK `ReferenceHandler` and renders the fragment into the `html` field of the tool result.
5. The MCP Apps server extension (`Mcp\Schema\Extension\Apps\McpApps`) is `enableExtension`'d once per container.

A dynamic shell (no Twig) is possible by adding `__invoke(): \Mcp\Schema\Content\TextResourceContents` to the class and returning a custom-built `TextResourceContents` directly; the bundle then tags the service `mcp.resource` and uses the class handler instead of `McpAppResourceRenderer`.

## When the class has no handler method

If you forget to add the `render` method (or whatever you passed to `method:`) on the class, `McpAppPass::registerTool()` simply skips the tool : the app becomes a static screen with no tool. The exception is when you explicitly set `$method` to a name that does not exist: then `McpAppPass` throws `LogicException`.

The same logic applies to `#[AsMcpAppTool]` placed on the primary tool method: `LogicException` ("must not also carry #[AsMcpAppTool]").

## Diagnostic recipes

- **Tool not appearing in `debug:mcp`** : the class is not a registered service, or it is excluded from autoconfiguration. Check `config/services.yaml`. The `debug:mcp` warning text explicitly points at autoconfiguration.
- **No capabilities at all** : verify `client_transports.{stdio,http}` is true (one of them must be). When both are false, `McpCommand` / `McpController` services are not registered.
- **Class-level attribute without `__invoke`** : `registerMcpAttributes` throws `LogicException` at compile time, container build fails.

## See also

- `references/api.md` : full attribute signatures and config tree
- `references/gotchas.md` : transport mismatch, JSON-RPC error format, lifecycle
