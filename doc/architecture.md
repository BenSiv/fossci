# Architecture

## Overview

fossci is a single application, written in [Luam](https://github.com/BenSiv/luam),
that sits alongside a Fossil repository rather than inside it. It is built
the same way `luametry` and `brain-ex` are: source files bundled and
statically linked against a `luam` checkout into one self-contained
binary (see `bld/build.sh`).

```
                     +------------------+
                     |   Fossil (fork)  |   version control, auth, UI,
                     |  wiki / timeline |   permissions, knowledge mgmt,
                     |                  |   AI tooling
                     +--------+---------+
                              |  /ext CGI dispatch (stock Fossil
                              |  feature, zero fossci-aware code)
                     +--------v---------+
                     |      fossci      |
                     | entity ledger,   |
                     | registration     |
                     | semantics,       |
                     | scientific       |
                     | layouts, rules,  |
                     | lineage, queries |
                     +--------+---------+
                              |
                     +--------v---------+
                     |   SQL storage    |   entity_event (ledger)
                     | (sqlite -> pg)   |   <entity_type> (projections)
                     +------------------+
```

Fossil is the platform, not a service fossci attempts to replace. It owns
the user interface, HTTP surface, identity/capabilities, repository database,
wiki, version history, and the fork's AI/knowledge-management tooling --
and it stays completely unaware that fossci exists. Fossci is the
scientific-management layer: it owns the entity ledger, schema-driven
registration semantics, validation, lineage, query models, and Luam
extensibility, and it renders its own pages. Fossil's only involvement is
relaying requests to it and framing the result, both through Fossil
features that predate and have nothing to do with fossci (see "Fossil
integration" below).

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

Fossil requires zero fossci-specific changes -- not in this fork, not
anywhere. Fossci bolts on entirely through mechanisms that already ship in
stock Fossil for *any* third-party tool, not something built or
special-cased for fossci:

- **`extroot` CGI-extension dispatch** (`src/extcgi.c`, documented in
  `doc/web/serverext.wiki` of the Fossil tree): a repository admin points
  Fossil's CGI launcher at a directory (`extroot: DIR` in the CGI script,
  or `--extroot DIR` for `fossil server`/`ui`/`http`). Requests under
  `/ext/PATH` are relayed to an executable found under `DIR`, run as a
  real child CGI process (`popen2()`), with Fossil's login/capability
  context passed in as environment variables (`FOSSIL_USER`,
  `FOSSIL_CAPABILITIES`, `FOSSIL_NONCE`, ...). Fossci's compiled binary
  *is* that executable -- pure config and deployment, no Fossil source
  touched. `src/cgi.lua` is already written as a CGI program (reads
  `PATH_INFO`/`QUERY_STRING`/`REQUEST_METHOD`, prints `Status:`/
  `Content-Type:` headers) and already reads `FOSSIL_USER` from the
  environment, so it's already shaped for this dispatch path.
- **Fossci renders its own UI.** Because `/ext` hands fossci a full
  request/response cycle, fossci doesn't hand Fossil a layout to render
  (that framing is dropped) -- `src/html.lua` renders fossci's own pages
  directly, the same way it does today.
- **Embedding into Fossil's navigation**: a Markdown-mimetype wiki page
  (or a `/doc/` page) with a plain `<iframe src="/ext/fossci/register?
  type=reagent">` frames a fossci page inside Fossil's chrome. This
  relies on Fossil's existing raw-HTML-in-Markdown allowance
  (`src/markdown_html.c`) -- an `<iframe>` tag, not inline `<script>`, so
  it needs no CSP-nonce cooperation from Fossil either.
- **Schema and extension files** remain version-controlled Fossil files
  (`schemas/`, `extensions/`); fossci reads them directly off disk from
  its own checkout of the repository it's deployed alongside. No Fossil
  change needed for that either -- it's just reading tracked files off
  disk.

**Fossci requires a live, `fossil open`'d checkout to run -- deliberately,
not as a stopgap.** The alternative (fetch schema/extension content
through Fossil's HTTP/JSON API instead, so fossci could run against a bare
repository with no working directory) was considered and rejected: it
would trade a zero-cost, already-working mechanism for real added
complexity (API fetch, auth, caching/invalidation), and it would weaken
the actual point of schema-as-code -- that editing a schema is an
ordinary Fossil commit, not a redeploy. A live checkout can drift (stuck
merges, uncommitted local edits) if left unmanaged, but that's a
solved, well-understood operational problem (the same one any Fossil
checkout has), not a new one fossci introduces. Bare-repository serving
is out of scope by design, not merely deferred.

One consequence to design around: `/ext/*` bypasses Fossil's own
per-repo read-capability checks (`serverext.wiki` says as much
explicitly) -- fossci is responsible for its own authorization decisions,
using the `FOSSIL_CAPABILITIES` env var Fossil provides, rather than
assuming Fossil already gated access before the request reached it.

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
