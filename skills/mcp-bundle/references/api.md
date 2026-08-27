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
├── Command\
│   ├── McpCommand                                  #[AsCommand('mcp:server')] — STDIO transport
│   └── DebugCommand                                #[AsCommand('debug:mcp')] — list registered capabilities
├── Controller\
│   └── McpController                               HTTP transport entry point (route _mcp_endpoint)
├── DependencyInjection\
│   ├── McpPass                                     compiler pass — reflects tagged methods, calls Builder::add*()
│   └── McpAppPass                                  compiler pass — wires #[AsMcpApp] / #[AsMcpAppTool] (priority 10)
├── Exception\
│   ├── ExceptionInterface                          interface extends \Throwable
│   └── LogicException                              extends \LogicException implements ExceptionInterface
├── Http\
│   └── MiddlewareFactory                           DNS-rebinding protection tuning
├── Profiler\
│   └── DataCollector                               Web Profiler panel (registered when kernel.debug)
├── Routing\
│   └── RouteLoader                                 supports type 'mcp'; adds _mcp_endpoint when http transport enabled
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
│   ├── Registry                                    default registry service id mcp.registry
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

- Imports `config/services.php` (registers `mcp.registry`, `mcp.server.builder`, `mcp.server`).

- Stores all config under `mcp.*` parameters (`mcp.app`, `mcp.version`, `mcp.description`, `mcp.website_url`, `mcp.icons`, `mcp.pagination_limit`, `mcp.instructions`, `mcp.apps.enabled`).

- Registers attribute autoconfiguration for the four SDK attributes (`registerMcpAttributes()`).

- Registers `#[AsMcpApp]` autoconfiguration (adds tag `mcp.app`).

- Registers the Twig `McpAppRenderer` service IF Twig is available.

- Auto-configures `Mcp\Capability\Registry\Loader\LoaderInterface` (tag `mcp.loader`), `RequestHandlerInterface` (tag `mcp.request_handler`), `NotificationHandlerInterface` (tag `mcp.notification_handler`).

- Calls `configureClient()` if `client_transports` is set.

`configureClient()` conditionally registers `mcp.psr17_factory`, `mcp.psr_http_factory`, `mcp.http_foundation_factory`, the session store (`mcp.session.store`), `mcp.server.debug_command`, `mcp.server.command` (STDIO), `mcp.middleware_factory`, `mcp.server.controller` (HTTP), `mcp.server.route_loader`, and the Profiler `mcp.data_collector` (when `kernel.debug`).

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

Per-request: builds a `StreamableHttpTransport` with the configured middleware, runs `$server->run($transport)`, adapts the PSR-7 response to a Symfony `Response` (streamed when `Content-Type: text/event-stream`).

### `Symfony\AI\McpBundle\Command\McpCommand`

```php
#[AsCommand('mcp:server', 'Starts an MCP server')]
class McpCommand extends Command
{
    public function __construct(
        private readonly \Mcp\Server $server,
        private readonly ?LoggerInterface $logger = null,
    ) {}

    protected function execute(InputInterface $input, OutputInterface $output): int;  // builds StdioTransport, runs server
}
```

The command name is `mcp:server` (NOT `mcp:serve`).

### `Symfony\AI\McpBundle\Command\DebugCommand`

```php
#[AsCommand('debug:mcp', 'Display the MCP capabilities registered with the server')]
final class DebugCommand
{
    public function __construct(
        private readonly \Mcp\Server\Builder $builder,
        private readonly \Mcp\Capability\RegistryInterface $registry,
    ) {}

    public function __invoke(SymfonyStyle $io, ?string $name = null): int;
    // lists Tools, Prompts, Resources, Resource Templates tables; with $name, prints detailed schema
}
```

### `Symfony\AI\McpBundle\Attribute\AsMcpApp` / `AsMcpAppTool`

See the bundle attribute signatures above.

### `Symfony\AI\McpBundle\Routing\RouteLoader`

```php
final class RouteLoader extends Loader
{
    public function __construct(
        private bool $httpTransportEnabled,
        private string $httpPath,
    ) {}

    public function load(mixed $resource, ?string $type = null): RouteCollection;  // 'mcp' type
    public function supports(mixed $resource, ?string $type = null): bool;          // 'mcp' === $type
}
```

Adds one route `_mcp_endpoint` (when `httpTransportEnabled` is true) at `$httpPath` with `methods: [GET, POST, DELETE, OPTIONS]` and `_controller: mcp.server.controller::handle`. Calling `load()` twice throws `LogicException`.

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

Compiler pass, priority 10 (runs BEFORE `McpPass`). For each service tagged `mcp.app`:

1. Reads the `#[AsMcpApp]` attribute.

2. Enforces `ui://` URI scheme.

3. Resolves the resource handler: class with `__invoke()` (tagged `mcp.resource`) OR template-based (routes through the shared `McpAppResourceRenderer`).

4. Registers the UI resource with the `_meta.ui` descriptor marker (`Mcp\Schema\Extension\Apps\McpApps::resourceMarker()`).

5. Registers the linked tool from the handler method (default `render`) with `ui` link `Mcp\Schema\Extension\Apps\UiToolMeta::class` and visibility `[ToolVisibility::Model, ToolVisibility::App]` (or `[ToolVisibility::App]` when `appOnly = true`).

6. Registers each method with `#[AsMcpAppTool]` as an additional tool.

7. Stores the `toolTemplates` map in the `mcp.apps.tool_templates` container parameter (consumed by `McpPass`).

Enables the `McpApps` server extension (`Builder::enableExtension(new McpApps())`) once if either `apps.enabled = true` or any `#[AsMcpApp]` exists (and the extension has not already been enabled).

### Exceptions

```php
namespace Symfony\AI\McpBundle\Exception;

interface ExceptionInterface extends \Throwable {}

class LogicException extends \LogicException implements ExceptionInterface {}
```

There is NO `McpException`, NO `RuntimeException`, NO `McpServerException`. Bundle errors are `LogicException`s thrown from `McpBundle::registerMcpAttributes()`, `McpAppPass::process()`, and `McpPass::process()`.

## Config tree (`config/options.php`)

```yaml
mcp:
    app: 'app'                                    # scalar, default 'app'
    version: '0.0.1'
    description: ~                                # null
    icons:                                        # list<{src, mime_type?, sizes[]}>

        - { src: 'https://example.com/icon.png', mime_type: 'image/png', sizes: ['any'] }
    website_url: ~
    pagination_limit: 50
    instructions: ~

    client_transports:
        stdio: false                              # enables mcp:server command
        http:  false                              # enables _mcp_endpoint route

    apps:
        enabled: ~                                # null=auto, true|false forced

    http:
        path: '/_mcp'                             # default; controller bound to this path
        allowed_hosts: ~                          # null=SDK default (localhost), list<string>, or false
        session:
            store: 'file'                         # file | memory | cache | framework
            directory: '%kernel.cache_dir%/mcp-sessions'  # file backend
            cache_pool: 'cache.mcp.sessions'      # cache backend (PSR-16 wrapper around cache.app if missing)
            prefix: 'mcp-'                        # file/memory/cache/framework key prefix
            ttl: 3600                             # seconds, min 1
```

Notes:

- The default HTTP path is `/_mcp`, NOT `/mcp`.

- The `cache` backend auto-creates a default pool (`cache.mcp.sessions` as `Psr16Cache` wrapping `cache.app`) only when the configured pool id matches and the pool does not yet exist.

- `allowed_hosts` validation: must be null, false, or an array of hostnames; anything else is rejected at config compile time.

## Service IDs

| Service id | Type | Where |
|---|---|---|
| `mcp.registry` | `Mcp\Capability\Registry` | services.php |
| `mcp.server.builder` | `Mcp\Server\Builder` | services.php (factory: `Mcp\Server::builder()`) |
| `mcp.server` | `Mcp\Server` | services.php (factory: `mcp.server.builder->build()`) |
| `mcp.session.store` | one of `FileSessionStore` / `InMemorySessionStore` / `Psr16SessionStore` / `FrameworkSessionStore` | McpBundle::configureSessionStore() |
| `mcp.psr17_factory` | `Http\Discovery\Psr17Factory` | configureClient() |
| `mcp.psr_http_factory` | `Symfony\Bridge\PsrHttpMessage\Factory\PsrHttpFactory` | configureClient() |
| `mcp.http_foundation_factory` | `Symfony\Bridge\PsrHttpMessage\Factory\HttpFoundationFactory` | configureClient() |
| `mcp.middleware_factory` | `Symfony\AI\McpBundle\Http\MiddlewareFactory` | configureClient() |
| `mcp.server.controller` | `Symfony\AI\McpBundle\Controller\McpController` | configureClient() |
| `mcp.server.command` | `Symfony\AI\McpBundle\Command\McpCommand` | configureClient() |
| `mcp.server.debug_command` | `Symfony\AI\McpBundle\Command\DebugCommand` | configureClient() |
| `mcp.server.route_loader` | `Symfony\AI\McpBundle\Routing\RouteLoader` | configureClient() |
| `mcp.data_collector` | `Symfony\AI\McpBundle\Profiler\DataCollector` | configureClient() (kernel.debug only) |
| `mcp.app.renderer` | `Symfony\AI\McpBundle\App\McpAppRenderer` | configureApps() (Twig only) |
| `mcp.app.reference_handler` | `Symfony\AI\McpBundle\App\McpAppReferenceHandler` | McpPass::configureAppReferenceHandler() |

## See also

- `references/patterns.md`

- `references/gotchas.md`
