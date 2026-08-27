# Changelog

Versions of this documentation suite are tagged against the [symfony/ai](https://github.com/symfony/ai) monorepo. See README § Maintenance for the refresh policy.

## [Unreleased]

Tracks `symfony/ai`'s `main` branch ahead of the 0.13.0 release (not tagged: 0.13.0 has not shipped upstream yet). Per UPGRADE.md ("FROM 0.12 to 0.13"):

- `agent` : `AgentProcessor` removed — `Agent` drives tool calling itself via `toolbox`/`maxToolCalls`/`includeSources`/`toolExecutor` constructor arguments, with `SequentialToolExecutor` as the default `ToolExecutorInterface`.
- `ai-bundle` : `keep_tool_messages` renamed to `exclude_tool_messages` (same value semantics).
- `mcp-bundle` : multi-server support — every option moves under `mcp.servers.<name>`, capabilities are opt-in via a required `registry` key, per-server services replace the old singletons, route name is `_mcp_endpoint_<name>`, default HTTP path `/mcp/<name>`, `mcp:server`/`debug:mcp` gain a server argument/option. New: the bundle can act as an MCP client (`mcp.clients.<name>`) reaching remote servers.
- `mate` : skills are copied into `.agents/skills/mate-<name>/` (safe to commit) instead of symlinked into `vendor/`; `.claude/skills/` mirrors via a relative symlink. `mate/extensions.php` splits editable (`enabled`, `mode`) from tool-written (`state`, `source`, `source_hash`, `hash`, `targets`) fields.
- `platform` : `Result\Stream\ListenerInterface` gains `onError(ErrorEvent)`; Gemini/VertexAI bridges batch `ToolCallComplete` at stream end instead of one per function call (multi-candidate responses excepted).
- `chat`, `store`, `symfony-ai` : no content changes, version metadata aligned with the rest of the suite.

## [0.12.0] - 2026-08-27

Initial release: 8 agent skills (Platform, Agent, Chat, Store, AI Bundle, MCP Bundle, Mate, Symfony AI orchestrator).

**Corrected same-day**: `agent`, `ai-bundle`, and `chat` initially documented `symfony/ai`'s post-0.13 API (`Agent` with a `toolbox`/`maxToolCalls`/`includeSources` constructor, `exclude_tool_messages`) instead of the real v0.12.0 API (`AgentProcessor` wired as both an input and an output processor, `keep_tool_messages`). The `v0.12.0` tag was moved to the corrected commit before any consumer depended on it.
