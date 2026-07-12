# Deployment

fossci bolts onto a running Fossil server entirely through Fossil's
existing, general-purpose `/ext` CGI-extension mechanism (see
[architecture.md](architecture.md#fossil-integration)). This page covers
the operational steps: build, package, point Fossil at it, embed it in a
page. None of it touches Fossil's own source.

## 1. Build

```bash
LUAM_DIR=/path/to/luam ./bld/build.sh
```

Produces `bin/fossci`, a single self-contained binary.

## 2. Package as an extroot extension

```bash
./bld/package_extroot.sh <checkout>/.ext
```

Copies `bin/fossci` to `<checkout>/.ext/fossci` (executable). The target
directory must live inside the Fossil checkout that holds this project's
`schemas/`, `extensions/`, and `.fossci/` store, because
`config.find_checkout_root()` (`src/config.lua`) finds that checkout by
walking *up* from the extension's own directory looking for a
`.fslckout`/`_FOSSIL_` marker file. `<checkout>/.ext` satisfies that with
one step up. Add `.ext` and `.fossci` to the repository's
`ignore-glob` setting so `fossil addremove`/`extras` don't pick up the
binary or the runtime database.

## 3. Point Fossil at it

Fossil's CGI-extension mechanism (`extroot`) is disabled by default and
requires no Fossil source changes -- just repository/server config:

- If Fossil runs as CGI, add a line to the CGI launcher script:

  ```
  repository: /path/to/repo.fossil
  extroot: /absolute/path/to/<checkout>/.ext
  ```

- If Fossil runs via `fossil server`/`ui`/`http`, add a flag -- **but note
  these commands `chroot()` into the repository's own directory by
  default** (`--chroot DIR` overrides it, `--nojail` disables it), so
  `--extroot` must be given as the path *as seen from inside that jail*,
  not the real host-absolute path. If `repo.fossil` and `<checkout>/.ext`
  are siblings (the default layout above), that's simply the same
  subpath with the parent stripped:

  ```bash
  fossil server /path/to/repo.fossil --extroot /.ext
  ```

  Getting this wrong doesn't error at startup -- it fails per-request with
  "extroot is not a directory", because the path is resolved inside the
  jail. Verified against a real `fossil server` instance.

Requests to `/ext/fossci/*` are now relayed to `bin/fossci` as a child CGI
process, with `FOSSIL_USER`, `FOSSIL_CAPABILITIES`, `FOSSIL_NONCE`, and the
rest of the standard CGI environment set for it (`src/extcgi.c` in the
Fossil tree). For example, `/ext/fossci/register?type=reagent` invokes
`bin/fossci` with `PATH_INFO=/register` and `QUERY_STRING=type=reagent`,
matching `src/cgi.lua`'s routing.

**Requires a Fossil build with the `/ext` POST-body relay fix.** Stock
Fossil's `ext_page()` (`src/extcgi.c`) writes the request body to the
child CGI's stdin but doesn't close that pipe until *after* it tries to
read the child's entire response -- any extension that reads its POST
body to EOF before responding (as any normal CGI program does, fossci
included) deadlocks, and so does Fossil. This is fixed in this
fork/checkout; `POST /ext/fossci/api/validate` and `.../api/submit` will
hang indefinitely on a Fossil build without the fix. GET-only endpoints
(`register`, `autocomplete`) are unaffected.

### Reserved query parameter names

Confirmed directly, reproducibly: a request to `/ext/fossci/whatever?name=X`
fails with Fossil's own `404 Not Found: path does not match any file or
script` -- the same error produced when `--extroot` itself is misconfigured
-- even though the extension is set up correctly and the request never
reaches fossci at all. Fossil's `/ext` relay reads the sub-path to relay to
from a CGI parameter literally named `name`, and query-string parameters
get folded into the *same* CGI parameter table before `ext_page()` runs, so
a real `?name=...` in the URL clobbers Fossil's own internal value. `id` was
suspected of the same issue during development but did not reproduce on
closer testing; `type`, `columns`, `entry`, and `page` are confirmed safe.
Bottom line: don't name a fossci query parameter `name` (or, to be safe,
anything you haven't checked). fossci's own routes use `view_name`/
`template_name`/`entity_id` instead, precisely to avoid this.

### Authorization

`/ext/*` bypasses Fossil's own per-repo read-capability check (Fossil
documents this explicitly), so fossci enforces its own: every request must
carry the `i` (Check-In) capability in `FOSSIL_CAPABILITIES`, checked in
`cgi.handle_request` (`src/cgi.lua`) before anything else runs. A user
without check-in rights on the Fossil repository gets `403 Forbidden` from
fossci itself, regardless of what Fossil's own page would have allowed.

## 4. Embed in a Fossil page

Fossci renders its own pages; Fossil doesn't need to understand their
content, only frame them.

**Not inside wiki content.** An earlier version of this doc claimed a
Markdown-mimetype wiki page could embed a registration table with a
plain `<iframe>`. Verified false against a real Fossil build:
`wikiformat.c`'s markup allowlist (`aMarkup[]`) has no entry for
`<iframe>`/`<script>`/`<object>`/`<form>` under *any* wiki mimetype
(`text/x-fossil-wiki`, `text/x-markdown`, or plain text all go through
the same sanitizer) -- Fossil escapes it to an inert
`<span class='error'>&lt;iframe ...&gt;</span>` instead of rendering it,
regardless of mimetype. There is no supported way to get a truly live
embed inside wiki page content. The closest available approximation is
a plain link (`<a>` -- and Markdown's `[text](url)` -- are both
allowed), which fossci's own entry-conversion tooling uses:

```markdown
[Open registration table →](/ext/fossci/register?type=reagent)
```

This opens fossci's page on click rather than embedding it inline.

**Outside wiki content, a real iframe still works.** Any Fossil page
that isn't run through the wiki sanitizer -- a raw file served from the
repository tree via `/doc`, or a custom skin's header/footer template --
can embed one normally, since sanitization is specific to wiki/ticket
content, not universal:

```html
<iframe src="/ext/fossci/register?type=reagent"
        style="width:100%;height:600px;border:0;"></iframe>
```
