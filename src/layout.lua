-- Layout-as-code: a deployment's site-wide navigation/branding as one
-- versioned Luam file (layout.lua at the checkout root -- see
-- doc/deployment.md), synced the same way schema.sync_all() applies
-- schemas/*.lua: read on every request, written straight into Fossil's
-- own repository config table (never Fossil source). This is what makes
-- project name, nav tabs, and index page deployer-editable data instead
-- of a one-off manual `fossil sql` edit.
--
-- Shape (all fields optional):
--   return {
--       project_name = "...",
--       short_project_name = "...",
--       index_page = "/wiki?name=...",
--       nav = {
--           {label = "Home", url = "/home"},
--           {label = "Notebook", url = "/wiki", capability = "*"},
--       },
--       extra_css = "nav.mainmenu { ... }",
--       custom_js_path = "assets/wikiedit-wysiwyg.js",
--       footer_extra = "<script src=\"/script.js\"></script>",
--       header_extra = "<script nonce=\"$nonce\">...</script>",
--       search_wiki = true,
--       search_tkt = true,
--   }
--
-- `search_wiki`/`search_tkt` map directly to Fossil's own "search-wiki"/
-- "search-tkt" settings (src/search.c) -- both false by default in a
-- fresh repo, so a header_extra/nav "Search" link is otherwise a dead
-- end ("Search is disabled"). Declared here rather than fixed with a
-- one-off `fossil set`, for the same reason project_name/nav/etc. are:
-- surviving a fresh re-init without a manual step being silently missed.
--
-- `extra_css`/`footer_extra`/`header_extra` are appended to whatever
-- Fossil's own "css"/"footer"/"header" config values already contain
-- (idempotently, each marked by its own fixed comment pair), not a
-- replacement -- all three are normally Fossil's *entire* value for
-- that setting, and fossci has no reliable way to read the compiled-in
-- default from Luam. A deployment that wants any of them to take
-- visible effect must have already seeded a real base value once (e.g.
-- via Fossil's own /setup_skinedit, or by copying the matching
-- pub/skins/default/{css,footer,header}.txt content into that setting)
-- -- a one-time, Fossil-side admin action, same category as setting
-- --extroot itself.
--
-- `custom_js_path` reads a JS file from the checkout and merges it into
-- Fossil's own "js" setting, served at /script.js -- nothing on any
-- page loads that by default, so it's typically paired with
-- footer_extra adding a <script src="/script.js"> tag (once a base
-- footer has been seeded, per above).

paths = require("paths")
sandbox = require("sandbox")
db = require("db")

layout = {}

CSS_MARKER_START = "/* fossci-layout:extra_css:start */"
CSS_MARKER_END = "/* fossci-layout:extra_css:end */"
JS_MARKER_START = "/* fossci-layout:custom_js:start */"
JS_MARKER_END = "/* fossci-layout:custom_js:end */"
FOOTER_MARKER_START = "<!-- fossci-layout:footer_extra:start -->"
FOOTER_MARKER_END = "<!-- fossci-layout:footer_extra:end -->"
HEADER_MARKER_START = "<!-- fossci-layout:header_extra:start -->"
HEADER_MARKER_END = "<!-- fossci-layout:header_extra:end -->"

function layout.load(root)
    path = config_layout_path(root)
    if paths.file_exists(path) == false then
        return nil
    end
    file = io.open(path, "r")
    if file == nil then
        return nil, "cannot open layout file: " .. path
    end
    source = io.read(file, "*all")
    io.close(file)

    ok, result = sandbox.run(source, path, sandbox.data_env())
    if ok == nil or ok == false then
        return nil, "error loading layout.lua: " .. tostring(result)
    end
    if type(result) != "table" then
        return nil, "layout.lua must return a table"
    end
    return result
end

-- Kept as a separate helper (rather than requiring "config" at module
-- load time) to avoid a require-cycle risk if config.lua ever needs
-- layout info back -- it doesn't today, but this costs nothing.
function config_layout_path(root)
    config = require("config")
    return config.layout_path(root)
end

HEX_DIGITS = "0123456789abcdef"

-- SQLite's X'...' blob-literal syntax, built by hand rather than
-- through db.quote()/string.format's %s substitution -- verified
-- directly that a quoted-string SQL literal is NOT safe for arbitrary
-- binary (e.g. a real PNG logo): sqlite's own tokenizer rejects it
-- ("unrecognized token") on bytes a plain '...'-with-doubled-quotes
-- literal can't represent, since that quoting scheme is for text, not
-- arbitrary bytes. Hex digits are always plain ASCII, so this sidesteps
-- the whole problem instead of trying to make text-quoting binary-safe.
function to_hex_literal(data)
    parts = {"X'"}
    for i = 1, #data do
        byte = string.byte(data, i)
        high = math.floor(byte / 16)
        low = byte % 16
        table.insert(parts, string.sub(HEX_DIGITS, high + 1, high + 1))
        table.insert(parts, string.sub(HEX_DIGITS, low + 1, low + 1))
    end
    table.insert(parts, "'")
    return table.concat(parts)
end

function set_config_blob(repo_fossil, name, data)
    db.exec(repo_fossil, string.format(
        "INSERT OR REPLACE INTO config(name, value, mtime) VALUES (%s, %s, strftime('%%s','now'));",
        db.quote(name), to_hex_literal(data)
    ))
end

function set_config(repo_fossil, name, value)
    db.exec(repo_fossil, string.format(
        "INSERT OR REPLACE INTO config(name, value, mtime) VALUES (%s, %s, strftime('%%s','now'));",
        db.quote(name), db.quote(value)
    ))
end

-- Fossil parses `mainmenu` as a TCL-style list, so any field containing
-- whitespace (a multi-word label, most often) must be brace-quoted or
-- it silently splits into separate list elements and desyncs every
-- entry after it -- brace every field unconditionally rather than
-- relying on callers to remember which labels happen to have a space.
function build_mainmenu_text(nav_items)
    lines = {}
    for _, item in ipairs(nav_items) do
        capability = item.capability
        if capability == nil then
            capability = "*"
        end
        table.insert(lines, "{" .. item.label .. "} {" .. item.url .. "} {" .. capability .. "} {}")
    end
    return table.concat(lines, "\n") .. "\n"
end

MIME_BY_EXT = {
    png = "image/png", jpg = "image/jpeg", jpeg = "image/jpeg",
    gif = "image/gif", svg = "image/svg+xml", webp = "image/webp",
}

function guess_mimetype(path)
    ext = string.match(path, "%.([%a%d]+)$")
    if ext == nil then
        return "application/octet-stream"
    end
    guessed = MIME_BY_EXT[string.lower(ext)]
    if guessed == nil then
        return "application/octet-stream"
    end
    return guessed
end

function sync_logo(root, repo_fossil, def)
    path = def.logo_path
    if string.sub(path, 1, 1) != "/" then
        path = paths.joinpath(root, path)
    end
    file = io.open(path, "rb")
    if file == nil then
        return
    end
    data = io.read(file, "*all")
    io.close(file)

    mimetype = def.logo_mimetype
    if mimetype == nil then
        mimetype = guess_mimetype(path)
    end
    set_config_blob(repo_fossil, "logo-image", data)
    set_config(repo_fossil, "logo-mimetype", mimetype)
end

-- Shared by css/js/footer: each is normally Fossil's *entire* value for
-- that setting (there's no reliable way for fossci to read the
-- compiled-in default from Luam -- see the file header), so a
-- deployment that wants any of these fields to take visible effect
-- must have already seeded a real base value once (e.g. via Fossil's
-- own /setup_skinedit, or by copying the matching pub/skins/default/*
-- file's content into that setting) -- a one-time, Fossil-side admin
-- action, same category as setting --extroot itself. Idempotent: strips
-- anything from a previous sync's marker onward before appending fresh,
-- so re-syncing never duplicates.
-- Reads a JS file from the checkout (or an absolute path) and merges
-- its content into Fossil's own "js" setting (served at /script.js --
-- see doc/deployment.md). Fossil doesn't reference /script.js from any
-- page by default; something (typically footer_extra, appending a
-- <script src="/script.js"> tag) has to actually load it for this to
-- run anywhere.
function sync_custom_js(root, repo_fossil, def)
    path = def.custom_js_path
    if string.sub(path, 1, 1) != "/" then
        path = paths.joinpath(root, path)
    end
    file = io.open(path, "r")
    if file == nil then
        return
    end
    data = io.read(file, "*all")
    io.close(file)
    merge_config_text(repo_fossil, "js", data, JS_MARKER_START, JS_MARKER_END)
end

function merge_config_text(repo_fossil, config_name, extra_text, marker_start, marker_end)
    rows = db.query(repo_fossil, string.format("SELECT value FROM config WHERE name = %s;", db.quote(config_name)))
    current = ""
    if rows != nil and rows[1] != nil and rows[1].value != nil then
        current = rows[1].value
    end

    start_pos = string.find(current, marker_start, 1, true)
    if start_pos != nil then
        current = string.sub(current, 1, start_pos - 1)
    end

    new_value = current .. marker_start .. "\n" .. extra_text .. "\n" .. marker_end .. "\n"
    set_config(repo_fossil, config_name, new_value)
end

-- Applies `def` (as returned by layout.load) to the Fossil repository
-- at `repo_fossil` (a plain sqlite file path -- Fossil repositories are
-- ordinary sqlite databases with their own "config" table, so this is
-- just another db.exec/db.query target, the same functions used for
-- fossci's own store).
function layout.sync(repo_fossil, def, root)
    if def.logo_path != nil then
        sync_logo(root, repo_fossil, def)
    end
    if def.project_name != nil then
        set_config(repo_fossil, "project-name", def.project_name)
    end
    if def.short_project_name != nil then
        set_config(repo_fossil, "short-project-name", def.short_project_name)
    end
    if def.index_page != nil then
        set_config(repo_fossil, "index-page", def.index_page)
    end
    if def.nav != nil then
        set_config(repo_fossil, "mainmenu", build_mainmenu_text(def.nav))
    end
    if def.extra_css != nil then
        merge_config_text(repo_fossil, "css", def.extra_css, CSS_MARKER_START, CSS_MARKER_END)
    end
    if def.custom_js_path != nil then
        sync_custom_js(root, repo_fossil, def)
    end
    if def.footer_extra != nil then
        merge_config_text(repo_fossil, "footer", def.footer_extra, FOOTER_MARKER_START, FOOTER_MARKER_END)
    end
    if def.header_extra != nil then
        merge_config_text(repo_fossil, "header", def.header_extra, HEADER_MARKER_START, HEADER_MARKER_END)
    end
    if def.search_wiki != nil then
        sync_bool_setting(repo_fossil, "search-wiki", def.search_wiki)
    end
    if def.search_tkt != nil then
        sync_bool_setting(repo_fossil, "search-tkt", def.search_tkt)
    end
    -- Read back by wiki.lua's wiki.fossil_bin() -- a real HTTP request
    -- reaching fossci through fossil-scm's own /ext dispatch has
    -- FOSSIL_BIN (and PATH, and every other env var outside its own
    -- fixed CGI whitelist) wiped before this process even starts, so an
    -- env var can never carry this reliably; the repo's own config
    -- table, synced here exactly like header/footer/css, can.
    if def.fossil_bin_path != nil then
        set_config(repo_fossil, "fossci-fossil-bin", def.fossil_bin_path)
    end
end

-- Fossil's own db_get_boolean() (src/db.c) accepts "1"/"0" among other
-- forms -- used here rather than true/false literals since this is a
-- plain SQL text column, not a typed one.
function sync_bool_setting(repo_fossil, name, enabled)
    value = "0"
    if enabled == true then
        value = "1"
    end
    set_config(repo_fossil, name, value)
end

-- CLI entry point: `fossci layout sync --repo-fossil <path>`.
--
-- layout.sync() otherwise only ever runs from inside cgi.handle_request(),
-- which gates its ENTIRE body (including this call) behind a real
-- check-in-capability check (cgi.lua's REQUIRED_CAPABILITY test) --
-- confirmed live with a direct A/B test: an unauthenticated HTTP hit to
-- /ext/fossci/ (403, no session cookie) left the served css/js/footer
-- completely stale, while the exact same hit with a real admin session
-- (200) refreshed it. A deploy-time reconciliation step has no browser
-- session to offer, so it needs a path that bypasses the capability gate
-- entirely rather than faking a login -- same reasoning as users.do_users
-- being a plain CLI command instead of an HTTP-authenticated one.
function layout.do_layout(cmd_args)
    action = cmd_args[1]

    if action != "sync" then
        print("Usage: fossci layout sync --repo-fossil <path>")
        return
    end

    repo_fossil = layout_find_repo_fossil_arg(cmd_args)
    if repo_fossil == nil then
        print("Usage: fossci layout sync --repo-fossil <path>")
        return
    end

    config = require("config")
    root = config.find_checkout_root()
    def, err = layout.load(root)
    if def == nil then
        print("Error: " .. tostring(err))
        return
    end

    layout.sync(repo_fossil, def, root)
    print("layout.lua synced into " .. repo_fossil)
end

-- users.lua has an identically-shaped helper (same --repo-fossil <path>
-- flag) named find_repo_fossil_arg -- Luam's top-level functions are all
-- plain globals in the same interpreter state (both modules get
-- `require`d into the same fossci.lua process), so an identically-NAMED
-- function here would silently override whichever module loaded second.
-- Named distinctly rather than risking that, same reasoning as this
-- file's own config_layout_path vs users.lua's config_users_path.
function layout_find_repo_fossil_arg(cmd_args)
    for i, a in ipairs(cmd_args) do
        if a == "--repo-fossil" then
            return cmd_args[i + 1]
        end
    end
    return nil
end

return layout
