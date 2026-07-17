# fossci TODO

## Completed (M0 foundation)
- [x] Project scaffold (src/, tst/, doc/, bld/) matching luam/luametry/brain-ex conventions
- [x] Docs: manifesto, project plan, architecture, schema format, extensibility model
- [x] SQLite-backed event-sourced ledger (`entity_event` + projected typed tables)
- [x] Schema-as-code Luam-table loader, generating/migrating projected tables
- [x] Minimal CLI: `init`, `schema`, `entity`, `ledger`
- [x] Capability-scoped sandbox primitive (`load` + `setfenv`), proven with a trivial example extension
- [x] Test harness: bats CLI tests + Luam unit tests
      **Correction found 2026-07-17, fixed same day**: this checkout's
      `tst/unit/`/`tst/integration/` were actually empty (confirmed via
      `find tst -type f`) despite this being marked done -- see
      `software`'s `docs/fossci-cicd-plan.md` issue #8 for how it was
      found (while planning fossci's CI/CD). Real harness now exists:
      `tst/unit/schema.lua`/`view.lua` (standalone Luam scripts, matching
      luametry's convention) cover `schema.validate` and `view.lua`'s
      join-aware table-guessing/reference-column resolution;
      `tst/integration/*.bats` (schema/entity/view/cgi) exercise the real
      built binary end to end, CLI dispatch and real CGI-mode invocations
      alike, including a regression test for the exact join-resolution
      bug `view.lua`'s fix corrects. `bld/test.sh` runs both (build, then
      unit, then bats), verified end to end including that a real failure
      actually propagates a non-zero exit. This was the fossci-side
      prerequisite blocking the CI/CD plan's Phase 2 test-gate step --
      unblocked now.

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
- [x] **Added 2026-07-18**: interactive entity-relation diagram on the
      Data page (`/` route) -- a `List`/`Diagram` toggle next to the
      existing entity-type list, same page/URL, not a separate route
      (per project discussion). `schema.relationships(db_path)` is new
      pure introspection (same shape as `schema.list`/`schema.fields`):
      walks every registered type's fields for `type == "reference"`,
      returning `{from_type, to_type, field_name}` edges. Layout is a
      circle (not a physics simulation -- deterministic, stable,
      nothing to converge or drift off-canvas), radius scaled to node
      count so labels don't crowd as a deployment registers more
      types. All positioning/SVG markup is computed server-side in
      Luam (`html.render_relation_diagram`) -- the only client-side JS
      (`html.diagram_js`) is hover-to-highlight-relations and
      click-to-browse, the same "server renders, client only handles
      the interaction" split the popover feature already established.

      Verified: new bats test (node-per-type, edge-per-reference-field,
      against the real fixture schemas); all 26 integration tests pass;
      a real headless-browser trace against a local replica (7 realistic
      entity types, 5 reference edges) confirmed the toggle, the circular
      layout, hover-highlighting the right edges/dimming the rest, and
      clicking a node navigating to its `/browse?type=X` page -- all
      working end to end, screenshotted before and during hover.
- [x] **Significant bug found and fixed 2026-07-18** (found while
      investigating "a Notebook page created outside the deployment's
      prefix doesn't show at all" -- that turned out to be the smaller
      of two bugs): `wiki.lua`'s `wiki.fossil_bin()` fell back to a bare
      `os.getenv("FOSSIL_BIN")`, and ultimately a bare `"fossil"` command
      resolved via `PATH`, to locate the real Fossil binary for its
      shell-outs (`fossil wiki list`/`create`/`export`, backing
      `/notebook`, `/wiki-new`, and every internal "does this page
      already exist" check). **Neither ever actually reaches a real HTTP
      request**: fossil-scm's own `/ext` dispatch (`extcgi.c`) calls
      `fossil_clearenv()` then re-populates *only* a small fixed
      whitelist (`azCgiEnv[]` -- GATEWAY_INTERFACE, PATH_INFO,
      FOSSIL_REPOSITORY, etc.) before spawning fossci as a child process
      -- `FOSSIL_BIN` was never in that list, and neither is `PATH`
      itself. So the bare-`"fossil"`-via-`PATH` fallback was broken on
      *every* real production request, full stop -- it only ever
      appeared to work because every prior check of this code (bats
      tests, direct CLI use) invoked fossci directly, bypassing
      fossil-scm's dispatch (and its env-wiping) entirely. Confirmed
      directly against the real production container, not just reasoned
      from source: `env -i sh -c "fossil wiki list -R
      /data/repo.fossil"` reproduces the exact same `fossil: not found`
      a real request hit.

      Fixed generically in fossci (not a Celleste-Bio-specific patch):
      `wiki.fossil_bin(repo_fossil)` now also checks a new deployment
      setting, `fossci-fossil-bin`, read from the repo's own Fossil
      config table -- synced there by `layout.sync()` from a new
      optional `fossil_bin_path` layout.lua field, the exact same
      mechanism `header`/`footer`/`css` already use, chosen specifically
      *because* it doesn't depend on any environment variable surviving
      fossil-scm's own CGI dispatch. `FOSSIL_BIN` itself is still
      checked first (harmless for whatever non-CGI paths, e.g. CLI, do
      still set it), and a bare `"fossil"` remains the final fallback.

      Verified: 4 new Luam unit tests (`tst/unit/wiki.lua`) covering the
      full fallback chain against a scratch config table; all 28
      integration tests still pass; then, to prove this wasn't just
      unit-level, reproduced the *exact* originally-broken scenario
      end-to-end -- a real `fossil cgi` invocation of `/ext/fossci/
      notebook` (fossil-scm's actual dispatch, not a bats-style direct
      binary call) against a repo with the new config value set and
      *no* `FOSSIL_BIN` in the environment -- and confirmed pages that
      previously came back empty (`"No entries yet"`) now list
      correctly. `/wiki-new`'s "does this page already exist" check
      (`wiki.page_exists`) and page creation (`wiki.create_page`) share
      the exact same fixed function, so this likely also silently fixes
      a related, not-yet-separately-reported "New Page" failure mode --
      worth keeping an eye on, not independently reproduced here.
- [x] Entity browse/detail views: `GET /browse?type=X` (table of all
      entities of a type) and `GET /detail?type=X&id=Y` (current field
      values + full ledger history), both pure server-rendered HTML, no
      JS/CSP concerns. `schema.show_json`'s layout-building logic is now
      factored into `schema.layout()` so these reuse it as a native Luam
      table instead of round-tripping through JSON
- [ ] Schema + extension admin UI
- [x] **Security finding, fixed 2026-07-17** (found while adding browse/
      detail, pre-existing, broader than that feature): `entity_type`
      flows unescaped into raw SQL as a table-name (`"SELECT * FROM "
      .. entity_type`, throughout `entity.lua`/`db.lua`) and into a file
      path for schema lookup (`schema.lua`'s `schemas_dir .. "/" ..
      name .. ".lua"`) wherever it comes from a request parameter
      (`params.type`) -- a live SQL-injection and path-traversal surface
      if `entity_type` is ever taken from anywhere less trusted than
      "must exactly match an already-registered schema name". Prior
      code paths only happened to be safe because every call site
      checked the name resolves via `schema.layout`/`schema.fields`
      first, which was incidental, not a deliberate guard. Fixed with
      exactly the dedicated pass this note called for: a new
      `schema.valid_name_syntax(name)` (charset check, `^[a-z_]
      [a-z0-9_]*$`, matching how every real schema names itself),
      applied once, at each of the 8 places in `cgi.lua` where a
      request parameter (`params.type`/`type` for the autocomplete
      endpoint's `ref_type`) becomes an `entity_type` -- `/register`,
      `/browse`, `/detail`, `/api/validate`, `/api/submit`,
      `/api/update`, `/api/preview`, `/api/autocomplete` -- rejecting
      with 400 before the value can reach any raw SQL or path-building
      call. Deliberately a pure syntax check rather than one that also
      queries `schema.list()`: the existing `schema.layout`/
      `schema.is_registered`/`db.table_exists` calls already downstream
      of each of these handlers cover "is this a real registered type,"
      and duplicating that here would just be a second DB round-trip
      for the same fact -- the actual gap being closed is purely
      "can this string possibly be a valid identifier at all."

      Verified: 2 new `schema.lua` unit tests (valid real-schema-name
      shapes accepted; SQL-injection/path-traversal/case/leading-digit/
      empty/nil/non-string shapes rejected) plus 3 new real CGI-mode
      bats tests -- `/browse` and `/api/preview` both given a
      stacked-SQL-statement payload (`sample; DROP TABLE sample;--`)
      and a path-traversal payload (`../../etc/passwd`) as `type`,
      confirmed to get a 400 rather than reaching SQL, with a follow-up
      request confirming the `sample` table and its data genuinely
      survived (not just "returned 400," but "the injection didn't
      fire"). All 24 existing + new bats tests and all unit tests still
      pass.
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

- [x] **Fixed 2026-07-18**: `.btn`/`.btn-primary`/`.btn-secondary`/
      `.btn-delete` existed as three separate, hand-copied inline CSS
      blocks (`render()`, `render_browse()`, `render_sql()`) that had
      quietly drifted apart -- reported live as visible button-styling
      inconsistency (Celleste-Bio's "run and chat buttons" complaint).
      Confirmed via a real rendered-page computed-style comparison, not
      just reading the CSS: `render_sql()`'s copy never had the shared
      `.btn` base at all (no flex-centering, no shared padding/
      transition), and its `.btn-secondary` was a whole font-size step
      smaller (0.85rem vs the others' inherited 0.9rem) -- the "Run"/
      "Generate query" buttons measurably didn't match "Submit Batch"/
      "+ Add Row" elsewhere in the app. Fixed with a new
      `fossci_button_css()` (same pattern as `fossci_container_css()`),
      one shared definition used by all three `render_*` functions; also
      had to add the missing `btn` class to `render_sql()`'s own button
      markup (`class="btn-primary"` -> `class="btn btn-primary"`, same
      for `-secondary`), since the shared CSS split common properties
      into `.btn` deliberately -- markup-only using `.btn-primary` alone
      now gets just the color/variant, not the padding/radius/font-size,
      which was caught and fixed before landing (a real regression during
      the refactor itself, not shipped).

      Verified: all 24 bats + unit tests still pass; a real headless-
      browser trace against a local replica (real fossil-scm + fossci
      binaries, production's actual `layout.lua`/skin config) confirmed
      the "Run" and "Generate query" buttons now have byte-identical
      computed border-radius/padding/font-size/height/display to
      "Submit Batch"/"+ Add Row" -- before the fix they measurably
      differed; after, they match exactly.

      The floating chat-widget toggle button remains visually distinct
      (a round pill FAB, different color/padding system) -- left as is,
      pending confirmation this is an intentional design category
      (floating launcher vs. inline form button) rather than the same
      kind of drift.

- [x] **Fixed 2026-07-18**: the hover-popover preview (`/api/preview`,
      `handle_preview` in `cgi.lua`) showed reference-type fields as
      their raw foreign-key id instead of the referenced entity's name
      -- reported live specifically for a "sample" row's "experiment"/
      "container" fields. Root cause: this was a genuinely separate code
      path from `render_reference_value` (used by `/browse`/`/detail`/
      `/sql`'s own cell rendering, which already resolved references
      correctly) -- `handle_preview`'s own field-rendering loop just did
      `html_escape(tostring(value))` for every field, with no reference
      awareness at all, for any entity type, not just these two; they
      were simply the first ones a real user happened to check.
      Confirmed directly against real production data before fixing (via
      a real CGI-mode call to the live production container, not a
      synthetic repro): the popover showed literal ids `197631`/`197963`
      where the referenced experiment/container rows are actually named
      `exp343`/`Petri dish 9cm`. Fixed by resolving `field.type ==
      "reference"` values through the existing `entity_display_label()`
      before rendering, same as the working code paths already do.

      Verified: new bats test (`/api/preview resolves a reference field
      to the referenced entity's name, not its raw id`); all 25
      integration tests pass; the exact real production row from the
      live bug report re-checked with the fixed binary (copied
      alongside, not yet replacing the deployed one) shows
      `"Experiment: exp343"` / `"Container: Petri dish 9cm"` where it
      previously showed the raw ids.

- [ ] **Investigated 2026-07-18, not reproduced anywhere, needs more repro
      detail from the user**: Celleste-Bio reported the nav-icon hover
      tooltip (`.fossci-nav-label`) never shows on any page. Tested
      twice: first a headless-browser trace against a local replica
      seeded with production's actual skin config (all 7 real nav icons
      across both a fossci page and two genuinely Fossil-native pages,
      `/wiki`/`/timeline` -- every tooltip correct every time); then,
      since that could just mean the replica wasn't faithful enough, a
      second trace against the **real live production site**
      (celleste-lims.com) with a real temporary login session -- same
      result, all 6 real icons (7th is the hidden hamburger button)
      showed `opacity:1`/`visibility:visible` at the correct computed
      position, every time. One real false alarm caught and corrected
      along the way: an initial fast pass (checking computed style
      immediately after the synthetic hover, no settle time) showed
      `opacity:0`/`hidden` for some icons -- not a real bug, just reading
      the CSS transition (`var(--fossci-transition)`, ~0.2-0.3s) before
      it finished; waiting ~400ms after each hover before reading fixed
      it in both environments.

      This means the underlying mechanism has now been verified correct
      against the actual deployed code, on the actual production site,
      with a real session -- twice. Whatever the real user is
      experiencing isn't a positioning/visibility bug in this code as
      exercised here. Needs one of: the specific browser/OS/device (a
      touch-only device wouldn't have a real `:hover` state at all), how
      long they're actually pausing on an icon before giving up, or
      (most useful) a screen recording of the failure.

## Deliberately deferred (see project_plan.md)
- [ ] Live/as-you-type validation
- [ ] Merge-conflict resolution UI for concurrent entity edits
- [ ] Extension-rendered UI pages/routes
- [ ] Cross-entity-type validation rules
