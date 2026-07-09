# Extensibility

fossci's extension system has one goal: let the people using the system
for their own science extend it for their own science, without touching
fossci's own source. Everything -- validation rules, event reactions,
integrations -- is a Luam script, version-controlled the same way schema
files are.

## Extension layout

```
extensions/<name>/
  manifest.lua
  main.lua
```

A manifest is a Luam table file, loaded the same sandboxed way a schema
file is (see `schema.md` and `architecture.md`) -- one language for
everything a schema or extension author writes, no separate config
format:

```lua
-- extensions/unique-lot-number/manifest.lua
return {
  name = "unique-lot-number",
  events = {"entity.before_create", "entity.before_update"},
  entity_types = {"reagent"},
  capabilities = {
    read = {"entity"},
    write = {},
    net = "none",
  },
}
```

```lua
-- extensions/unique-lot-number/main.lua
function on_before(new, old, ctx)
  local issues = {}
  if old == nil or new.lot_number != old.lot_number then
    local dup = ctx.query("reagent", {lot_number = new.lot_number})
    if #dup > 0 then
      table.insert(issues, {field = "lot_number", severity = "error",
        message = "Lot number already registered"})
    end
  end
  return issues
end
```

## Event model

| Hook | Timing | Can it block? | Typical use |
|---|---|---|---|
| `entity.before_create` / `entity.before_update` | Synchronous, inside the write transaction | Yes -- returned issues can block the commit | Validation rules |
| `entity.after_create` / `entity.after_update` | Asynchronous, after commit | No | Notifications, derived-entity computation, external sync |
| `notebook.after_save` | Asynchronous, after commit | No | Auto-tagging, indexing |
| `registration.before_submit` / `registration.after_submit` | Around the whole table submit, not just one row | before: yes, after: no | Batch-level checks or reactions |

Before-hooks and after-hooks are deliberately different code paths, not
a timing flag on the same one: a slow or broken after-hook must never be
able to hang or corrupt a user's data-entry transaction, so it doesn't
get the chance to run inside it at all.

## Capabilities

A manifest declares what an extension needs; fossci grants exactly that
and nothing more when it builds the sandboxed environment for that
extension's invocation (see `architecture.md` for the `loadstring` +
`setfenv` mechanism this rests on):

- `read: [entity]` -- read-only lookups into current entity state via
  `ctx.query(entity_type, filter)`. No raw SQL is ever exposed.
- `write: [entity]` -- access to `ctx.create_entity()` /
  `ctx.update_entity()`. Most extensions (especially validation rules)
  declare no write access at all.
- `net: outbound` -- opts into the socket/SSL libraries being present in
  the extension's environment. Absent by default; an extension that
  doesn't declare this has no network access, full stop.

An admin-visible registry approves an extension's declared capabilities
before it becomes active -- an extension can't silently escalate what
it's allowed to touch after the fact.

## What extensions cannot do (v0)

- Render their own UI pages or routes. Event hooks cover the concrete
  cases (integrations, derived-entity automation) without this; it's
  deferred until a real extension needs it, per `project_plan.md`.
- Cross-entity-type rules. A rule is scoped to one entity type's own
  values, plus read-only lookups into others -- it cannot subscribe to
  every entity type at once.
- Anything outside its declared capabilities. There is no "trusted mode"
  escape hatch for extension code; if a script needs more, the manifest
  needs to declare it and an admin needs to approve it.
