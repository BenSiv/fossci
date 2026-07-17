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

## M2 -- extensibility platform
- [x] Extension manifest format + loader/registry (`src/extension.lua`):
      formalizes manifest loading/validation/matching, previously inline
      in `entity.lua`'s before-hook dispatch; `fossci extension list/show`
- [x] Admin-approval registry for declared capabilities: `extension_approval`
      table records the capabilities approved at approval time; a manifest
      edited to request more afterward is treated as unapproved again
      (capability diff, not just presence) until re-approved (`fossci
      extension approve/revoke`) -- closes a real gap where M1's
      before-hooks ran any extension unconditionally, no approval gate
- [x] After-hooks: async event dispatch, per-extension retry/failure
      isolation. fossci is a one-shot CGI/CLI process (no long-lived
      place to run a background timer), so "async" is a job queue
      (`extension_job` table) drained by `fossci extension run-pending`,
      meant to be invoked by whatever the deployer already uses for
      scheduled tasks (cron, etc.) -- fossci doesn't prescribe one.
      Verified: one job per matching approved extension, isolated
      per-job retry (stays 'pending' and retries up to
      `extension.MAX_JOB_ATTEMPTS`, then flips to 'failed'), and a
      permanently-failing extension's job never affects another
      extension's job for the same event
- [x] `ctx.create_entity` / `ctx.update_entity` write bindings,
      capability-gated on `capabilities.write` containing `"entity"`
      (same blanket-capability shape as the existing `read` check, not
      per-entity-type) -- available to both before- and after-hooks
      (`build_ctx` in `entity.lua`)
- [ ] Known gap found while verifying the above, not yet fixed: `net =
      "outbound"` capability is non-functional -- `sandbox.lua` does
      `require("socket")`, but no build (fossci's own `bld/build.sh` or
      its sibling projects) actually compiles/links LuaSocket's native
      core into the static binary; unlike the `lfs` packaging bug found
      earlier, this is a much bigger fix (multiple C sources, possibly
      LuaSec for HTTPS), not attempted yet. No extension has needed real
      network access yet either, so this was never exercised until now.

## M3 -- analytics path
- [ ] Postgres adapter for the projection tables (ledger semantics unchanged)
- [x] Entity browse/detail views: `GET /browse?type=X` (table of all
      entities of a type) and `GET /detail?type=X&id=Y` (current field
      values + full ledger history), both pure server-rendered HTML, no
      JS/CSP concerns. `schema.show_json`'s layout-building logic is now
      factored into `schema.layout()` so these reuse it as a native Luam
      table instead of round-tripping through JSON
- [ ] Schema + extension admin UI
- [ ] **Security finding, not yet fixed** (found while adding browse/
      detail, pre-existing, broader than this feature): `entity_type`
      flows unescaped into raw SQL as a table-name (`"SELECT * FROM "
      .. entity_type`, throughout `entity.lua`/`db.lua`) and into a file
      path for schema lookup (`schema.lua`'s `schemas_dir .. "/" ..
      name .. ".lua"`) wherever it comes from a request parameter
      (`params.type`) -- a live SQL-injection and path-traversal surface
      if `entity_type` is ever taken from anywhere less trusted than
      "must exactly match an already-registered schema name". Today's
      code paths happen to be safe in practice only because every call
      site checks the name resolves via `schema.layout`/`schema.fields`
      first, which is incidental, not a deliberate guard. Needs a
      dedicated pass: a single allowlist/charset check (e.g. `^[a-z_]
      [a-z0-9_]*$` matched against `schema.list()`) applied once,
      centrally, everywhere `entity_type` enters from external input.
- [x] **Known gap, found while auditing the hover-popover rollout
      (`3d50607`), now fixed**: `/sql`'s entity-reference-link resolution
      (`view.reference_columns`, `src/view.lua`) only covered a single,
      unaliased `SELECT ... FROM <table>`, so any query with a join
      silently fell back to the raw id for reference columns belonging to
      the joined table (verified directly: a reference column on a
      joined-but-not-FROM table resolved under the new code, not the
      old). Fixed via a new `view.guess_tables`, which walks every
      `FROM`/`...JOIN` occurrence (all join variants end in the literal
      word "JOIN", so one case-insensitive match covers
      inner/left/right/outer/cross) and merges each table's reference
      columns, first table wins a name collision. `view.reference_columns`
      now takes a list (a bare string still works, for callers that only
      ever guessed one table). Still string-matching, not a real SQL
      parser: comma-joins (`FROM a, b`), subqueries, and CTEs are still
      unresolved -- same silent raw-id fallback as before for those, just
      a narrower set of cases than plain joins now.

## Deliberately deferred (see project_plan.md)
- [ ] Live/as-you-type validation
- [ ] Merge-conflict resolution UI for concurrent entity edits
- [ ] Extension-rendered UI pages/routes
- [ ] Cross-entity-type validation rules
