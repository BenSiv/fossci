# Project Plan

fossci is a general-purpose scientific entity-tracking, experiment-planning,
and lab-notebook layer, built as a bolt-on to [Fossil](https://fossil-scm.org)
(specifically, [this fork](https://github.com/BenSiv/fossil-scm), which adds
AI-enabled knowledge management on top of stock Fossil). Fossci remains
separate from Fossil's core domain code, but integrates through Fossil's
extension and page-rendering mechanisms. If M1 needs a focused bridge in
this fork, that bridge belongs to Fossil; Fossci still does not duplicate
Fossil's UI or platform services.

See [manifesto.md](manifesto.md) for why this exists and
[architecture.md](architecture.md) for the technical design.

## Division of responsibility

| Concern | Owner |
|---|---|
| Version control, permissions/auth, timeline, artifact history | Fossil (unmodified) |
| Notebook entry text (free-text/markup) | Fossil wiki pages |
| Schema-as-code (entity type definitions) and extension scripts | Fossil-tracked files -- version history for free |
| Entity ledger + projected tables (structured data, queryable) | fossci, own SQL storage |
| Page chrome, forms, tables, navigation, session handling | Fossil (its existing UI) |
| Scientific layouts, entity registration semantics, validation, lineage, queries, extensions | fossci |

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
- Registration layout: fossci supplies Fossil with a declarative description
  of a table bound to an entity type. Fossil renders and hosts the table
  using its own UI, rather than fossci shipping a second web UI.
- Before-hooks: scriptable validation rules, run synchronously, blocking
  the write on any error-severity issue. Fossil surfaces issues inline per
  row and field from fossci's structured result.
- Fossil integration: use Fossil's identity, capabilities, repository,
  wiki, version history, and AI/knowledge-management facilities. fossci
  supplies the scientific-management layer; it does not duplicate them.

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
