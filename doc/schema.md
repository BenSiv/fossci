# Schema-as-Code

An entity type is defined as a Luam table file, checked into the Fossil
repository (so its own edit history is versioned like everything else),
one file per type. This is deliberate: fossci already has exactly one
language (Luam) that everyone touching the system -- schema authors,
extension authors, the platform itself -- needs to know. Adding YAML or
JSON as a second, hand-authored format would buy nothing a plain Luam
table doesn't already give for free (comments, no quoting-every-key
friction, and no separate parser to maintain). This mirrors an existing
convention in this ecosystem: `luametry`'s own config
(`~/.config/luametry/settings.lua`) is a `.lua` file that *is* the
config, not a serialization of one.

## Format

```lua
-- schemas/reagent.lua
return {
  name = "reagent",
  fields = {
    {name = "lot_number",    type = "text",      required = true},
    {name = "concentration", type = "number",    required = true},
    {name = "prepared_on",   type = "date",      required = true},
    {name = "status",        type = "select",    required = true,
      values = {"active", "depleted", "discarded"}},
    {name = "prepared_from", type = "reference", required = false,
      entity_type = "reagent"},
  },
}
```

## Field types (v0 -- deliberately five)

| type | meaning |
|---|---|
| `text` | free string |
| `number` | numeric, integer or float |
| `date` | ISO 8601 date |
| `select` | one of a fixed `values` list |
| `reference` | points at another entity by id, optionally constrained to a specific `entity_type` |

A `number` field may optionally declare `min`/`max` -- wired into the
registration table's `<input type="number">` (`min`/`max` attributes,
bounding the native spinner arrows), but **UI-hint only, not enforced
server-side**. A real range constraint (rejecting an out-of-bounds value
on submit) is still a `before_create`/`before_update` extension's job
(see `extensibility.md`) -- `min`/`max` here don't replace that, they
just stop the input widget itself from suggesting an obviously-invalid
value. Consolidating this into a real, DB-enforced schema constraint is
a bigger change (`entity_field` would need new columns) not done yet.

Deferred: multi-select, attachments/files, rich text, computed/formula
fields, server-enforced numeric bounds. None of these are ruled out
architecturally -- they're just not needed to prove the core
registration workflow end to end.

## Loading is sandboxed, not just `dofile`

A schema file is executable Luam, not inert data the way a YAML/JSON
file would have been. So it isn't loaded with a bare `dofile`: it runs
through the same `loadstring` + `setfenv` sandbox described in
`architecture.md`, with an environment that can only construct and
return a plain table -- no `os`, no `io`, nothing extension capabilities
would need either. Same security posture a data format would have had,
without needing a second parser to get there.

## What a schema file generates

Loading a schema does two things:

1. Registers (or updates) a row in the `entity_type`/`entity_field`
   tables that the ledger and validation layer read at runtime.
2. Generates (or migrates) a real typed SQL table for that entity type --
   `reagent(id, lot_number, concentration, prepared_on, status,
   prepared_from, created_by, created_at, updated_by, updated_at,
   last_event_id)` -- the thing a dashboard actually queries.

Schema changes are themselves ordinary Fossil commits: renaming or adding
a field is a diff against `schemas/reagent.lua`, reviewable and
revertable the same way any other change to the repository is.

## Where JSON still shows up

Only at the actual Fossil API boundary (wiki payloads, auth lookups,
landing in M1) -- because that's Fossil's own wire protocol, not a
format fossci is choosing on its own. Internally, the ledger serializes
`field_changes` as JSON inside a single SQLite column; that's invisible
storage plumbing, not something a schema or extension author ever
writes by hand, so it isn't a format anyone needs to learn.
