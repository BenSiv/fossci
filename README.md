# fossci

fossci (**Foss**il + **F**ree/**O**pen **S**ource **S**oftware + **Sci**ence)
is a general-purpose scientific entity-tracking, experiment-planning, and
lab-notebook system, built as a bolt-on to [Fossil](https://fossil-scm.org).

It does not fork or modify Fossil. Fossil stays exactly what it already is
-- version control, permissions, wiki, an AI-enabled knowledge layer (see
[this fork](https://github.com/BenSiv/fossil-scm)) -- and fossci adds
structured entity tracking, registration workflows, and scriptable
extensibility on top of it, for whatever science someone is doing. It is
not shaped around any one discipline; see [doc/manifesto.md](doc/manifesto.md)
for why that matters.

## Key ideas

- **Registration tables**: fill in a table inside a notebook entry, and
  each row creates or updates a structured entity -- no separate
  per-entity form required.
- **100% traceability**: entities live in an append-only event ledger,
  never edited in place; schemas, extensions, and notebook text are all
  version-controlled Fossil-tracked files.
- **SQL-native**: the entity ledger projects into real typed tables, so
  downstream analytics and dashboards query normal SQL, not an opaque log.
- **Extensible from day one**: validation rules and event reactions are
  user-authored Luam scripts, capability-scoped and sandboxed, not a
  fixed feature set.

See [doc/architecture.md](doc/architecture.md) for the technical design,
[doc/schema.md](doc/schema.md) for the entity-type format, and
[doc/extensibility.md](doc/extensibility.md) for how extensions work.
[doc/project_plan.md](doc/project_plan.md) has the milestone roadmap.

## Status

Early. M0 (foundation: ledger, schema loader, minimal CLI, sandbox
primitive) is what's in this repository so far -- see
[TODO.md](TODO.md) for what's done and what's next.

## Installation

### Prerequisites

Requires a built [`luam`](https://github.com/BenSiv/luam) checkout
(`gcc`, `sqlite3` dev headers).

### Build

```bash
LUAM_DIR=/path/to/luam ./bld/build.sh
```

Produces `bin/fossci`, a single self-contained binary (no external Luam
runtime needed at run time).

## CLI

```
Usage: fossci <command> [subcommand] [arguments]

fossci init                              initialize a fossci store (sqlite db + config)
fossci schema  < add | list | show >     manage entity type definitions
fossci entity  < create | list | show >  create/inspect entities
fossci ledger  < show | history >        inspect the raw event ledger for an entity
```

## License

MIT -- see [LICENSE](LICENSE).
