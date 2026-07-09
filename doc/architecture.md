# Architecture

## Overview

fossci is a single application, written in [Luam](https://github.com/BenSiv/luam),
that sits alongside a Fossil repository rather than inside it. It is built
the same way `luametry` and `brain-ex` are: source files bundled and
statically linked against a `luam` checkout into one self-contained
binary (see `bld/build.sh`).

```
                     +------------------+
                     |   Fossil (fork)  |   version control, auth,
                     |  wiki / timeline |   permissions, knowledge mgmt
                     +--------+---------+
                              |  HTTP/JSON API (wiki read/write)
                              |  read-only SQLite access (auth check)
                     +--------v---------+
                     |      fossci      |
                     |  entity ledger   |
                     |  registration UI |
                     |  event bus       |
                     |  extensions      |
                     +--------+---------+
                              |
                     +--------v---------+
                     |   SQL storage    |   entity_event (ledger)
                     | (sqlite -> pg)   |   <entity_type> (projections)
                     +------------------+
```

Fossil is never modified. Everything fossci-specific -- the entity ledger,
the registration workflow, the event bus, the extension runtime -- lives
in this one codebase, callable against any Fossil repository that exposes
its normal API.

## Why Fossil, unmodified

An earlier design explored embedding a scripting runtime directly inside
Fossil's C source (replacing or extending TH1). That path required
porting ~100 host command bindings, inventing a taint-tracking system Lua
has no native equivalent for, and accepted an ongoing merge-conflict tax
against every future Fossil release. None of that is necessary once the
extension/entity system is a separate process talking to Fossil over its
existing interfaces. Fossil stays close to upstream indefinitely; fossci
evolves independently.

## The entity ledger: event-sourced, not file-versioned

Two options were considered for "100% traceability": version-controlled
files (one file per entity, committed like everything else), or an
append-only event ledger in SQL with a materialized current-state
projection. Files-in-a-VCS were rejected because the explicit requirement
is real downstream analytics -- diffing YAML files doesn't give you fast
joins and aggregations for a dashboard. Event-sourced SQL gives you both:
full version history (nothing is ever overwritten, only appended) *and*
a normal queryable table for every entity type.

```
entity_event                              <entity_type> (e.g. "reagent")
  event_id      (monotonic, the version)    id
  entity_id     (stable logical identity)   <field columns, typed>
  entity_type_id                            created_by, created_at
  event_type    create | update | archive   updated_by, updated_at
  field_changes (old/new per field)         last_event_id
  author, timestamp
  source_notebook_entry_id, source_row_id
```

`entity_event` is the ledger -- append-only, the source of truth, and
the answer to "what changed, when, and by whom" for any entity. Each
entity type also gets a real typed SQL table generated from its schema
definition, kept in sync in the same transaction as the event insert.
That's what a dashboard queries; nothing about analytics touches the
ledger directly.

### SQLite now, Postgres later

Luam ships a working SQLite binding (`lib/sqlite`, used via
`database.lua`'s `local_query`/`local_update`, the same pattern `brain-ex`
already uses) and no Postgres binding exists yet. So v0 runs on SQLite --
it's real, it's available, and it's enough to prove the ledger and
projection design end to end. The database access layer (`src/db.lua`)
is written as a small adapter specifically so that swapping the backend
later, when dashboard/analytics concurrency actually demands it, doesn't
require touching the ledger or entity logic above it.

## Fossil integration

- **Auth**: fossci opens a read-only connection to Fossil's own
  repository SQLite file to validate session state and look up
  capability strings -- reusing Fossil's actual login system rather than
  reimplementing one.
- **Notebook entries**: authored as Fossil wiki pages. Registration
  Tables are a specific HTML/JS block embedded in the wiki page's raw
  HTML (which Fossil already permits); fossci's JS hydrates that block
  into an interactive widget that calls back to fossci's own API.
  No Fossil-side change is required for this.
- **Schema and extension files**: version-controlled as files in the
  Fossil repository (`schemas/`, `extensions/`). Fossil has no native
  push webhook (confirmed still-open upstream:
  `elabftw`-adjacent issue tracking aside, Fossil's own
  `Webhook for process automation` request has sat open since 2022), so
  fossci polls the timeline/JSON API for commits touching those paths on
  a short interval rather than waiting for a push.

## Extension sandboxing: pure Luam, no C required

Because the whole system -- host and extensions alike -- is Luam, capability
scoping doesn't need a second language runtime or a C-level trust
boundary. It uses the same technique Luam's own test suite already
demonstrates (`tst/test_readonly.lua` in the luam repo): load untrusted
code with `loadstring`, build a restricted environment table exposing
only what that extension's manifest declares, and bind it with
`setfenv(f, sandbox_env)` before calling it. A validation rule gets
read-only entity lookups; an extension that declares `net: outbound`
gets the socket library added to its environment; nothing gets more than
it explicitly asked for and was granted.

```lua
local sandbox_env = build_env_for(extension.capabilities)
local fn = loadstring(extension.source, extension.name)
setfenv(fn, sandbox_env)
local ok, result = pcall(fn, new, old, ctx)
```

This mirrors the capability-manifest design worked out for the
Luam-in-Fossil version of this idea, just without ever needing to touch
Fossil's C code or invent a second sandboxing mechanism -- Lua's own
5.1-era `setfenv`/`getfenv` primitives (which Luam preserves) are already
enough.

## Event model

- **Before-hooks** (`entity.before_create`, `entity.before_update`,
  `registration.before_submit`): synchronous, inside the write
  transaction, can return `{field, severity, message}` issues that block
  the commit. This is where validation rules live.
- **After-hooks** (`entity.after_create`, `notebook.after_save`, ...):
  asynchronous, fire after the transaction commits, cannot block or roll
  anything back. This is where integrations and derived-entity automation
  live -- a slow or broken extension can never hang or corrupt a user's
  data-entry transaction.
