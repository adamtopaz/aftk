# aftk Rewrite Plan

## Purpose

This document captures the current high-level plan for the rewrite of `aftk`.
It is intentionally architectural rather than detailed. Each layer will be refined in follow-up design work.

## Relationship to the main-branch worktree

This rewrite is being developed in a separate worktree alongside the current main-branch worktree.

- **Main-branch worktree**: `/home/dev/aftk`
- **Rewrite worktree**: `/home/dev/aftk_rewrite`

The main-branch worktree serves as the reference point for:

- current behavior,
- the existing server and file-worker,
- the current `informal[...]` elaborator design,
- implementation ideas,
- and comparison during the rewrite.

We will use the main-branch worktree to study the existing system and to get ideas for how some parts of the rewrite should behave or be structured. In practice, AI agents may read files in the main-branch worktree and then make corresponding edits in the rewrite worktree.

This allows for **selective borrowing** from the existing implementation. Small pieces of code, local patterns, or short fragments may be adapted when that is useful. However, the rewrite should **not** be carried out by copying files wholesale from the main-branch worktree, and agents should **not** use file-copy operations such as `cp ...` to transfer implementation files from `/home/dev/aftk` into `/home/dev/aftk_rewrite`.

The intended workflow is: read the old code, understand the relevant behavior or technique, and then implement or edit the new code in this worktree. The goal is a fresh rewrite informed by the main-branch worktree, not a mechanical file transfer or a direct port of whole files or large verbatim snippets.

The rewrite worktree is intended to replace that architecture with a layered design, while preserving or intentionally evolving the behaviors that remain important.

## Overall architecture

The new `aftk` is organized as a layered system:

1. **Knowledge base layer**
2. **Informal layer**
3. **Server and file-worker layer**
4. **Toolkit layer**
5. **AI autoformalization agent layer**

Each layer builds on the one below it. The key design decision is that the **knowledge base is the single source of truth for natural-language knowledge**.

---

## 1. Knowledge base layer

The foundational layer is a knowledge base for natural-language mathematical and technical knowledge.

### Goals

- Create natural-language knowledge
- Modify existing knowledge
- Query and inspect knowledge
- Search across the knowledge base
- Support structured metadata alongside the main text

### Storage model

Natural-language knowledge will be stored in:

- **Markdown** for the main content
- **JSON** for associated metadata

This gives us a human-readable primary representation together with machine-friendly structured data.

### Interaction model

Interaction with the knowledge base will happen through a Lean-based CLI:

```text
lake exe aftk kb ...
```

Here `...` stands for a suite of commands for creating, editing, querying, searching, and otherwise managing knowledge-base content.

### Role in the full system

This layer is the base of the whole architecture. All higher layers that need natural-language information should obtain it from the knowledge base rather than introducing separate storage systems.

---

## 2. Informal layer

On top of the knowledge base sits the **informal layer**.

This layer consists of Lean 4 elaborators and other metaprogramming constructions that connect the natural-language knowledge base to the formal Lean codebase.

### Goals

- Bridge informal, natural-language content and formal Lean developments
- Make knowledge-base nodes directly usable from Lean
- Provide tooling for working with these informal/formal connections

### Key design decision

In the current architecture represented by the main-branch worktree, there are two separate ways of storing natural-language data:

- informal nodes
- an independent knowledge base

In this rewrite, that duplication is removed.

The **knowledge base is the only source of natural-language data**.

For example:

- `informal[a.b.c]` will refer to the knowledge-base node `a.b.c`

This means the informal layer does not define a competing storage model for natural-language content. Instead, it provides the Lean-side mechanisms for using and elaborating references into the knowledge base.

### Interaction model

This layer will also have its own Lean-based CLI:

```text
lake exe aftk informal ...
```

The informal CLI will provide commands for interacting with the informal layer and its connection to the knowledge base.

---

## 3. Server and file-worker layer

On top of the informal layer, we will build the `aftk` server and file-worker.

### Goals

- Preserve the useful behavior of the server and file-worker from the main-branch worktree
- Extend them so they are aware of both the knowledge base and the informal layer
- Support more than Lean-only workflows

### Expanded scope

In the rewrite, the server and file-worker should support:

- interaction with Lean code
- interaction with the knowledge base
- interaction with the informal layer

So while this layer should feel similar in spirit to the current server and file-worker, it will sit on top of the broader layered architecture rather than serving only Lean interaction.

### Role in the stack

This is the operational layer that exposes the core system services for tools, automation, and editor- or agent-driven workflows.

---

## 4. Toolkit layer

On top of the server and file-worker layer, we will build the **toolkit layer**.

This is the first layer that is intended to be developed in **TypeScript** rather than Lean.

### Goals

- Build higher-level tools on top of the `aftk` server and file-worker
- Support agent-driven workflows and external automation
- Package the lower-layer capabilities into practical interfaces for everyday use

### Relationship to the main-branch worktree

This is similar to what we currently do in the main-branch worktree, where we build tools using the `aftk` server/file-worker for use with the pi agent.

In the rewrite, the toolkit layer should play the same general role, but it should sit on top of the new layered architecture and be aware that the lower layers now include not just Lean interaction, but also the knowledge-base and informal layers.

### Role in the stack

This is the tool-construction layer. It is responsible for turning the capabilities exposed by the lower layers into concrete tools that can be consumed by higher-level agent orchestration, including the autoformalization agent layer, as well as other integrations such as pi.

---

## 5. AI autoformalization agent layer

On top of the toolkit layer, we will build the actual **AI autoformalization agent layer**.

This is the layer where we will develop the AI-agent orchestration for the rewrite.

Like the toolkit layer, this layer is also intended to be developed in **TypeScript**. The plan is to use the **pi agent SDK** here, so the orchestration layer should be designed as a TypeScript-based agent system sitting on top of the lower layers.

### Goals

- Orchestrate AI-driven autoformalization workflows
- Use the toolkit layer as the main source of higher-level tools
- Use CLI tools from the lower layers when direct access is useful
- Coordinate work across the knowledge-base, informal, and Lean-facing parts of the system

### Interaction model

This layer is expected to use:

- the **pi agent SDK** and related TypeScript agent infrastructure,
- the **TypeScript toolkit** developed in the previous layer,
- the various **CLI tools** developed in the previous layers,
- and the services exposed by the `aftk` server and file-worker.

In other words, this is the layer that brings the whole stack together into concrete AI-agent behavior.

### Role in the stack

This is the outermost layer. It is where the full architecture is used to drive actual autoformalization agents and workflows.

---

## Layer relationships

The intended dependency structure is:

- **Knowledge base**: foundational data layer
- **Informal layer**: depends on the knowledge base
- **Server/file-worker layer**: depends on both the knowledge base and the informal layer
- **Toolkit layer**: depends on the server/file-worker layer and, through it, the lower layers
- **AI autoformalization agent layer**: depends on the toolkit layer and may also invoke CLI tools from lower layers where appropriate

A core consequence of this structure is:

- natural-language knowledge lives in one place
- Lean metaprogramming features reference that knowledge rather than duplicating it
- higher-level services operate with awareness of both the informal and formal sides of the project
- TypeScript tools can be built on top of stable system services rather than reimplementing lower-layer logic
- AI orchestration can combine toolkit-level abstractions with direct CLI access to lower layers when needed

---

## Guiding principles

As the design is refined, the rewrite should continue to follow these principles:

- **Layered architecture** with clear responsibilities
- **Single source of truth** for natural-language knowledge
- **Lean-native core tooling**, including CLI entry points
- **Human-readable storage** for core content
- **Machine-readable metadata** for structured operations
- **Extensibility** for future workflows, automation, and integrations
- **A TypeScript toolkit layer** built on top of the Lean-based core services
- **A TypeScript AI autoformalization agent layer** that uses the pi agent SDK and orchestrates workflows using the toolkit and lower-layer CLIs
- **Reference-driven reimplementation** when learning from the main-branch worktree
- **Selective borrowing is allowed**, but wholesale file copying and `cp ...`-style transfers are not

---

## Topics to refine later

This document stays high-level for now. Later planning should refine at least the following:

- knowledge-base directory and file layout
- node identity and naming conventions
- JSON metadata schema and validation rules
- query and search behavior
- exact semantics of `informal[...]`
- error handling across all layers
- CLI command structure for `kb` and `informal`
- server/file-worker protocols and responsibilities
- toolkit API surface and tool-building conventions
- pi-agent integration patterns for the toolkit layer
- AI-agent orchestration architecture for autoformalization
- pi agent SDK integration patterns for the AI agent layer
- boundaries between toolkit usage and direct CLI usage in agent workflows

---

## Summary

The rewrite of `aftk` is centered on a layered design:

- a **knowledge base** for markdown-backed natural-language knowledge with JSON metadata,
- an **informal layer** that connects this knowledge base to Lean through elaborators and metaprogramming,
- a **server/file-worker layer** that exposes the combined system for broader interaction and automation,
- a **toolkit layer** in TypeScript that builds practical agent-facing tools on top of those services,
- and an **AI autoformalization agent layer** in TypeScript that uses the pi agent SDK to orchestrate real agent workflows using the toolkit and lower-layer CLIs.

The most important architectural commitment is that the knowledge base becomes the sole repository of natural-language knowledge, with all higher layers built around that fact.
