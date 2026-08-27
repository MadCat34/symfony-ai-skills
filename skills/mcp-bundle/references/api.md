# MCP Bundle : API Reference

Read this when the user asks for the full signature catalogue of the bundle, the config tree, or the routes wiring.

Source of truth: `https://github.com/symfony/ai/tree/main/src/mcp-bundle/` (namespace `Symfony\AI\McpBundle\`).

## Two namespaces

The bundle uses **two** namespaces that must not be confused:

```php
Symfony\AI\McpBundle\          ← this bundle (Symfony glue)
Mcp\                           ← the SDK the bundle wraps
```

Every attribute the developer writes (`#[McpTool]`, `#[McpPrompt]`, `#[McpResource]`, `#[McpResourceTemplate]`) and every transport (`StreamableHttpTransport`, `StdioTransport`) is in the `Mcp\` namespace. The bundle adds the autoconfiguration, compiler pass, controller, command, profiler, route loader, and the `#[AsMcpApp]` UI layer.

## Bundle namespaces

```php
Symfony\AI\McpBundle\
├── McpBundle                                       main bundle class (extends AbstractBundle)
├── Attribute\
│   ├── AsMcpApp                                    UI-resource MCP App
│   └── AsMcpAppTool                                additional tool on an #[AsMcpApp] class
├── App\
│   ├── McpAppRenderer                              Twig renderer (service id mcp.app.renderer); requires Twig
│   ├── McpAppResourceRenderer                      single shared renderer dispatched by URI for template-based apps
│   └── McpAppReferenceHandler                      decorates SDK ReferenceHandler; renders template-bound tool results
├── Client\
│   ├── McpClientInterface                          one configured client (mcp.clients.<name>); IteratorAggregate<string, ServerConnectionInterface>
│   ├── McpClient                                   default implementation
│   ├── ServerConnectionInterface                   one connection to one remote server (lazy-opened, auto-reconnect)
│   ├── ServerConnection                            default implementation, wraps an SDK Mcp\Client
│   ├── TransportFactory                            builds the SDK stdio/http client transport from config
│   └── ServerLogForwarder                          forwards remote log notifications to the "mcp" logger channel
├── Command\
│   ├── McpCommand                                  #[AsCommand('mcp:server')] — STDIO transport, one server per invocation
│   └── DebugCommand                                #[AsCommand('debug:mcp')] — lists servers' capabilities AND clients' reach
├── Controller\
│   └── McpController                               HTTP transport entry point, one instance per server (route _mcp_endpoint_<name>)
├── DependencyInjection\
│   ├── McpPass                                     compiler pass — reflects tagged methods, calls Builder::add*() per matching server
│   └── McpAppPass                                  compiler pass — wires #[AsMcpApp] / #[AsMcpAppTool] (priority 10)
├── Exception\
│   ├── ExceptionInterface                          interface extends \Throwable
│   ├── LogicException                              extends \LogicException implements ExceptionInterface
│   └── InvalidArgumentException                    extends \InvalidArgumentException implements ExceptionInterface
├── Http\
│   └── MiddlewareFactory                           DNS-rebinding protection tuning, one instance per server
├── Profiler\
│   └── DataCollector                                Web Profiler panel (registered when kernel.debug), aggregates every server
├── Routing\
│   └── RouteLoader                                 supports type 'mcp'; adds one _mcp_endpoint_<name> route per HTTP-enabled server
└── Session\
    └── FrameworkSessionStore                       implements SessionStoreInterface; backed by Symfony SessionHandlerInterface
```

The `file`, `memory`, and `cache` session stores are NOT in the bundle : they live in the SDK at `Mcp\Server\Session\FileSessionStore`, `Mcp\Server\Session\InMemorySessionStore`, `Mcp\Server\Session\Psr16SessionStore`. Only the `framework` backend is bundle-specific.

## SDK namespaces used by the bundle

```text
Mcp\
├── Server                                          built via Mcp\Server::builder(); run via $server->run($transport)
├── Server\Builder                                  fluent builder (setServerInfo, addTool, addPrompt, addResource, addResourceTemplate, enableExtension, setRegistry, setSession, setContainer, setReferenceHandler, ...)
├── Server\Transport\
│   ├── StreamableHttpTransport                     used by McpController
│   ├── StdioTransport                              used by McpCommand
│   └── Http\Middleware\DnsRebindingProtectionMiddleware
├── Server\Session\SessionStoreInterface            contract implemented by FrameworkSessionStore
├── Capability\
│   ├── Attribute\McpTool                           SDK attribute (see below)
│   ├── Attribute\McpPrompt
│   ├── Attribute\McpResource
│   ├── Attribute\McpResourceTemplate
│   ├── Registry                                    one instance per server, service id mcp.server.<name>.registry
│   ├── Discovery\DocBlockParser
│   └── Discovery\SchemaGenerator                   derives JSON input schema from method signatures
├── Schema\
│   ├── ToolAnnotations                             passed to addTool()
│   ├── Annotations                                 passed to addResource() / addResourceTemplate()
│   ├── Icon                                        passed to addTool() / addPrompt() / addResource() icons
│   ├── JsonRpc\Request                             abstract; SDK sub-types for each MCP method
│   ├── JsonRpc\Response
│   ├── JsonRpc\Error                               JSON-RPC error envelope (PARSE_ERROR -32700, INVALID_REQUEST -32600, METHOD_NOT_FOUND -32601, INVALID_PARAMS -32602, INTERNAL_ERROR -32603, RESOURCE_NOT_FOUND -32002)
│   └── Extension\Apps\McpApps                      server extension enabling #[AsMcpApp]; MIME_TYPE and URI_SCHEME constants
└── Exception\ExceptionInterface                    SDK exception contract
```

## SDK attribute signatures (real, from `Mcp\Capability\Attribute\`)

These are the constructors the compiler pass reflects on. There is no bundle wrapper, no alternate signature.

```php
namespace Mcp\Capability\Attribute;

#[\Attribute(\Attribute::TARGET_METHOD | \Attribute::TARGET_CLASS)]
final class McpTool
{
    public function __construct(
        public ?string $name = null,              // defaults to method name
        public ?string $title = null,
        public ?string $description = null,        // defaults to the method's DocBlock
        public ?\Mcp\Schema\ToolAnnotations $annotations = null,
        public ?array $icons = null,
        public ?array $meta = null,
        public ?array $outputSchema = null,
    ) {}
}

#[\Attribute(\Attribute::TARGET_METHOD | \Attribute::TARGET_CLASS)]
final class McpPrompt
{
    public function __construct(
        public ?string $name = null,
        public ?string $title = null,
        public ?string $description = null,
        public ?array $icons = null,
        public ?array $meta = null,
    ) {}
    // NOTE: no `arguments` parameter — prompt arguments are derived from the method signature.
}

#[\Attribute(\Attribute::TARGET_METHOD | \Attribute::TARGET_CLASS)]
final class McpResource
{
    public function __construct(
        public string $uri,                       // ONLY required argument
        public ?string $name = null,
        public ?string $title = null,
        public ?string $description = null,
        public ?string $mimeType = null,
        public ?int $size = null,
        public ?\Mcp\Schema\Annotations $annotations = null,
        public ?array $icons = null,
        public ?array $meta = null,
    ) {}
}

#[\Attribute(\Attribute::TARGET_METHOD | \Attribute::TARGET_CLASS)]
final class McpResourceTemplate
{
    public function __construct(
        public string $uriTemplate,               // ONLY required argument; RFC 6570
        public ?string $name = null,
        public ?string $title = null,
        public ?string $description = null,
        public ?string $mimeType = null,
        public ?\Mcp\Schema\Annotations $annotations = null,
        public ?array $meta = null,
    ) {}
}
```

`McpPass` reads these attributes at compile time, generates the JSON input schema with `Mcp\Capability\Discovery\SchemaGenerator` (over a `DocBlockParser`), then calls the matching `Mcp\Server\Builder` method (`addTool`, `addPrompt`, `addResource`, `addResourceTemplate`) with a `[class, method]` handler and the attribute fields in the same order as the SDK's `Builder::add*()` signatures.

## Bundle attribute signatures

```php
namespace Symfony\AI\McpBundle\Attribute;

#[\Attribute(\Attribute::TARGET_CLASS)]
final class AsMcpApp
{
    public function __construct(
        public ?string $uri = null,                // defaults to 'ui://<kebab-short-class-name>'
        public ?string $name = null,               // linked tool name; default slug with dashes→underscores
        public ?string $title = null,
        public ?string $description = null,
        public ?string $template = null,           // Twig template name for the HTML shell
        public ?string $method = null,             // tool handler; default 'render'
        public ?string $toolTemplate = null,       // HTML-over-the-wire fragment for the primary tool
        public ?bool $prefersBorder = null,
        public ?string $domain = null,
        public ?array $cspConnect = null,
        public ?array $cspResource = null,
        public ?array $cspFrame = null,
        public ?array $cspBaseUri = null,
        public bool $camera = false,
        public bool $microphone = false,
        public bool $geolocation = false,
        public bool $clipboardWrite = false,
    ) {}
}

#[\Attribute(\Attribute::TARGET_METHOD)]
final class AsMcpAppTool
{
    public function __construct(
        public ?string $name = null,               // defaults to method name in snake_case
        public ?string $title = null,
        public ?string $description = null,
        public ?string $template = null,
        public bool $appOnly = false,              // [app] vs [model, app] visibility
    ) {}
}
```

The app URI MUST use the `ui://` scheme (`Mcp\Schema\Extension\Apps\McpApps::URI_SCHEME`); a different scheme triggers `LogicException` in `McpAppPass::process`.

## Bundle classes

### `Symfony\AI\McpBundle\McpBundle`

```php
final class McpBundle extends AbstractBundle
{
    public function configure(DefinitionConfigurator $definition): void;            // imports config/options.php
    public function loadExtension(array $config, ContainerConfigurator $container, ContainerBuilder $builder): void;
    public function build(ContainerBuilder $container): void;                      // adds McpAppPass(10) then McpPass()
}
```

`loadExtension` (the critical method):

- Imports `config/services.php` (registers only the server-agnostic services: `mcp.psr17_factory`, `mcp.psr_http_factory`, `mcp.http_foundation_factory`). Everything carrying per-server values (registry, builder, server, session store, controller) is registered per server by `configureServer()`, since those are method-call arguments on the SDK builder and method calls cannot be overridden through definition inheritance.

- Registers attribute autoconfiguration for the four SDK attributes (`registerMcpAttributes()`) and for `#[AsMcpApp]` (tag `mcp.app`).

- Registers the Twig `McpAppRenderer` service IF Twig is available.

- Auto-configures `Mcp\Capability\Registry\Loader\LoaderInterface` (tag `mcp.loader`), `RequestHandlerInterface` (tag `mcp.request_handler`), `NotificationHandlerInterface` (tag `mcp.notification_handler`).

- Calls `configureServers($config['servers'])` for the `servers:` section, and `configureClients($config['clients'])` for the `clients:` section — independent code paths, since a server (exposing your app) and a client (reaching another server) are unrelated roles.

`configureServers()` loops `configureServer($name, $server)` per entry, which registers that server's `mcp.server.<name>.registry`, `.builder`, `.<name>` (the `Server` itself, aliased for argument as `<name> server`), `.middleware_factory`, `.controller` (if HTTP enabled), and `.session.store`; it also feeds the shared `mcp.server.route_loader` (one `RouteLoader` for every HTTP-enabled server), `mcp.server.command` (one `McpCommand` for every STDIO-enabled server), and — when `kernel.debug` — the shared `mcp.data_collector`.

`configureClients()` loops per client, registering `mcp.client.<clientName>.server.<serverName>.transport` / `.builder` for each remote server, then `mcp.client.<clientName>` (`McpClient`, aliased for argument as `McpClientInterface` under the client's own name — and, when there is exactly one client, as a plain `McpClientInterface` too).

### `Symfony\AI\McpBundle\Controller\McpController`

```php
final class McpController
{
    public function __construct(
        private readonly \Mcp\Server $server,
        private readonly HttpMessageFactoryInterface $httpMessageFactory,
        private readonly HttpFoundationFactoryInterface $httpFoundationFactory,
        private readonly ResponseFactoryInterface $responseFactory,
        private readonly StreamFactoryInterface $streamFactory,
        private readonly MiddlewareFactory $middlewareFactory,
        private readonly ?LoggerInterface $logger = null,
    ) {}

    public function handle(Request $request): Response;
}
```

Per-request: builds a `StreamableHttpTransport` with the configured middleware, runs `$server->run($transport)`, adapts the PSR-7 response to a Symfony `Response` (streamed when `Content-Type: text/event-stream`). One `McpController` instance is registered per HTTP-enabled server (`mcp.server.<name>.controller`), each bound to its own `Server` and `MiddlewareFactory`.

### `Symfony\AI\McpBundle\Command\McpCommand`

```php
#[AsCommand('mcp:server', 'Starts an MCP server over STDIO')]
final class McpCommand
{
    /**
     * @param ServiceProviderInterface<\Mcp\Server> $servers the servers with the STDIO transport enabled
     */
    public function __construct(
        private readonly ServiceProviderInterface $servers,
        private readonly ?LoggerInterface $logger = null,
    ) {}

    public function __invoke(
        SymfonyStyle $io,
        ?string $name = null,   // #[Argument]; name of the server to run (mcp.servers.<name>)
    ): int;
    // builds a StdioTransport and runs $name (or the sole STDIO-enabled server when $name is null
    // and exactly one is configured; otherwise errors listing the available names)
}
```

The command name is `mcp:server` (NOT `mcp:serve`). One shared instance serves every STDIO-enabled server — the transport owns the process' STDIN/STDOUT, so exactly one server runs per invocation, hence the name argument instead of one command per server.

### `Symfony\AI\McpBundle\Command\DebugCommand`

```php
#[AsCommand('debug:mcp', 'Display the configured MCP servers and clients')]
final class DebugCommand
{
    /**
     * @param ServiceProviderInterface<\Mcp\Server\Builder>            $builders
     * @param ServiceProviderInterface<\Mcp\Capability\RegistryInterface> $registries
     * @param ServiceProviderInterface<McpClientInterface>             $clients
     * @param array<string, list<string>>                              $unassigned kind => service ids no server exposes
     */
    public function __construct(
        private readonly ServiceProviderInterface $builders,
        private readonly ServiceProviderInterface $registries,
        private readonly ServiceProviderInterface $clients,
        private readonly array $unassigned = [],
    ) {}

    public function __invoke(
        SymfonyStyle $io,
        ?string $name = null,      // #[Argument]; a tool/prompt name, resource URI, or resource template
        ?string $server = null,    // #[Option]; restrict to one server, or (with --client) the remote server to connect to
        ?string $client = null,    // #[Option]; connect this configured client and list what its server(s) advertise
        bool $clients = false,     // #[Option]; list configured clients and their servers without connecting
    ): int;
    // --client opens a connection (the only mode that does); every other mode reads the compiled container
}
```

Only `--client` opens a network/process connection; server-side inspection (default, `--server`) and `--clients` read the compiled container only.

### `Symfony\AI\McpBundle\Attribute\AsMcpApp` / `AsMcpAppTool`

See the bundle attribute signatures above.

### `Symfony\AI\McpBundle\Routing\RouteLoader`

```php
final class RouteLoader extends Loader
{
    /**
     * @param list<array{name: string, path: string, controller: string}> $servers the MCP servers exposed over HTTP
     */
    public function __construct(
        private array $servers,
    ) {}

    public function load(mixed $resource, ?string $type = null): RouteCollection;  // 'mcp' type
    public function supports(mixed $resource, ?string $type = null): bool;          // 'mcp' === $type
}
```

Adds one route per HTTP-enabled server, named `_mcp_endpoint_<name>`, at that server's `http.path` (default `/mcp/<name>`), with `methods: [GET, POST, DELETE, OPTIONS]` and `_controller: mcp.server.<name>.controller::handle`. Calling `load()` twice throws `LogicException` — same as before, just now one loader covers every server.

Routes config (`config/routes.yaml`):

```yaml
mcp:
    resource: .
    type: mcp
```

### `Symfony\AI\McpBundle\Http\MiddlewareFactory`

```php
final class MiddlewareFactory
{
    public function __construct(
        private readonly array|false|null $allowedHosts = null,
    ) {}

    /**

     * @return list<\Psr\Http\Server\MiddlewareInterface>|null
     */
    public function create(): ?array;
}
```

Tunings on the SDK's default middleware stack:

- `null` (unset): return `null` → the SDK uses its secure defaults (DNS rebinding protection on localhost).

- `false`: strip `DnsRebindingProtectionMiddleware` entirely (public MCP server).

- `list<string>`: replace the middleware with one restricted to those hostnames.

### `Symfony\AI\McpBundle\Profiler\DataCollector`

```php
final class DataCollector extends AbstractDataCollector implements LateDataCollectorInterface
{
    public function __construct(private readonly Builder $builder, private readonly RegistryInterface $registry);

    public function collect(Request $request, Response $response, ?\Throwable $exception = null): void;  // empty
    public function lateCollect(): void;                                                                  // builds the server, fills data
    public function getTools(): array;
    public function getPrompts(): array;
    public function getResources(): array;
    public function getResourceTemplates(): array;
    public function getTotalCount(): int;
    public function getName(): string;             // 'mcp'
    public static function getTemplate(): string;  // '@Mcp/data_collector.html.twig'
}
```

### `Symfony\AI\McpBundle\Session\FrameworkSessionStore`

```php
final class FrameworkSessionStore implements \Mcp\Server\Session\SessionStoreInterface
{
    public function __construct(
        private readonly \SessionHandlerInterface $handler,
        private readonly string $prefix = 'mcp-',
        private readonly int $ttl = 3600,
    ) {}

    public function exists(\Symfony\Component\Uid\Uuid $id): bool;
    public function read(\Symfony\Component\Uid\Uuid $id): string|false;
    public function write(\Symfony\Component\Uid\Uuid $id, string $data): bool;
    public function destroy(\Symfony\Component\Uid\Uuid $id): bool;
    public function gc(): array;          // always [] — expiry is enforced lazily on read()
}
```

Stored under `$prefix . $id` in the framework session handler as a JSON envelope `{d: data, e: expiryTimestamp}`. Expiry is enforced on `read()`; `gc()` is a no-op because `SessionHandlerInterface::gc()` would affect unrelated framework sessions.

### `Symfony\AI\McpBundle\DependencyInjection\McpPass`

Compiler pass. For each service tagged `mcp.tool` / `mcp.prompt` / `mcp.resource` / `mcp.resource_template`:

1. Resolves the class, throws `LogicException` if the class does not exist or the tagged method does not exist.

2. Reads the SDK attribute (method-level first, falling back to class-level for `__invoke`).

3. Generates the JSON input schema with `Mcp\Capability\Discovery\SchemaGenerator` (wrapped in try/catch for `Mcp\Exception\ExceptionInterface`).

4. Calls the matching `Mcp\Server\Builder::add*()` method with the handler `[class, method]` and the attribute fields.

5. Builds a service locator (`ServiceLocatorTagPass::register`) keyed by class and service id, then `setContainer()` on the builder.

6. Wires `McpAppReferenceHandler` if `mcp.apps.tool_templates` is non-empty.

### `Symfony\AI\McpBundle\DependencyInjection\McpAppPass`

Compiler pass, priority 10 (runs BEFORE `McpPass`). For each service tagged `mcp.app`, matched per server against that server's `registry.apps` patterns (same matcher as tools/prompts/resources):

1. Reads the `#[AsMcpApp]` attribute.

2. Enforces `ui://` URI scheme.

3. Resolves the resource handler: class with `__invoke()` (tagged `mcp.resource`) OR template-based (routes through the shared `McpAppResourceRenderer`).

4. Registers the UI resource with the `_meta.ui` descriptor marker (`Mcp\Schema\Extension\Apps\McpApps::resourceMarker()`) on the matching server's builder.

5. Registers the linked tool from the handler method (default `render`) with `ui` link `Mcp\Schema\Extension\Apps\UiToolMeta::class` and visibility `[ToolVisibility::Model, ToolVisibility::App]` (or `[ToolVisibility::App]` when `appOnly = true`).

6. Registers each method with `#[AsMcpAppTool]` as an additional tool.

7. Stores the `toolTemplates` map in the `mcp.apps.tool_templates` container parameter (consumed by `McpPass`).

Enables the `McpApps` extension (`Builder::enableExtension(new McpApps())`) once per server whose `registry.apps` pattern matches at least one `#[AsMcpApp]` service — there is no `apps.enabled` boolean anymore, this replaced it entirely (see `references/gotchas.md` #14).

### `Symfony\AI\McpBundle\Client\McpClientInterface` / `McpClient` / `ServerConnectionInterface`

```php
namespace Symfony\AI\McpBundle\Client;

/**
 * @extends \IteratorAggregate<string, ServerConnectionInterface>
 */
interface McpClientInterface extends \IteratorAggregate, \Countable
{
    public function getName(): string;                              // this client's config key (mcp.clients.<name>)
    public function has(string $server): bool;
    public function get(string $server): ServerConnectionInterface; // throws InvalidArgumentException if unknown
    public function getServerNames(): array;
    public function disconnect(): void;                             // closes every connection this client opened
}

final class McpClient implements McpClientInterface
{
    /**
     * @param ServiceProviderInterface<ServerConnectionInterface> $connections keyed by server name
     */
    public function __construct(
        private readonly string $name,
        private readonly ServiceProviderInterface $connections,
    ) {}
}

interface ServerConnectionInterface
{
    public function getName(): string;         // this remote server's config key (mcp.clients.<client>.servers.<name>)
    public function getClientName(): string;   // the owning client's config key
    public function isConnected(): bool;
    public function disconnect(): void;        // idempotent; reconnects transparently on next use

    public function getServerInfo(): ?\Mcp\Schema\Implementation;
    public function getInstructions(): ?string;
    public function ping(): void;

    public function listTools(?string $cursor = null): \Mcp\Schema\Result\ListToolsResult;
    public function getTools(): array;                                          // list<Tool>, follows pagination to the end
    public function callTool(string $name, array $arguments = [], ?callable $onProgress = null): \Mcp\Schema\Result\CallToolResult;

    public function listResources(?string $cursor = null): \Mcp\Schema\Result\ListResourcesResult;
    public function getResources(): array;                                      // list<ResourceDefinition>
    public function readResource(string $uri, ?callable $onProgress = null): \Mcp\Schema\Result\ReadResourceResult;

    public function listResourceTemplates(?string $cursor = null): \Mcp\Schema\Result\ListResourceTemplatesResult;
    public function getResourceTemplates(): array;                              // list<ResourceTemplate>

    public function listPrompts(?string $cursor = null): \Mcp\Schema\Result\ListPromptsResult;
    public function getPrompts(): array;                                        // list<Prompt>
    public function getPrompt(string $name, array $arguments = [], ?callable $onProgress = null): \Mcp\Schema\Result\GetPromptResult;

    public function complete(\Mcp\Schema\PromptReference|\Mcp\Schema\ResourceReference $ref, array $argument): \Mcp\Schema\Result\CompletionCompleteResult;
    public function setLoggingLevel(\Mcp\Schema\Enum\LoggingLevel $level): void;
}
```

A connection is opened lazily on first use (not on `get()`, not on client construction) and closed on kernel reset — callers never manage transports or the SDK's explicit connect/disconnect lifecycle directly. Iterating an `McpClientInterface` (`foreach ($client as $name => $connection)`) does not open any connection either; only calling a method on a `ServerConnectionInterface` does.

### Exceptions

```php
namespace Symfony\AI\McpBundle\Exception;

interface ExceptionInterface extends \Throwable {}

class LogicException extends \LogicException implements ExceptionInterface {}
class InvalidArgumentException extends \InvalidArgumentException implements ExceptionInterface {}
```

There is NO `McpException`, NO `RuntimeException`, NO `McpServerException`. `LogicException` comes from `McpBundle::registerMcpAttributes()`, `McpAppPass::process()`, and `McpPass::process()`. `InvalidArgumentException` comes from `McpClient::get()` (unknown server name) and `DebugCommand` (unknown server/client name).

## Config tree (`config/options.php`)

```yaml
mcp:
    servers:                                          # map, key = server name (letters/digits/_/-)
        <name>:
            name: ~                                   # advertised name; defaults to the config key
            version: '0.0.1'
            description: ~
            icons: []                                 # list<{src, mime_type?, sizes[]}>
            website_url: ~
            pagination_limit: 50                      # min 1
            instructions: ~

            transports:
                stdio: false                           # enables `mcp:server <name>`
                http: true                              # enables the `_mcp_endpoint_<name>` route

            http:
                path: ~                                # default '/mcp/<name>'
                allowed_hosts: ~                       # null=SDK default (localhost), list<string>, or false

            session:
                store: 'file'                          # file | memory | cache | framework
                directory: ~                            # file backend; default '%kernel.cache_dir%/mcp-sessions/<name>'
                cache_pool: 'cache.mcp.sessions'       # cache backend (PSR-16 wrapper around cache.app if missing)
                prefix: ~                               # file/memory/cache/framework key prefix; default 'mcp-<name>-'
                ttl: 3600                               # seconds, min 1

            registry: []                               # REQUIRED: one list for every kind, or a map per kind
                                                        # (tools, prompts, resources, resource_templates, apps)
                                                        # entries: service id | FQCN | 'Namespace\Prefix\' | '*'

    clients:                                           # map, key = client name (letters/digits/_/-); default {}
        <name>:
            client_info:
                name: ~                                 # defaults to the config key
                version: '0.0.1'
                description: ~
            forward_server_logs: true                   # forward remote log notifications to the "mcp" logger channel
            protocol_version: ~                         # leave unset to keep the SDK default
            capabilities:
                roots: false
                roots_list_changed: false
            sampling: ~                                 # service id implementing SamplingCallbackInterface
            elicitation: ~                              # service id implementing ElicitationCallbackInterface
            init_timeout: 30                            # seconds, min 1
            request_timeout: 120
            max_retries: 3

            servers:                                    # REQUIRED, at least one entry
                <serverName>:
                    transport: ~                         # REQUIRED: 'stdio' or 'http'
                    # stdio only:
                    command: []                          # e.g. ['npx', '-y', '@modelcontextprotocol/server-filesystem', '/tmp']
                    cwd: ~
                    env: {}
                    inherit_env: true
                    max_buffer_size: ~
                    # http only:
                    url: ~
                    headers: {}
                    http_client: ~                       # PSR-18 client service id; default 'psr18.http_client'
                    max_sse_buffer_bytes: ~
                    # overrides of the client-level values, per remote server:
                    init_timeout: ~
                    request_timeout: ~
                    max_retries: ~
```

Notes:

- The default HTTP path is `/mcp/<name>`, always derived from the server name (NOT `/_mcp`, and NOT a fixed `/mcp`).

- `registry` accepts a bare list (one set of patterns for every kind) or a map keyed by `tools`/`prompts`/`resources`/`resource_templates`/`apps`. A pattern matching nothing on its server is a compile-time error; `'*'` cannot be combined with other entries in the same list.

- Two servers must not resolve to the same session storage : rejected at compile time.

- `clients.<name>.servers.<name>` validates `stdio` and `http` options are mutually exclusive per entry (a `command` on an `http` entry, or a `url` on a `stdio` entry, is a compile-time error).

- The `cache` session backend auto-creates a default pool (`cache.mcp.sessions` as `Psr16Cache` wrapping `cache.app`) only when the configured pool id matches and the pool does not yet exist.

## Service IDs

| Service id | Type | Where |
|---|---|---|
| `mcp.server.<name>.registry` | `Mcp\Capability\Registry` | `configureServer()` |
| `mcp.server.<name>.builder` | `Mcp\Server\Builder` | `configureServer()` (factory: `Mcp\Server::builder()`) |
| `mcp.server.<name>` | `Mcp\Server` | `configureServer()` (factory: `mcp.server.<name>.builder->build()`); aliased for argument as `<name> server` |
| `mcp.server.<name>.session.store` | one of `FileSessionStore` / `InMemorySessionStore` / `Psr16SessionStore` / `FrameworkSessionStore` | `configureServer()` |
| `mcp.server.<name>.middleware_factory` | `Symfony\AI\McpBundle\Http\MiddlewareFactory` | `configureServer()` |
| `mcp.server.<name>.controller` | `Symfony\AI\McpBundle\Controller\McpController` | `configureServer()`, only when `transports.http` |
| `mcp.server.command` | `Symfony\AI\McpBundle\Command\McpCommand` | `configureServers()`, one shared instance for every STDIO-enabled server |
| `mcp.server.route_loader` | `Symfony\AI\McpBundle\Routing\RouteLoader` | `configureServers()`, one shared instance for every HTTP-enabled server |
| `mcp.server.debug_command` | `Symfony\AI\McpBundle\Command\DebugCommand` | `loadExtension()` |
| `mcp.data_collector` | `Symfony\AI\McpBundle\Profiler\DataCollector` | `configureServers()` (kernel.debug only) |
| `mcp.client.<name>` | `Symfony\AI\McpBundle\Client\McpClient` | `configureClients()`; aliased for argument as `McpClientInterface $<name>` (and as a plain `McpClientInterface` when it is the only client) |
| `mcp.client.<client>.server.<server>.transport` | SDK client transport | `configureClients()` |
| `mcp.client.<client>.server.<server>.builder` | SDK client builder | `configureClients()` |
| `mcp.psr17_factory` | `Http\Discovery\Psr17Factory` | services.php |
| `mcp.psr_http_factory` | `Symfony\Bridge\PsrHttpMessage\Factory\PsrHttpFactory` | services.php |
| `mcp.http_foundation_factory` | `Symfony\Bridge\PsrHttpMessage\Factory\HttpFoundationFactory` | services.php |
| `mcp.app.renderer` | `Symfony\AI\McpBundle\App\McpAppRenderer` | configureApps() (Twig only) |
| `mcp.app.reference_handler` | `Symfony\AI\McpBundle\App\McpAppReferenceHandler` | McpPass::configureAppReferenceHandler() |

## See also

- `references/patterns.md`

- `references/gotchas.md`
