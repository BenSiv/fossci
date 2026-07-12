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
--   }
--
-- `extra_css` is appended to whatever Fossil's own "css" config value
-- already contains (idempotently, marked by a fixed comment pair), not
-- a replacement -- Fossil's "css" setting is normally the *entire*
-- stylesheet, and fossci has no reliable way to read the compiled-in
-- default from Luam. A deployment that wants extra_css to take visible
-- effect must have already seeded a real base stylesheet once (e.g. via
-- Fossil's own /setup_skinedit, or by copying the Fossil build's
-- pub/skins/default/css.txt into that setting) -- a one-time, Fossil-side
-- admin action, same category as setting --extroot itself.

paths = require("paths")
sandbox = require("sandbox")
db = require("db")

layout = {}

CSS_MARKER_START = "/* fossci-layout:extra_css:start */"
CSS_MARKER_END = "/* fossci-layout:extra_css:end */"

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

function merge_css(repo_fossil, extra_css)
    rows = db.query(repo_fossil, "SELECT value FROM config WHERE name = 'css';")
    current = ""
    if rows != nil and rows[1] != nil and rows[1].value != nil then
        current = rows[1].value
    end

    start_pos = string.find(current, CSS_MARKER_START, 1, true)
    if start_pos != nil then
        current = string.sub(current, 1, start_pos - 1)
    end

    new_css = current .. CSS_MARKER_START .. "\n" .. extra_css .. "\n" .. CSS_MARKER_END .. "\n"
    set_config(repo_fossil, "css", new_css)
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
        merge_css(repo_fossil, def.extra_css)
    end
end

return layout
