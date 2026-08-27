# MCP Bundle : Gotchas

Read this when a recipe misbehaves or you need the real defaults (transport, port, error envelope). Each gotcha is grounded in the bundle source or the SDK files the bundle imports.

## 1. Transport mismatch

If an editor expects STDIO and you serve HTTP (or vice versa), the client silently hangs or errors out:

- Claude Code, Cursor, Windsurf and most editor integrations use **STDIO**. They spawn `php bin/console mcp:server` (NOT `mcp:serve`) and pipe JSON-RPC over stdin/stdout.
- Web clients (hosted LLM agents talking to your remote server) use **HTTP** at `/_mcp` (default path).

You can enable both transports simultaneously : the bundle registers `mcp.server.command` and `mcp.server.controller` independently based on `client_transports.{stdio,http}`. The two transports do not share a session; a session id from one is meaningless to the other.

## 2. Default HTTP path is `/_mcp`, not `/mcp`

From `config/options.php`:

```text
->scalarNode('path')->defaultValue('/_mcp')->end()
```

If the client config says `POST /mcp` and you never set `mcp.http.path`, every request 404s. Set the path explicitly or update the client URL.

## 3. STDIO command is `mcp:server`, not `mcp:serve`

From `Command/McpCommand.php`:

```text
#[AsCommand('mcp:server', 'Starts an MCP server')]
```

Editor configs that use `bin/console mcp:serve` will fail with "Command not found". Always use `mcp:server`.

## 4. Capability negotiation is automatic; do not hand-roll responses

Clients send an `initialize` JSON-RPC request. The bundle's `Mcp\Server` (built via `Mcp\Server::builder()`) emits the response based on what was registered through `Builder::addTool()` / `addPrompt()` / `addResource()` / `addResourceTemplate()`. You do NOT need to write that response yourself : and you should not: the SDK has the protocol-version-aware logic. Under-advertising hides capabilities from the client; over-advertising without registering handlers causes `tools/call` to return `Mcp\Schema\JsonRpc\Error::METHOD_NOT_FOUND` (`-32601`).

## 5. JSON-RPC errors, NOT Symfony HTTP errors

When a tool throws, the SDK converts the exception into a `Mcp\Schema\JsonRpc\Error` envelope with one of the standard codes:

- `-32700` Parse error (`Error::PARSE_ERROR`)
- `-32600` Invalid request (`Error::INVALID_REQUEST`)
- `-32601` Method not found (`Error::METHOD_NOT_FOUND`)
- `-32602` Invalid params (`Error::INVALID_PARAMS`, carries optional `data`)
- `-32603` Internal error (`Error::INTERNAL_ERROR`)
- `-32000` Server error (`Error::SERVER_ERROR`)
- `-32002` Resource not found (`Error::RESOURCE_NOT_FOUND`)

This is what the client expects:

```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "error": { "code": -32602, "message": "city must be a non-empty string" }
}
```

Do NOT throw `Symfony\Component\HttpKernel\Exception\HttpException` or `NotFoundHttpException` from a tool method : those become HTTP 500/404 responses, which the MCP client cannot parse as JSON-RPC. Let exceptions bubble up; the SDK formats them.

If you need to surface a structured error, the bundle's own exception types are `Symfony\AI\McpBundle\Exception\ExceptionInterface` (interface) and `Symfony\AI\McpBundle\Exception\LogicException` (extends `\LogicException`). There is no `McpException` in the bundle : only the SDK's `Mcp\Exception\ExceptionInterface`.

## 6. STDIO stdout pollution breaks the protocol

`StdioTransport` writes JSON-RPC frames to stdout. Anything else on stdout : `echo`, `var_dump`, `print_r`, `printf`, Monolog handlers writing to stdout : interleaves with the protocol and clients parse garbage.

- Default Monolog in CLI writes to stderr. Good.
- If you have a custom handler that writes to stdout, swap it for `php://stderr` or `StreamHandler('/dev/null')`.
- Container compilation messages on stdout (`bin/console` debug output) will break the protocol in dev. The `mcp:server` command does NOT silence container build output : disable any `->setVerbose(true)` kernel options when running it under a client.
- `var_dump(...)` in a tool method is fine for HTTP (response is parsed JSON) but fatal for STDIO.

## 7. DNS rebinding protection on HTTP

The SDK's `StreamableHttpTransport` ships `DnsRebindingProtectionMiddleware` enabled by default, restricted to localhost. The bundle's `MiddlewareFactory` reads `mcp.http.allowed_hosts`:

- `null` (unset): SDK default (localhost only : fine for local dev, blocks public hosts).
- `list<string>`: replace with a `DnsRebindingProtectionMiddleware` restricted to those hostnames.
- `false`: strip the middleware entirely (exposes a public MCP server : required when behind a reverse proxy on a public domain).

```yaml
mcp:
    client_transports:
        http: true
    http:
        allowed_hosts: ['mcp.example.com']   # restrict to a public hostname
# or
        allowed_hosts: false                  # public server, no rebinding protection
```

## 8. Auth via reverse proxy

MCP itself does not define authentication. For HTTP transport:

- Terminate TLS + auth at nginx/Caddy (mTLS, OAuth2 introspection, `auth_request`, `forward_auth`).
- Reject unauthenticated requests with HTTP 401 before they reach `/_mcp` : the SDK will not receive them.
- For STDIO, the security boundary is the OS user that owns the spawned process; the host (editor) is the trust anchor.

If you need per-tool authorization, implement a Symfony Security voter and call `Security::isGranted()` at the top of the tool method. The bundle does not provide a built-in `#[IsGranted]`-style attribute for MCP tools (that exists on `ai-bundle` for AI tool calling, not MCP).

## 9. Resource template limitation

`#[McpResourceTemplate]` is registered for discovery only (`resources/templates/list`); the SDK's `addResourceTemplate` does NOT auto-resolve `users://{id}` to a handler. To implement a templated resource, register the template (for listing) AND handle `resources/read` for matching URIs in your handler : return the resource contents yourself by parsing the URI. Do not assume the SDK does dynamic routing for templates.

## 10. Lifecycle / SIGTERM for STDIO

Editor clients send `SIGTERM` when the user closes the session. The `Mcp\Server\Transport\StdioTransport` handles this gracefully, but if your tool methods hold open resources (DB connections, file handles, cache pools), let exceptions bubble and do not catch `Throwable` at the top level : that prevents the SDK's shutdown hook from running.

For long-running STDIO servers in production (rare : usually editors spawn per session), consider:

- `pcntl_async_signals(true)` if you want custom signal handling
- A graceful drain: stop accepting new requests, finish in-flight ones, close session store (`gc()` on `SessionStoreInterface`)
- The Symfony session store (`FrameworkSessionStore`) is lazy on `gc()` : expired sessions are cleaned up on the next `read()`. No cron required.

## 11. Class-level attribute without `__invoke()` fails compilation

The bundle's `registerMcpAttributes()` autoconfig throws `LogicException` when the attribute is on a class that has no `__invoke()` method:

> The class "X" uses #[McpTool] as a class-level attribute but has no "__invoke()" method. Add an __invoke() method or move the attribute to a method.

This surfaces at container compile time, not at runtime : fix the class or move the attribute to a method.

## 12. Service registration is mandatory

A class carrying `#[McpTool]` (or any other capability attribute) MUST also be a registered container service with autoconfiguration. Otherwise `McpPass` never sees it, `debug:mcp` reports zero capabilities, and the warning text specifically calls this out. Check:

- `config/services.yaml`: `App\` resource with `autoconfigure: true` (Symfony default).
- `#[Autoconfigure(false)]` on the class : remove it.
- Excluded via `App\Excluded\` etc. : include the path.
- For dev-only tools, use Symfony's `#[When('dev')]` attribute.

## 13. Default session store is `file`; check the directory

```yaml
mcp:
    http:
        session:
            store: 'file'
            directory: '%kernel.cache_dir%/mcp-sessions'
```

Default store is `file`. Default directory is the Symfony cache directory. In a Docker container with an ephemeral filesystem, sessions vanish on restart : switch to `framework` (Symfony's `SessionHandlerInterface`) or `cache` (PSR-16) for persistence across deploys.

For multi-process setups (FrankenPHP, Roadrunner), use `cache` (with a shared pool like Redis) or `framework` (with a shared session handler) : the file store will not see sessions created by other workers.

## 14. `apps.enabled` auto-detection

`mcp.apps.enabled` defaults to `null` (= auto). Auto behaviour in `McpAppPass`:

- If `enabled` is `true` OR any service is tagged `mcp.app`: enable the `McpApps` server extension once.
- If `enabled` is `false`: hard-disable : register nothing even if `#[AsMcpApp]` classes exist.
- If `enabled` is `null` and NO `#[AsMcpApp]` exists: do NOT enable the extension.

For an explicit "no apps" deployment, set `apps.enabled: false` to be defensive.

## 15. The bundle is experimental

The bundle's own `README.md` states it is experimental and NOT covered by Symfony's Backward Compatibility Promise. Symfony AI itself is also experimental. Pin versions carefully and read `UPGRADE.md` in the `symfony/ai` monorepo on every upgrade.

## See also

- `references/api.md`
- `references/patterns.md`
- MCP spec: https://spec.modelcontextprotocol.io/
