# Ticketing as generic, prioritized task management

## Status: design exploration, nothing implemented

This is a proposal for how a fossci deployment could implement a generic,
prioritized task/ticket board using primitives fossci already has
(schema-as-code entity types + canned parameterized views), rather than a
new fossci subsystem. It doesn't add anything to fossci's own core; the
point of writing it down here is that the *pattern* is generic (useful to
any deployment), even though any real instance of it (field names, actual
scoring weights) is deployment content, per `project_plan.md`'s division
of responsibility table -- exactly the same reasoning `schema.md`'s
`reagent.lua` example follows.

## Relationship to Fossil's own ticket system

Fossil (the fork fossci sits on) already ships a ticket tracker
(`tkt.c`) -- `layout.lua`'s `search_tkt` setting (see `schema.md`... no,
see `layout.lua`'s own doc comment) toggles Fossil's native ticket search.
That system is Fossil's, not fossci's: it's a separate content type
(`ticket`/`ticketchng` cards in the Fossil repo), rendered by Fossil's own
`/tktview`/`/rptview` pages, with its own schema-free key/value field
model. fossci doesn't touch it and this proposal doesn't either -- it's
about building a *task* entity type inside fossci's own entity ledger
(the same ledger that already holds `reagent`, `experiment`, etc.), which
gets fossci's existing traceability (event-sourced history), validation
(before-hooks), and query surface (`/browse`, `/detail`, ad-hoc `/sql`,
canned `views/`) for free. A deployment could use both side by side --
Fossil's tracker for its own bug-tracking use case, fossci's `task` entity
for lab/project task management -- or treat fossci's as the only one; that
choice belongs to the deployment, not to this doc.

## What already covers this, with zero fossci core changes

| Need | Existing fossci primitive |
|---|---|
| Task fields (title, due date, owner, priority axes, done state) | An ordinary schema file (`schemas/task.lua`), same as any entity type -- see `schema.md` |
| Full history of every edit/reprioritization | The entity ledger (`entity_event`), automatic for any entity type |
| "Assign to me" / "mark done" / retitle | `POST /api/submit` (register/update), same generic flow every entity type gets |
| A prioritized, sorted list view (not just a raw table) | A canned `view` (`views/<name>.lua`: `name`, `title`, `sql`, `param`, `columns`) -- see `src/view.lua` and the real examples under `software`'s `elab/schema/fossci/views/` |
| Validation (e.g. "urgency must be 1-5") | A `before_create`/`before_update` extension, same mechanism any validation rule uses |

Nothing here needs a new fossci feature. The scoring/sorting logic that
makes a task list feel "prioritized" rather than just a plain table lives
entirely in the canned view's own SQL -- exactly the same place
`software`'s existing `views/samples_by_experiment.lua` puts its
`ORDER BY`.

## Field set and prioritization strategy, inspired by brain-ex

[brain-ex](../../brain-ex) (a sibling project, task management over
SQLite) has a real, non-cosmetic prioritization model worth borrowing the
*shape* of, not the code (brain-ex is Lua/SQLite too, but its own CLI, not
a fossci extension):

- **Fields**: `content` (body/title combined), `subject` (a free-text
  project/category grouping), `due_to`, `done` (a timestamp, doubling as
  status -- null means open), `owner`, and two independent 1-5 integer
  axes, `importance` and `urgency`, rather than one collapsed
  "priority" field.
- **Prioritization is computed at read time, not stored.** brain-ex
  derives an `active_urgency` via a `CASE` expression that escalates the
  raw `urgency` value the closer `due_to` gets (e.g. due within a day ->
  forced to 5; within 2 days -> at least 4; ...; no due date -> raw
  `urgency` unchanged), then sorts by `active_urgency * importance`
  descending, with `importance`, then `active_urgency`, then
  nearest-due-date as tiebreakers. This is a plain Eisenhower
  (importance x urgency) matrix with a deadline-driven boost, not a
  generic weighted-scoring engine -- deliberately simple, and it reads
  straightforwardly as one `ORDER BY` expression.
- **Presentation buckets into quadrants** (e.g. "Critical"
  importance>=4 & urgency>=4, "Strategic" high-importance/lower-urgency,
  "Tactical" the reverse, "Backlog" neither) purely for display -- the
  sort itself doesn't need the bucket, just the product.

A `schemas/task.lua` mirroring this would declare `content`/`subject` as
`text`, `due_to` as `date`, `owner` as `text` (or `reference` to a `user`
entity type if one exists), `importance`/`urgency` as `number` (fossci's
`select` type could constrain them to 1-5 if a fixed-value field is
preferred over free numeric input), and `done` as... fossci's ledger
already has `created_at`/`updated_at`/an implicit history per entity, so
"done" could be a `select` field (`open`/`done`) rather than a second
timestamp, since fossci doesn't need a separate completion-time field
when the event ledger already records exactly when that transition
happened.

A companion `views/prioritized_tasks.lua` would carry brain-ex's
`active_urgency`/sort-order SQL directly, adapted to `task`'s real column
names -- this is the one piece that's genuinely SQL logic, not schema
declaration, the same way `software`'s existing views already mix a
`WHERE`/`ORDER BY` with the entity table.

## What's missing today, and why it's still fine for v0

- **No computed/formula field type** (`schema.md`'s "Field types (v0)"
  table lists `text`/`number`/`date`/`select`/`reference`; computed
  fields are explicitly deferred). Not needed here -- the scoring lives in
  the *view's* SQL, not as a stored/computed column on the entity itself,
  so this gap doesn't block anything.
- **No extension-rendered UI** (`project_plan.md`'s deferred list) --
  today a canned view renders as a plain sorted/labeled table via
  fossci's generic view-rendering path, not a colored quadrant board.
  Good enough to prove the model; a genuinely quadrant-styled board would
  need that deferred capability, and isn't worth building until a real
  deployment actually wants the visual, not just the ordering.
- **Cross-entity-type rules are out of scope for before-hooks**
  (`extensibility.md`) -- irrelevant here since a `task`'s own validation
  (e.g. "urgency must be 1-5") only ever needs the entity's own fields.

## Next step, if a deployment wants this

This doc stops at the pattern. A concrete instantiation (real schema
file, real view, real field choices for a specific deployment) belongs in
that deployment's own config, not here -- see `software`'s
`docs/fossci-task-management-plan.md` for Celleste-Bio's planning
version of exactly this.
