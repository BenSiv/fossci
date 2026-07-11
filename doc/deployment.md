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

- If Fossil runs via `fossil server`/`ui`/`http`, add a flag:

  ```bash
  fossil server /path/to/repo.fossil --extroot /absolute/path/to/<checkout>/.ext
  ```

Requests to `/ext/fossci/*` are now relayed to `bin/fossci` as a child CGI
process, with `FOSSIL_USER`, `FOSSIL_CAPABILITIES`, `FOSSIL_NONCE`, and the
rest of the standard CGI environment set for it (`src/extcgi.c` in the
Fossil tree). For example, `/ext/fossci/register?type=reagent` invokes
`bin/fossci` with `PATH_INFO=/register` and `QUERY_STRING=type=reagent`,
matching `src/cgi.lua`'s routing.

### Authorization

`/ext/*` bypasses Fossil's own per-repo read-capability check (Fossil
documents this explicitly), so fossci enforces its own: every request must
carry the `i` (Check-In) capability in `FOSSIL_CAPABILITIES`, checked in
`cgi.handle_request` (`src/cgi.lua`) before anything else runs. A user
without check-in rights on the Fossil repository gets `403 Forbidden` from
fossci itself, regardless of what Fossil's own page would have allowed.

## 4. Embed in a Fossil page

Fossci renders its own pages; Fossil doesn't need to understand their
content, only frame them. A Markdown-mimetype wiki page (Fossil allows raw
HTML there) can embed a registration table with a plain iframe -- no
inline `<script>`, so no CSP-nonce cooperation from Fossil is needed:

```html
<iframe src="/ext/fossci/register?type=reagent"
        style="width:100%;height:600px;border:0;"></iframe>
```

Create or edit a wiki page with mimetype `text/x-markdown` and drop that
tag in where the registration table should appear.
