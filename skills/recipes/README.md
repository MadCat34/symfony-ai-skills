---
title: Symfony AI Recipes Index
target-version: PHP 8.2+ / Symfony 6.4 | 7.4 | 8.0
last-verified: 2026-07-29
---

> Symfony AI is **experimental** : APIs may break between releases. Always check `UPGRADE.md` in the [symfony/ai monorepo](https://github.com/symfony/ai) before upgrading.

End-to-end patterns that compose at least two Symfony AI components together. Each recipe opens with the experimental banner and YAML frontmatter listing the components it composes.

| Recipe | Composes |
|---|---|
| [agent-response-with-source-metadata](agent-response-with-source-metadata.md) | platform, agent, ai-bundle (`HasSourcesInterface`, `AgentProcessor::includeSources`) |
| [audio-transcription-pipeline](audio-transcription-pipeline.md) | platform (Whisper bridge), agent (`SpeechAgent`) |
| [bounded-document-investigation](bounded-document-investigation.md) | platform, agent, ai-bundle (bounded tool calls and structured reports) |
| [chat-with-memory-doctrine](chat-with-memory-doctrine.md) | chat, agent, ai-bundle, doctrine (DBAL message store bridge) |
| [multi-agent-orchestration](multi-agent-orchestration.md) | agent, chat |
| [query-aware-hybrid-retrieval](query-aware-hybrid-retrieval.md) | platform, agent, ai-bundle, store (application-owned query classifier + observable strategy selection) |
| [rag-pinecone](rag-pinecone.md) | platform, store, agent |
| [rag-postgres-pgvector](rag-postgres-pgvector.md) | platform, store, agent |
| [tool-calling-agent](tool-calling-agent.md) | agent, ai-bundle (`#[AsTool]`, `#[IsGrantedTool]`) |

Pick the recipe whose story matches your use case, copy the whole `composer require` block, then the config and service code. Recipes are end-to-end patterns verified against the source tree at the version pinned in their frontmatter; older versions of Symfony AI may require command tweaks (see `UPGRADE.md` in the monorepo).
