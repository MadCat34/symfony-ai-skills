# Changelog

Versions of this documentation suite are tagged against the [symfony/ai](https://github.com/symfony/ai) monorepo. See README § Maintenance for the refresh policy.

## [Unreleased]

## [0.12.0] - 2026-08-27

Initial release: 8 agent skills (Platform, Agent, Chat, Store, AI Bundle, MCP Bundle, Mate, Symfony AI orchestrator).

**Corrected same-day**: `agent`, `ai-bundle`, and `chat` initially documented `symfony/ai`'s post-0.13 API (`Agent` with a `toolbox`/`maxToolCalls`/`includeSources` constructor, `exclude_tool_messages`) instead of the real v0.12.0 API (`AgentProcessor` wired as both an input and an output processor, `keep_tool_messages`). The `v0.12.0` tag was moved to the corrected commit before any consumer depended on it.
