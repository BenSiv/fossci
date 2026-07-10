# fossci TODO

## Completed (M0 foundation)
- [x] Project scaffold (src/, tst/, doc/, bld/) matching luam/luametry/brain-ex conventions
- [x] Docs: manifesto, project plan, architecture, schema format, extensibility model
- [x] SQLite-backed event-sourced ledger (`entity_event` + projected typed tables)
- [x] Schema-as-code Luam-table loader, generating/migrating projected tables
- [x] Minimal CLI: `init`, `schema`, `entity`, `ledger`
- [x] Capability-scoped sandbox primitive (`load` + `setfenv`), proven with a trivial example extension
- [x] Test harness: bats CLI tests + Luam unit tests

## Next (M1 -- registration workflow)
- [ ] Declarative registration-table layout supplied by fossci and rendered by Fossil
- [ ] Before-hooks: scriptable validation, blocking, structured per-row/field issues for Fossil to render
- [ ] Fossil bridge: identity/capability context and Fossci layout/result exchange, using Fossil's existing extension/page mechanisms
- [ ] Fossil-backed schema and extension discovery from version-controlled repository files

## Later (M2 -- extensibility platform)
- [ ] Extension manifest format + loader/registry
- [ ] Admin-approval registry for declared capabilities
- [ ] After-hooks: async event dispatch, per-extension retry/failure isolation
- [ ] `ctx.create_entity` / `ctx.update_entity` write bindings, capability-gated

## Later (M3 -- analytics path)
- [ ] Postgres adapter for the projection tables (ledger semantics unchanged)
- [ ] Entity browse/detail views
- [ ] Schema + extension admin UI

## Deliberately deferred (see project_plan.md)
- [ ] Live/as-you-type validation
- [ ] Merge-conflict resolution UI for concurrent entity edits
- [ ] Extension-rendered UI pages/routes
- [ ] Cross-entity-type validation rules
