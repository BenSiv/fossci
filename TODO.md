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
- [x] Registration-table CGI flow: fossci renders and serves its own
      `/register`, `/api/autocomplete`, `/api/validate`, `/api/submit`
      (`src/cgi.lua`), including before-hook validation with structured
      per-row/field issues rendered by fossci itself
- [ ] Package fossci's binary + config for deployment under Fossil's
      `--extroot` directory (`doc/web/serverext.wiki` mechanism in the
      Fossil tree) -- zero Fossil changes, pure deployment
- [ ] Read `FOSSIL_USER` / `FOSSIL_CAPABILITIES` / `FOSSIL_NONCE` env vars
      (already injected by Fossil's `/ext` dispatch) for identity/
      capability context; enforce fossci-side authorization, since
      `/ext/*` bypasses Fossil's own repo read-capability checks
- [ ] Minimal Markdown wiki-page snippet (plain `<iframe>` embed)
      demonstrating a registration table framed inside Fossil's own
      navigation
- [ ] Fossil-backed schema and extension discovery: read `schemas/` and
      `extensions/` from the Fossil checkout fossci is deployed
      alongside -- no Fossil change needed, just reading tracked files

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
