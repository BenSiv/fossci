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
- [x] Package fossci's binary for deployment under Fossil's `--extroot`
      directory (`bld/package_extroot.sh`); see doc/deployment.md
- [x] Enforce fossci-side authorization from `FOSSIL_CAPABILITIES`
      (requires Check-In capability `i`), since `/ext/*` bypasses
      Fossil's own repo read-capability checks (`src/cgi.lua`)
- [x] Minimal Markdown wiki-page snippet (plain `<iframe>` embed)
      demonstrating a registration table framed inside Fossil's own
      navigation (doc/deployment.md)
- [x] Exercise the packaged deployment end to end against a real Fossil
      server: real repo, real login, real `/ext` dispatch -- found and
      fixed three real bugs in the process (lfs never actually packaged
      in `bld/build.sh`; `--extroot` must be chroot-relative under
      `fossil server`/`ui`; a POST-body deadlock in Fossil's own
      `src/extcgi.c`, fixed in the fossil-scm checkout). No automated
      integration test yet, though -- tst/integration is still empty,
      see note below; this was manual verification.
- [x] Fossil-backed schema and extension discovery: read `schemas/` and
      `extensions/` from the Fossil checkout fossci is deployed
      alongside -- already how `config.schemas_dir()`/`extensions_dir()`
      work, and already exercised for real in the end-to-end test above.
      Decided (see doc/architecture.md, "Fossil integration"): fossci
      requires a live `fossil open`'d checkout, deliberately -- bare-
      repository (checkout-less) serving is out of scope by design

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
