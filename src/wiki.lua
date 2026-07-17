-- Creates real Fossil wiki pages by shelling out to the `fossil wiki
-- create` CLI (io.popen/os.execute -- confirmed available to fossci's
-- own trusted top-level code, only stripped from the sandboxed
-- extension environment in sandbox.lua). Wiki pages are content-addressed
-- manifest artifacts (delta encoding, hash tree, versioning) -- real
-- Fossil-core machinery, not something to reimplement via raw SQL here,
-- matching the same "defer to Fossil's own CLI" stance already taken
-- for password hashing (see users.lua/sync_users.py).
wiki = {}

-- Both os.execute and io.popen run through the system shell (system()/
-- popen(), no arg-list mode), so every value built from request input
-- must be quoted before it reaches a shell string. Standard POSIX
-- single-quote wrapping: close the quote, emit an escaped literal
-- quote, reopen it.
function wiki.shell_quote(value)
    return "'" .. string.gsub(tostring(value), "'", "'\\''") .. "'"
end

function wiki.fossil_bin()
    bin = os.getenv("FOSSIL_BIN")
    if bin == nil or bin == "" then
        return "fossil"
    end
    return bin
end

-- Returns a plain list of every real wiki page name in the repository
-- (technote/checkin/branch/tag/ticket synthetic pages excluded -- `fossil
-- wiki list` already excludes those by default, see src/wiki.c, unless
-- --show-associated is passed, which this doesn't). One name per line on
-- stdout; used to build a live folder tree from names that follow a
-- "<folder>/<entry>" convention, instead of a one-time static snapshot --
-- see html.render_notebook_tree.
function wiki.list_pages(repo_fossil)
    output_path = os.tmpname()
    cmd = wiki.fossil_bin() .. " --nocgi wiki list -R " .. wiki.shell_quote(repo_fossil) ..
        " >" .. wiki.shell_quote(output_path) .. " 2>&1"
    os.execute(cmd)

    names = {}
    fh = io.open(output_path, "r")
    if fh != nil then
        content = io.read(fh, "*all")
        io.close(fh)
        for line in string.gmatch(content, "[^\n]+") do
            table.insert(names, line)
        end
    end
    os.remove(output_path)
    return names
end

function wiki.page_exists(repo_fossil, name)
    cmd = wiki.fossil_bin() .. " --nocgi wiki export " .. wiki.shell_quote(name) ..
        " - -R " .. wiki.shell_quote(repo_fossil) .. " >/dev/null 2>&1"
    return os.execute(cmd) == 0
end

-- Returns ok, message. On success `message` is fossil's own stdout+stderr
-- (informational); on failure it's the error text to show the user.
function wiki.create_page(repo_fossil, name, content, mimetype, author)
    if repo_fossil == nil or repo_fossil == "" then
        return false, "Not running as a real Fossil CGI extension (FOSSIL_REPOSITORY unset)."
    end
    if name == nil or name == "" then
        return false, "Page name is required."
    end
    if wiki.page_exists(repo_fossil, name) then
        return false, "A wiki page named '" .. name .. "' already exists."
    end
    if content == nil then
        content = ""
    end
    if mimetype == nil or mimetype == "" then
        mimetype = "text/x-markdown"
    end
    if author == nil or author == "" then
        author = "anonymous"
    end

    content_path = os.tmpname()
    output_path = os.tmpname()
    fh = io.open(content_path, "w")
    if fh == nil then
        os.remove(content_path)
        os.remove(output_path)
        return false, "Could not write a temporary file for the page content."
    end
    io.write(fh, content)
    io.close(fh)

    -- --nocgi is required, not cosmetic: Fossil's own main() switches into
    -- CGI-request handling the moment it sees GATEWAY_INTERFACE set (main.c),
    -- and that var (along with REQUEST_METHOD/PATH_INFO/QUERY_STRING) is
    -- always present in THIS process's own env -- Fossil's /ext dispatch set
    -- them via fossil_setenv() to invoke fossci in the first place, and a
    -- plain os.execute()/system() child inherits them. Without --nocgi, this
    -- shells out to what fossil thinks is ANOTHER cgi request, not a CLI
    -- command, and it fails with a confusing "no such file: wiki" (confirmed
    -- by reproducing locally with GATEWAY_INTERFACE set vs unset).
    cmd = wiki.fossil_bin() .. " --nocgi wiki create " .. wiki.shell_quote(name) ..
        " " .. wiki.shell_quote(content_path) ..
        " -R " .. wiki.shell_quote(repo_fossil) ..
        " -M " .. wiki.shell_quote(mimetype) ..
        " -U " .. wiki.shell_quote(author) ..
        " >" .. wiki.shell_quote(output_path) .. " 2>&1"
    exit_code = os.execute(cmd)
    os.remove(content_path)

    output = ""
    ofh = io.open(output_path, "r")
    if ofh != nil then
        output = io.read(ofh, "*all")
        io.close(ofh)
    end
    os.remove(output_path)

    if exit_code == 0 then
        return true, output
    end
    return false, output
end

return wiki
