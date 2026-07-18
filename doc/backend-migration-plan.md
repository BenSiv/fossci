# Backend migration plan: dropping Fossil as the substrate

Status: proposal / scoping, not started. Written 2026-07-19 after a
session that hit three separate real bugs traced to Fossil's own CGI
dispatch internals (env-var wiping before spawning `/ext` extensions, a
base CSS rule silently overriding fossci's own styles, an fd-corruption
bug in `fossil server`'s own relay), on top of an existing architectural
mismatch: this project's actual value (schema-as-code, an event-sourced
ledger, generated forms/views) was never built on Fossil's own
version-control machinery -- it lives in a wholly separate SQLite store
fossci manages itself. Fossil today mostly just supplies auth, CGI
hosting, wiki pages, and skin chrome -- see project_plan.md's "Division
of responsibility" table for the current shape this plan proposes to
change.

This doc scopes what changes, in what order, and what's genuinely open --
it is not an implementation plan to execute blindly.

## Settled: fossci is the foundation, not brain-ex

Raised and resolved 2026-07-19: could `brain-ex` (see "What to take from
brain-ex" below) be extended into the actual backend instead -- patched
with real multiuser-safe SQL and agent management, with fossci ported
down to just a front-end/config layer on top of it? **No** -- decided
against, for reasons specific to what each project's core actually is,
not scope discomfort:

- **The data models point opposite directions.** fossci's whole reason
  for being is genericity: any entity type is a Lua table declaring
  fields, and it gets a form, validation, an audit trail (the ledger),
  and query surface for free -- which is *why* `task` already lives
  comfortably as just another entity type (`schemas/task.lua`), not a
  special case. `brain-ex`'s `sql_schema.lua` is the opposite: five
  fixed, hardcoded tables (`notes`, `connections`, `tasks`,
  `agent_sessions`, `agent_messages`), no schema-as-code layer at all --
  confirmed directly by reading it, not assumed. Making brain-ex the
  backend means either bolting fossci's entire generic entity/ledger
  system onto it from scratch (a bigger rewrite than the alternative),
  or permanently forking the data model -- generic entities in one
  system, notes/tasks stuck in brain-ex's fixed tables in another. A
  real regression, not a simplification.
- **The multiuser/SQL-safety rewrite is bigger on brain-ex's side.**
  Every query across `task.lua`/`note.lua`/`knowledge_pool.lua`/
  `vault_to_sql.lua`/`update.lua`/`agent_engine.lua` is string-
  concatenated (see "Explicitly do not port as-is" below), and there's
  no user/session concept anywhere except a hardcoded
  `session_id='default'`. fossci's query layer (`db.lua`) is already
  parameterized and already proven under real multiuser/capability-
  gated use (this session's own SQL-injection fix, among other things)
  -- extending it is strictly less work than retrofitting brain-ex to
  match it.
- **A "brain-ex as a separate service, called over HTTP" split was also
  considered and rejected** -- it doesn't avoid the core problem
  (brain-ex has no user concept at all, so "whose tasks are whose"
  still has no answer), and adds network-call overhead for no benefit.

**Conclusion**: fossci's code (schema/ledger/CGI/rendering) stays the
foundation -- it was already general enough and already independent of
Fossil (see below). What's taken from brain-ex is specific
*subsystems* (agent orchestration, search-ranking, context compaction --
see "What to take from brain-ex, concretely"), ported to operate on
fossci's own entities through fossci's own already-safe query layer,
not brain-ex's tables. brain-ex itself stays untouched and independent,
continuing to be exactly what it's for -- a minimalist personal CLI
tool. This is a one-time source to port *from*, the same way `dkjson`
was vendored once rather than kept as a live upstream dependency; no
ongoing coupling to brain-ex is created or required.

## What's kept, unchanged

Everything in `src/` that doesn't touch Fossil directly carries over
as-is: `schema.lua`, `entity.lua`, `ledger.lua`, `view.lua`,
`template.lua`, `html.lua` (rendering), the diagram/popover features,
the CLI dispatch shape. This is the majority of the codebase by line
count and by the amount of real, tested behavior it encodes -- none of
it needs to change to drop Fossil, because none of it depended on
Fossil beyond the auth/hosting/wiki concerns below.

## What's replaced, and why

| Concern | Today (Fossil) | Proposed replacement |
|---|---|---|
| CGI hosting | Fossil's `/ext` dispatch: `fossil_clearenv()` + a fixed env whitelist, then `popen2()` to this project's binary | A real web server (nginx, or Apache) invoking the *same* binary directly as a plain CGI script or FastCGI responder. cgi.lua already speaks the CGI env-var protocol (`GATEWAY_INTERFACE`/`PATH_INFO`/`QUERY_STRING`/etc.) natively -- this removes the Fossil-specific relay in the middle, not the protocol itself. Biggest single simplification in this plan: minimal code change, since the interface this project already implements doesn't change. |
| Login, sessions, capabilities | Fossil's user table, password hashing, session cookies, CSRF, capability-letter model | New `auth.lua`: bcrypt (via a C binding, statically linked the same way sqlite3/lpeg already are) for password hashing; a stateless HMAC-signed session cookie (timestamp + HMAC, no server-side session store needed at this project's scale); a ported CSRF double-submit-cookie check. A capability/role model close enough to today's letters that `cgi.has_capability`-style checks barely change. |
| Wiki pages (Notebook) | Fossil wiki pages, native editor, native markdown rendering | A `document` entity type (or similar) in fossci's own ledger -- `path`/`content` as ordinary fields, full history via the *existing* `ledger.history()`/`/detail` machinery every other entity type already gets for free. Renaming becomes a plain field update; no name-uniqueness trap (see the wiki-rename research this replaces). Real gap: needs its own markdown renderer (see Open questions). |
| Skin/chrome (header, nav, footer, CSS) | Fossil's skin config table, fought via `!important`-adjacent overrides all session | Owned outright -- `layout.lua`'s CSS becomes the only stylesheet, no more "override Fossil's base `textarea{max-width:95%}`" fights. |
| Storage | Two SQLite files: Fossil's own repo (`repo.fossil`, holding users/wiki/config) + fossci's separate store (`.fossci/fossci.db`, entity/ledger tables) | One SQLite file. Real simplification -- no more "which store does this table live in," no more the `DOCUMENT_ROOT`/`FOSSIL_REPOSITORY` env-var path-resolution dance this session spent real time debugging. |
| Tickets (if used) | Fossil's built-in ticket system | Deferred -- confirm whether `/rptview/1` is actually load-bearing for this deployment (Tickets was just removed from software's own nav in favor of the Tasks entity type) before deciding whether to reimplement or drop. |
| Agent/chat, NL-to-SQL | **Bigger than initially scoped** -- fossil-scm's own fork has real custom infrastructure here, not a thin wrapper: `agent.c`/`agent_web.c` (chat JSON API + semantic search over `ai_note`/`ai_vector` -- real vector embeddings), `agent_store.c`/`agent_th1.c` (session persistence), `cfg/roles/json-default.th1` (RAG-style prompt assembly from system+page-context+retrieved notes), `dev/agents/fossil-gemini-agent.sh` (headless gemini-cli wrapper). Both the chat widget and NL-to-SQL (`software`'s `site-scripts.js`) call this same backend (`/agent-api-v1-session-create`, `/agent-api-v1-chat`) -- confirmed directly, not assumed. | See the new "Agent/chat replacement" section below -- this needs its own real design, not a one-line swap. |

## Phases

### Phase 0 -- new project skeleton -- done 2026-07-19

Bootstrapped at `/root/projects/platform-wip` (placeholder location/name
-- rename both once naming is settled; the build script isolates the
name to two variables, `ENTRY`/`BIN_NAME`, for exactly this reason).
`schema.lua`/`entity.lua`/`ledger.lua`/`view.lua`/`template.lua`/
`html.lua`/`db.lua`/`sandbox.lua`/`extension.lua`/`init.lua` copied
over verbatim; `config.lua` had its Fossil-checkout-marker root-finding
replaced with a plain `DOCUMENT_ROOT`-or-cwd check (no walking up
looking for `.fslckout`/`_FOSSIL_` -- nothing to find); `cgi.lua` had
`layout.sync()` and the `wiki.lua`-backed routes (`/notebook`,
`/wiki-new`, `/wiki-create`) removed, and its capability check
switched from `FOSSIL_CAPABILITIES` to a `AUTH_CAPABILITIES` env var --
same shape, explicitly labeled as an insecure Phase-0 stub pending real
auth. The full bats/unit test suite (32 integration tests + unit
tests, ported from fossci's own with only variable renames) passes
against the new binary, invoked exactly the way a real CGI request
would (`GATEWAY_INTERFACE` etc.), proving the "was already independent
of Fossil" claim empirically rather than by assumption.

Also built during this phase, prompted by a direct question about
traceability (was genuinely unfinished, not just unverified): entities
can now be archived without ever being deleted. `archived_at` (nullable
timestamp, not a boolean -- records *when*, not just *whether*) joined
the other builtin columns; `entity.archive()`/`entity.unarchive()`
wrap the ledger's existing `append_archive` primitive (which already
existed but was never wired to anything); `entity.list()`/`count()`
exclude archived rows by default (`include_archived` opts back in);
`/api/archive`/`/api/unarchive` CGI routes and matching CLI
subcommands. Verified end to end: archiving removes a row from
`/browse`/`entity list` while `/detail`/`entity show` still reach it
directly, and `ledger.history()` shows the archive event sitting
alongside the original create event, never replacing it.

### Phase 1 -- auth (done 2026-07-18)
- `luam/lib/bcrypt/bcrypt.c`: thin Lua C binding over glibc/libxcrypt's
  own `crypt_gensalt`/`crypt_r` bcrypt support -- not a vendored
  bcrypt implementation, and not `crypt_blowfish` as originally
  scoped: verified directly (standalone C probes, then a real
  `require("bcrypt")` through `luam`) that this system's own libc
  already provides correct, real bcrypt, so nothing needed vendoring.
  Wired into `luam/bld/build_libs.sh` (standalone `.so`) and
  platform-wip's `bld/build.sh` (static link), matching the
  sqlite3/lfs pattern -- lives in `luam/lib/`, not duplicated
  per-project, per explicit instruction.
- `luam/lib/hmac/hmac.c`: same reasoning, a thin binding over OpenSSL
  libcrypto's HMAC-SHA256 -- not a vendored pure-Lua SHA/HMAC
  implementation as originally scoped. Verified against the standard
  HMAC-SHA256 test vector via both the binding and `openssl dgst`
  directly. Also wired into both build scripts.
- `platform-wip/src/auth.lua`: user table (login, password_hash, cap,
  archived_at -- same nullable-timestamp archive convention as
  entities, never a hard delete); `auth.login()` (bcrypt-verify,
  rejects archived users); stateless HMAC-signed session cookies
  (`<login>.<expiry>.<hmac>`) -- capabilities are looked up fresh from
  the user table on every request rather than embedded in the cookie,
  so a capability change or archive takes effect on the user's very
  next request, not only after the cookie expires; CSRF via a
  double-submit cookie (`auth.generate_csrf_token`/`auth.verify_csrf`),
  checked against a client-sent `X-CSRF-Token` header on every
  mutating POST route.
- `cgi.lua`: the old `AUTH_USER`/`AUTH_CAPABILITIES`/`AUTH_NONCE`
  env-var stub is gone. Real `/login` (GET form, POST verifies +
  issues cookies) and `/logout` (clears both cookies) routes; every
  other route now resolves `author`/`capabilities` from the verified
  session. `AUTH_NONCE` (Fossil's old per-request CSP nonce) is
  replaced by `auth.generate_nonce()`, generated locally since there's
  no Fossil wrapper providing one anymore.
- New CLI: `platform user add|passwd|capabilities|list|archive|
  unarchive` -- direct replacement for the `fossil user *` commands
  this deployment's startup script and admin workflows used to shell
  out to.
- Test coverage: `tst/integration/auth.bats` (login success/failure,
  archived-user lockout, unauthenticated redirect, tampered-cookie
  rejection, capability-change-takes-effect-immediately, CSRF
  rejection/acceptance) plus `cgi.bats`'s existing route tests now run
  through a real logged-in session rather than an env-var stub.
- Still open from the original Phase 1 scope: no user-admin *page*
  yet (CLI-only for now) -- folded into Phase 2 below, which already
  expected to need one.

### Phase 2 -- CGI hosting (done 2026-07-18)
- Confirmed empirically, not just by inspection: installed Apache
  (mod_cgid) locally, configured a `ScriptAlias` mounting the whole app
  under a URL prefix (`/app -> cgi-bin/platform`, PATH_INFO-based, the
  standard "one script handles a whole subtree" CGI pattern), and
  exercised a real login -> session cookie -> authenticated
  request -> logout cycle over real HTTP. Needed **zero** application
  code changes to make this work, confirming the original hypothesis.
- That same real-hosting test surfaced a genuine, previously-unnoticed
  bug: several links/form-actions/fetch URLs in `html.lua`
  (browse/register/detail navigation, the SQL query iframe and form,
  the templates list) carried a leftover `fossci/`-prefixed (or
  absolute `/ext/fossci/...`) path segment from an old mount-point
  convention this project no longer uses -- every one of them 404'd
  once actually served through a real web server under a URL prefix,
  masked until now because every bats assertion checking these links
  used an unanchored substring match. Fixed to plain relative
  references (resolve correctly under any mount point); added a
  regression test asserting the fix and tightened the assertions that
  missed it. Also deleted two entirely dead render functions
  (`render_wiki_new`, `render_notebook_tree`, both leftover from routes
  removed in Phase 0) found during the same pass.
- Minimal Admin-only user-admin page: `GET /admin-users` (list) +
  `POST /admin-users-create|capabilities|password|archive|unarchive`,
  a thin web UI over the `platform user *` CLI surface, gated on the
  "a" (Admin) capability. Flat, single-segment route names
  (`/admin-users-create`, not `/admin/users/create`) deliberately, so
  this route family can link to itself and back to the listing page
  via plain relative references without needing `../`-style relative
  math -- exactly the bug class just fixed above.
- `require_csrf` extended to accept a submitted token from a parsed
  form field, not just the `X-CSRF-Token` header the JS `fetch()`
  callers use -- a plain HTML `<form>` POST (the admin page's only
  interaction model) has no way to attach a custom header at all.
- Test coverage: 4 new `auth.bats` tests (Admin-capability gating,
  create/capabilities/password/archive/unarchive round-tripping through
  the actual HTTP routes, CSRF rejection via the form-field path) plus
  the link-regression test above. 46 integration tests total, all
  passing.

### Phase 3 -- storage consolidation
- Merge fossci's own store schema into the same SQLite file real user/
  session/capability tables live in. One file, one backup story.

### Phase 4 -- Notebook-as-entity, redesigned as a real tree

Not just "swap the storage, keep the naming convention." Fossil's
wiki-page model forced identity-equals-name (the whole reason this
plan exists -- see the wiki-rename research this phase replaces); a
`document` entity type removes that constraint entirely, so the design
should actually use the freedom, not just relocate the old convention:

- `document` fields: a stable id (free, any entity type gets one),
  `parent_id` (self-reference, nullable = root-level), `title`
  (display name, freely renameable -- a plain field update, no
  collision risk since it's not a global key), `content` (markdown),
  and optionally a *cached, derived* `path` field (recomputed from the
  `parent_id` chain on write, for URLs/breadcrumbs -- source of truth
  is still `parent_id`, not the string).
- Cross-document linking: adopt brain-ex's `[[title]]` /
  `[[subject/title]]` wiki-link convention directly (`vault_to_sql.lua`'s
  `parse_links_str`/`extract_links`) plus its `connections`-table
  shape (a plain directed edge list) for backlinks -- a clean,
  already-proven pattern, and a natural fit now that documents are
  entities with real IDs to link between.
- Rename = a plain `entity.update()` on `title` (and `parent_id` for
  "move to a different folder"); both are just field writes, no
  special-casing, no name-uniqueness trap. Directly resolves the
  original complaint this whole investigation started from.
- Migration script: walk the current Fossil repo's real wiki pages,
  create one `document` entity per page, inferring `parent_id`/`title`
  from the existing `/`-delimited naming convention (a one-time,
  throwaway parse -- the convention stops mattering after this).
  **Given this deployment is a test replica with Benchling and the
  wiki-pages repo as the real sources of truth (confirmed directly,
  not assumed), full multi-revision history does not need to survive
  cutover at all** -- a final-state-only migration is not just
  acceptable but sufficient, which removes what would otherwise be the
  riskiest part of this phase.
- Markdown rendering: needs its own renderer now that Fossil's
  `/wikiajax/preview` is gone (see Open questions -- still open,
  leaning `cmark` shell-out).
- Minimal edit UI: a textarea + preview (reusing whatever markdown
  renderer gets picked), not a wysiwyg editor -- Fossil's wysiwyg wiki
  editor does not carry over and isn't in scope to rebuild.

### Phase 5 -- agent/chat replacement

Confirmed via `brain-ex` (`/root/projects/brain-ex`) as a concrete,
already-working blueprint for most of this -- not just inspiration, see
the dedicated section below for what to port directly vs. rebuild:

- Provider abstraction (`provider.generate(model, system_prompt,
  prompt) -> (result, err)`, dynamically loaded by name) -- the seam
  where Vertex AI/Gemini (kept, direct API call instead of via
  fossil-scm's C code + gemini-cli subprocess) or any other provider
  plugs in.
- DB-backed conversation history + context-window compaction (summarize-
  oldest-except-last-N once a token-estimate threshold is crossed,
  zero-deletion -- rows marked out-of-context, never dropped) --
  replaces `agent_store.c`. Needs one change from brain-ex's version:
  real per-user/per-request session IDs, not a hardcoded single
  session.
- A tool-use protocol (`<tool>/<method>/<args>` / `<done>` tags + a
  bounded turn loop) for letting the agent act (create/update a
  document, query the ledger) -- replaces the MCP-server plan from
  `fossci-agent-compose-plan.md` with something native to this
  project instead of a separate Python process. Needs a **web-native
  confirmation gate** in place of brain-ex's blocking terminal y/N
  prompt for destructive operations -- directly resolves that doc's
  open "execute immediately or wait for confirmation" question: yes,
  gate it, just not via a TTY.
- Semantic search over documents/notes (replacing `agent.c`'s
  `ai_note`/`ai_vector`): `knowledge_pool.lua`'s ranking formula
  (weighted lexical match + optional embedding cosine-similarity +
  tier/reinforcement weighting + duplicate suppression + a relevance
  floor) is a complete, portable algorithm -- pairs naturally with
  SQLite FTS5 for the lexical half (see Open questions) and an
  embeddings provider call for the semantic half.

### Phase 6 -- production cutover
- Given this deployment is a **test replica** (Benchling + the wiki
  pages repo are the real sources of truth, confirmed directly) real
  live-data risk is low for this specific deployment -- a from-scratch
  data start is explicitly acceptable here. Still worth a real runbook
  once a *different*, genuinely-production deployment is on the table
  (a future non-test-replica instance, or this one once it stops being
  a replica): a maintenance-window cutover, a backup immediately
  before, a tested rollback path.

### Deferred / only if needed
- Tickets replacement (pending the "is `/rptview/1` actually used"
  question above).
- Any Fossil-native feature not already covered: file/attachment
  storage (Fossil's own blob store -- needs a filesystem + metadata
  table equivalent if anything currently relies on wiki attachments),
  the project timeline (arguably superseded by per-entity
  `ledger.history()`, but confirm nothing leans on the *global*,
  cross-entity chronological view Fossil's timeline gives today).

## What to take from brain-ex, concretely

A thorough read of `/root/projects/brain-ex/src/{task,note,agent,
agent_engine,vault_to_sql,update,knowledge_pool}.lua` (2026-07-19)
found real, non-cosmetic logic worth porting directly -- not just
"look at this for inspiration." Highest-value, in order:

1. **Task prioritization** -- already adopted (see `task-management.md`
   and `software`'s `views/prioritized_tasks.lua`): the `active_urgency`
   SQL `CASE` expression (escalates urgency as a due date approaches)
   times `importance`, with an Eisenhower-quadrant classifier for
   display. Nothing new needed here; confirmed the existing port was
   the right piece to take.
2. **Knowledge/note search ranking** (`knowledge_pool.search_score`) --
   a complete formula: field-weighted lexical term matching (title x4,
   subject x2, content x1, plus phrase-match bonuses) blended with
   optional embedding cosine-similarity, multiplied by a curation-tier
   weight, plus a heat/retrieval-count reinforcement term, a duplicate-
   suppression penalty, and a hard relevance floor (exclude if neither
   lexical nor semantic score clears a minimum). Directly portable --
   it's arithmetic over fields any equivalent schema would have.
3. **Promotion-readiness classifier** (`review_status_for_item`) -- a
   simple, auditable decision tree (atomicity by word count, duplicate
   status, artifact staleness, tier, retrieval count) for "has this
   note earned promotion to curated/durable status." Worth adopting the
   *rule shape*, tune the actual thresholds for this deployment.
4. **Duplicate detection** -- content-hash + `GROUP BY hash HAVING
   COUNT(*)>1`, canonical = lowest id. Trivial, portable as-is (swap
   the DJB2-variant hash for something better if desired, e.g. plain
   MD5 -- the hash choice isn't load-bearing, the dedup query shape is).
5. **LLM context-compaction algorithm** -- token-estimate a
   conversation, and once a threshold is crossed, summarize everything
   except the last N messages via a dedicated "concise summarizer" LLM
   call, insert the summary as a new message, mark the summarized
   originals out-of-context (never deleted -- full audit history stays
   in SQL, only the live prompt shrinks). A real, reusable pattern for
   the agent replacement (Phase 5).
6. **Agent tool-use protocol** -- `<tool>/<method>/<args>` request tags
   plus a `<done>` terminal tag, parsed with a bounded turn loop (10
   turns), with a permission-gate policy distinguishing destructive
   tool calls (task/note writes, raw SQL) from read-only ones. The
   *policy* (gate destructive ops before executing) is reusable; the
   *mechanism* (a blocking terminal `y/N` prompt) is CLI-specific and
   must become a web-native confirm-before-apply flow instead.
7. **Wiki-link backlinks** -- `[[title]]`/`[[subject/title]]` inline
   link syntax, parsed and stored as a plain directed edge table
   (`connections`). Clean, minimal, and a natural fit for the
   `document` entity redesign in Phase 4.
8. **Provider abstraction** -- `provider.generate(model, system_prompt,
   prompt) -> (result, err)`, optionally `provider.embeddings(model,
   text) -> (vector, err)`, loaded dynamically by name. Confirmed no
   retry/backoff or streaming exists in brain-ex's version -- both
   would need to be added net-new, they're gaps in brain-ex too, not
   something to port from it.

**Explicitly do not port as-is** (real risks in brain-ex's own code,
confirmed by reading it, not hypothetical):
- **All of brain-ex's SQL is string-concatenated with manual quote-
  doubling, not parameterized.** Acceptable-ish for a single trusted
  local user; unacceptable for a multi-user, network-served,
  capability-gated system -- every ported query must become a
  parameterized/prepared statement, matching the discipline this
  project's own `db.quote()`/`db.literal()` already enforce elsewhere
  (see this session's own SQL-injection fix in `cgi.lua`/`schema.lua`
  for exactly why this matters in practice, not just in principle).
- Single hardcoded session id (`'default'`) -- must become real
  per-user/per-request sessions; the schema already supports it, only
  `run_agent`'s hardcoding doesn't.
- `agent_engine.process_tasks` marks a background task done even when
  the agent run itself returned an error -- a real bug, would silently
  swallow failed agent work if ported unchanged.
- Blocking `$EDITOR`/TTY-prompt patterns (`note.lua`'s `edit_note`,
  `agent_tools/bridge.lua`'s confirmation gate) -- assume an
  interactive local terminal; need a genuinely different, web-native
  mechanism, not a direct port.
- The reseeded-RNG `generate_id` scheme -- redundant given SQL
  autoincrement/UUIDs are simpler and don't have its concurrency-unsafe
  reseeding-every-call behavior.
- The legacy `knowledge_pool` table/`record_interaction`/`get_hot_items`
  -- brain-ex's own docs call this dead code superseded by
  `knowledge_items`; don't resurrect it.

## Open questions, not decided here

- **Markdown rendering.** Fossil's `/wikiajax/preview` endpoint is
  currently the *only* markdown-to-HTML renderer in the whole stack
  (used by the wysiwyg-editor live-preview fix from earlier this
  session, among other things). Dropping Fossil drops this too --
  needs either a vendored pure-Lua markdown parser (none evaluated
  yet) or a CLI shell-out to a small, fast, well-tested C
  implementation (e.g. `cmark`), the same pragmatic
  defer-to-a-real-implementation stance already taken for wiki
  versioning and password hashing. Needs its own research pass before
  Phase 4.
- **Full-text/semantic search infrastructure.** Fossil's own `/search`
  (wiki full-text) and `agent.c`'s `ai_vector` semantic search both
  disappear with Fossil. Leaning toward SQLite's built-in FTS5 virtual
  table for the lexical half (well-tested, no new dependency beyond
  confirming Luam's sqlite3 binding has FTS5 compiled in) combined
  with `knowledge_pool.search_score`'s blended-ranking formula above --
  and this could end up strictly better than what exists today, since
  it could span every entity type uniformly, not just wiki content.
  Not decided, needs its own scoping pass.
- **Session storage.** Stateless HMAC cookies avoid needing a session
  table, but that also means no server-side "log this user out
  everywhere" revocation short of rotating the HMAC secret (which logs
  *everyone* out). Acceptable at this scale, but worth stating
  explicitly rather than discovering it later.
- **Does anything actually use Fossil's ticket system?** Confirm
  before committing to ticket-replacement scope.
- **A global activity feed.** Fossil's timeline gave a cross-entity
  chronological view; `entity_event` already has everything needed for
  an equivalent (a plain `ORDER BY created_at DESC` query, no new
  storage) -- likely a small, easy win rather than an open risk, noted
  here so it doesn't get missed.

## Candidate project names

`fossci` (Fossil + CGI, presumably) stops making sense once Fossil is
gone. A few options, aimed at the actual differentiator -- schema-as-
code plus an event-sourced ledger, not any particular scientific
domain (this deployment happens to be a biotech lab, but the platform
itself isn't domain-specific, matching how fossci itself was never
Celleste-Bio-specific):

- **ledgerform** -- literal: a ledger, and the forms schema-as-code
  generates. Plain, describes the two real mechanisms directly.
- **schemabook** -- schema-as-code plus the notebook/document angle
  from Phase 4.
- **tallyroot** -- "tally" (a ledger/count) + "root" (schema roots,
  and a nod to being the foundation layer under a deployment).
- **lualedger** -- keeps the Lua/Luam heritage visible, plain and
  unambiguous about what it is.
- **traceform** -- "trace" (audit trail/history) + "form"
  (schema-driven forms), doesn't lock in "ledger" as jargon a new
  reader would need explained.

No strong recommendation among these -- pick on sound/memorability;
all five accurately describe the actual mechanism rather than a
borrowed domain metaphor.
