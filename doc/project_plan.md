# Project Plan

fossci is a general-purpose scientific entity-tracking, experiment-planning,
and lab-notebook layer, built as a bolt-on to [Fossil](https://fossil-scm.org)
(specifically, [this fork](https://github.com/BenSiv/fossil-scm), which adds
AI-enabled knowledge management on top of stock Fossil). Fossil requires
*zero* fossci-specific changes, including in this fork -- fossci integrates
purely through Fossil's existing, general-purpose extensibility features
(the `extroot` CGI-extension dispatch and Markdown/wiki embedding, see
architecture.md), the same mechanisms any third-party tool could use. No
adapter or bridge code for fossci belongs in Fossil, in this fork or
otherwise; fossci still does not duplicate Fossil's UI or platform
services.

See [manifesto.md](manifesto.md) for why this exists and
[architecture.md](architecture.md) for the technical design.

## Division of responsibility

| Concern | Owner |
|---|---|
| Version control, permissions/auth, timeline, artifact history | Fossil (unmodified) |
| Notebook entry text (free-text/markup) | Fossil wiki pages |
| Schema-as-code (entity type definitions) and extension scripts | Fossil-tracked files -- version history for free |
| Entity ledger + projected tables (structured data, queryable) | fossci, own SQL storage |
| Page chrome, overall navigation, session/login, Fossil-native pages | Fossil (its existing UI) |
| Bolt-on dispatch (`/ext/*` CGI relay via `extroot`), request framing (iframe embed in a wiki/doc page) | Fossil (unmodified, stock feature) |
| Registration-table rendering, forms, entity registration semantics, validation, lineage, queries, extensions | fossci (renders its own pages) |

## Milestones

### M0 -- Foundation (this pass)
- Project scaffold, docs, initial source skeleton and test harness.
- Event-sourced entity ledger: append-only event log + projected
  current-state tables, backed by SQLite for v0 (see architecture.md for
  why SQLite now and what the swap-to-Postgres path looks like).
- Schema-as-code loader (Luam-table entity type definitions -- one
  language for everything a schema or extension author writes, see
  schema.md).
- Minimal CLI: `fossci init`, `fossci schema`, `fossci entity`, `fossci ledger`.
- Capability-scoped sandboxed script execution (`load` + `setfenv`), the
  primitive the extension system builds on -- proven out with a trivial
  example extension before anything else is layered on top.

### M1 -- Registration workflow
- Registration layout: fossci renders and serves its own registration
  table for an entity type (already working end to end via
  `/register`, `/api/autocomplete`, `/api/validate`, `/api/submit` in
  `src/cgi.lua`). Fossil hosts it unmodified by relaying to it, not by
  rendering it.
- Before-hooks: scriptable validation rules, run synchronously, blocking
  the write on any error-severity issue. Fossci renders the per-row/field
  issues itself in its own response; there is no hand-off of structured
  issues to Fossil to render.
- Fossil integration (deployment, not code): package fossci's binary for
  Fossil's `--extroot` directory so `/ext/fossci/...` reaches it; consume
  the `FOSSIL_USER`/`FOSSIL_CAPABILITIES`/`FOSSIL_NONCE` environment
  variables Fossil already injects for identity/capability context;
  enforce fossci's own authorization, since `/ext/*` bypasses Fossil's
  repo read-capability checks. Embed via a plain `<iframe>` in a
  Markdown wiki/doc page. No changes to Fossil itself.

### M2 -- Extensibility platform
- Extension manifests: declared event subscriptions + capabilities
  (read/write/net), admin-approval registry.
- After-hooks: async, non-blocking, for integrations and derived-entity
  automation (Slack notifications, computed entities, external syncs).
- Async job queue with per-extension retry and failure isolation.

### M3 -- Analytics path
- Swap (or add, as an option) a Postgres-backed projection layer for the
  entity tables specifically, so dashboards (Superset or otherwise) have
  a real concurrent-write, analytics-grade target without touching the
  ledger's event-sourcing semantics.
- Entity browse/detail views, schema + extension admin UI.

## What's deliberately deferred

- Live/as-you-type validation (submit-time only for now).
- Merge-conflict resolution UI for concurrent entity edits (single-writer
  assumption for v0; conflicting writes are rejected, not merged).
- Extension-rendered UI pages/routes (event hooks cover the concrete
  integration cases without this; revisit once a real extension needs it).
- Cross-entity-type validation rules (each rule is scoped to one entity
  type's own values plus read-only lookups into others).

None of these are architectural dead ends -- they're left out of scope
because the basics need to be solid and used before any of them are worth
building.
