db = require("db")
config = require("config")
schema = require("schema")
entity = require("entity")
ledger = require("ledger")
view = require("view")
template = require("template")
html = require("html")
layout = require("layout")
json = require("dkjson")
paths = require("paths")

cgi = {}

-- Fossil's /ext dispatch bypasses the repo's own read-capability check
-- (see doc/architecture.md), so fossci gates itself here. "i" (Check-In)
-- is the closest existing Fossil capability to "real contributor with
-- write access"; Setup/Admin logins already carry it via fullcap().
REQUIRED_CAPABILITY = "i"

-- Rows per /browse page. A flat, fixed page size rather than a
-- user-configurable one -- simple, and every entity type here is a
-- plain projected SQL table so COUNT/LIMIT/OFFSET are cheap regardless
-- of size.
BROWSE_PAGE_SIZE = 100

function cgi.has_capability(capabilities, letter)
    if capabilities == nil or capabilities == "" then
        return false
    end
    return string.find(capabilities, letter, 1, true) != nil
end

-- Luam's and/or require boolean operands, so plain "value or default"
-- nil-coalescing (fine in stock Lua) errors here whenever value is a
-- truthy non-boolean (e.g. any real env var/query value) -- exactly the
-- normal-success case, not just an edge case.
function default_value(value, fallback)
    if value == nil then
        return fallback
    end
    return value
end

function parse_query(query_str)
    params = {}
    if query_str == nil then return params end
    for k, v in string.gmatch(query_str, "([^&=]+)=([^&=]*)") do
        -- simple url decoding for basic params
        decoded_v = string.gsub(string.gsub(v, "+", " "), "%%(%x%x)", function(h)
            return string.char(tonumber(h, 16))
        end)
        params[k] = decoded_v
    end
    return params
end

-- Filters/reorders a schema layout's fields to a comma-separated
-- allowlist, e.g. "?columns=lab_name,volume_ul" -- lets one embedded
-- registration table show only a curated subset of a schema's fields,
-- in a chosen order, the same way a Benchling entry's embedded
-- registration_table note picks its own column list independent of
-- the underlying entity schema's full field list. Unknown/mistyped
-- column names are silently skipped; if that empties the list
-- entirely, falls back to the full layout rather than showing nothing.
function filter_layout_columns(layout, columns_param)
    if columns_param == nil or columns_param == "" then
        return layout
    end
    by_name = {}
    for _, field in ipairs(layout.fields) do
        by_name[field.name] = field
    end
    filtered_fields = {}
    for wanted_name in string.gmatch(columns_param, "[^,]+") do
        field = by_name[wanted_name]
        if field != nil then
            table.insert(filtered_fields, field)
        end
    end
    if #filtered_fields == 0 then
        return layout
    end
    return {name = layout.name, fields = filtered_fields}
end

-- The `entry` query param is the embedding notebook entry's identifier
-- (a wiki page name/URL, whatever the client sent) -- see doc/architecture.md
-- and ledger.lua's source_notebook_entry_id. Optional: absent when
-- fossci is used standalone, not embedded in a notebook entry.
function source_from_params(params)
    source = {}
    if params.entry != nil and params.entry != "" then
        source.notebook_entry_id = params.entry
    end
    return source
end

function print_response(status, content_type, body)
    io.write("Status: " .. status .. "\r\n")
    io.write("Content-Type: " .. content_type .. "\r\n")
    io.write("Content-Length: " .. string.len(body) .. "\r\n")
    io.write("\r\n")
    io.write(body)
end

function handle_autocomplete(db_path, params)
    ref_type = params.type
    query_str = default_value(params.query, "")
    if ref_type == nil or ref_type == "" then
        return print_response("400 Bad Request", "application/json", json.encode({error = "Missing type"}))
    end

    if not db.table_exists(db_path, ref_type) then
        return print_response("200 OK", "application/json", "[]")
    end

    cols = db.get_columns(db_path, ref_type)
    if #cols == 0 then
        return print_response("200 OK", "application/json", "[]")
    end

    search_cols = {}
    for _, col in ipairs(cols) do
        if col == "id" or col == "name" or col == "title" or col == "label" or col == "lot_number" then
            table.insert(search_cols, col)
        end
    end
    if #search_cols == 0 then
        table.insert(search_cols, cols[1])
    end

    where = {}
    for _, col in ipairs(search_cols) do
        table.insert(where, col .. " LIKE " .. db.quote("%" .. query_str .. "%"))
    end

    has_name = false
    for _, col in ipairs(cols) do
        if col == "name" then has_name = true end
    end

    q = nil
    if has_name then
        q = "SELECT id, name FROM " .. ref_type
    else
        text_col = "id"
        for _, col in ipairs(cols) do
            if col != "id" and col != "created_at" and col != "created_by" and col != "updated_at" and col != "updated_by" and col != "last_event_id" then
                text_col = col
                break
            end
        end
        q = "SELECT id, " .. text_col .. " AS name FROM " .. ref_type
    end

    if #where > 0 then
        q = q .. " WHERE " .. table.concat(where, " OR ")
    end
    q = q .. " LIMIT 15;"

    rows = db.query(db_path, q)
    result = default_value(rows, {})
    return print_response("200 OK", "application/json", json.encode(result))
end

function cgi.handle_request()
    path_info = default_value(os.getenv("PATH_INFO"), "/register")
    query_string = default_value(os.getenv("QUERY_STRING"), "")
    method = default_value(os.getenv("REQUEST_METHOD"), "GET")
    params = parse_query(query_string)

    if not cgi.has_capability(os.getenv("FOSSIL_CAPABILITIES"), REQUIRED_CAPABILITY) then
        return print_response("403 Forbidden", "text/html", "<div class='fossil-doc'><h3>Forbidden: requires check-in capability</h3></div>")
    end

    root = config.find_checkout_root()
    db_path = config.db_path(root)

    -- Auto-initialize or sync database schemas on request
    if not config.is_initialized(root) then
        paths.create_dir_if_not_exists(config.store_dir(root))
        paths.create_dir_if_not_exists(config.schemas_dir(root))
        paths.create_dir_if_not_exists(config.extensions_dir(root))
        paths.create_dir_if_not_exists(config.views_dir(root))
        paths.create_dir_if_not_exists(config.templates_dir(root))
        ledger.init_schema(db_path)
    end
    schema.sync_all(db_path, root)

    -- Layout-as-code: written into Fossil's own repo config table, not
    -- fossci's store -- requires FOSSIL_REPOSITORY (only present when
    -- Fossil invokes us as a real CGI extension, not bare CLI use).
    repo_fossil = os.getenv("FOSSIL_REPOSITORY")
    if repo_fossil != nil and repo_fossil != "" then
        layout_def, layout_err = layout.load(root)
        if layout_def != nil then
            layout.sync(repo_fossil, layout_def, root)
        end
    end

    author = os.getenv("FOSSIL_USER")
    if author == nil or author == "" then
        author = default_value(os.getenv("USER"), "anonymous")
    end

    if path_info == "/register" then
        entity_type = params.type
        if entity_type == nil or entity_type == "" then
            return print_response("400 Bad Request", "text/html", "<div class='fossil-doc'><h3>Error: Missing 'type' parameter</h3></div>")
        end

        layout, err = schema.layout(db_path, entity_type)
        if layout == nil then
            return print_response("404 Not Found", "text/html", "<div class='fossil-doc'><h3>Error: " .. tostring(err) .. "</h3></div>")
        end
        layout = filter_layout_columns(layout, params.columns)
        layout_json = json.encode(layout)

        body = html.render(entity_type, layout_json, default_value(os.getenv("FOSSIL_NONCE"), ""))
        return print_response("200 OK", "text/html", body)
    end

    if path_info == "/browse" then
        entity_type = params.type
        if entity_type == nil or entity_type == "" then
            return print_response("400 Bad Request", "text/html", "<div class='fossil-doc'><h3>Error: Missing 'type' parameter</h3></div>")
        end

        layout, err = schema.layout(db_path, entity_type)
        if layout == nil then
            return print_response("404 Not Found", "text/html", "<div class='fossil-doc'><h3>Error: " .. tostring(err) .. "</h3></div>")
        end

        page = tonumber(params.page)
        if page == nil or page < 1 then
            page = 1
        end
        total = entity.count(db_path, entity_type)
        offset = (page - 1) * BROWSE_PAGE_SIZE
        rows = entity.list(db_path, entity_type, BROWSE_PAGE_SIZE, offset)
        body = html.render_browse(db_path, entity_type, layout, rows, page, BROWSE_PAGE_SIZE, total)
        return print_response("200 OK", "text/html", body)
    end

    if path_info == "/" or path_info == "" then
        entity_types = schema.list(db_path)
        for _, row in ipairs(entity_types) do
            row.count = entity.count(db_path, row.name)
        end
        index_capabilities = os.getenv("FOSSIL_CAPABILITIES")
        show_sql_widget = cgi.has_capability(index_capabilities, "s") or cgi.has_capability(index_capabilities, "a")
        body = html.render_index(entity_types, show_sql_widget)
        return print_response("200 OK", "text/html", body)
    end

    if path_info == "/detail" then
        entity_type = params.type
        -- Named "entity_id", not "id": Fossil's own /ext relay
        -- conflates the query string with its internal CGI parameter
        -- table (confirmed directly, reproducibly, for "name" -- see
        -- /view and /template below, which genuinely 404 as "path does
        -- not match any file or script" when called with a real
        -- "?name=..." query param). "id" itself turned out NOT to
        -- collide when re-checked with a real, valid id -- an earlier
        -- test here was a false positive from testing against a
        -- nonexistent id. Kept the "entity_id" rename anyway (harmless,
        -- and avoids relying on an exhaustive list of every other
        -- Fossil-reserved name), but don't cite it as a second
        -- confirmed collision.
        entity_id = tonumber(params.entity_id)
        if entity_type == nil or entity_type == "" or entity_id == nil then
            return print_response("400 Bad Request", "text/html", "<div class='fossil-doc'><h3>Error: Missing 'type' or 'entity_id' parameter</h3></div>")
        end

        layout, err = schema.layout(db_path, entity_type)
        if layout == nil then
            return print_response("404 Not Found", "text/html", "<div class='fossil-doc'><h3>Error: " .. tostring(err) .. "</h3></div>")
        end

        row = entity.get(db_path, entity_type, entity_id)
        if row == nil then
            return print_response("404 Not Found", "text/html", "<div class='fossil-doc'><h3>Error: no such " .. html_escape(entity_type) .. " #" .. tostring(entity_id) .. "</h3></div>")
        end

        history = ledger.history(db_path, entity_id)
        body = html.render_detail(db_path, entity_type, layout, row, history)
        return print_response("200 OK", "text/html", body)
    end

    if path_info == "/view" then
        view_name = params.view_name -- not "name" -- see /detail's comment
        if view_name == nil or view_name == "" then
            return print_response("400 Bad Request", "text/html", "<div class='fossil-doc'><h3>Error: Missing 'view_name' parameter</h3></div>")
        end

        views_dir = config.views_dir(root)
        view_def, err = view.load(views_dir, view_name)
        if view_def == nil then
            return print_response("404 Not Found", "text/html", "<div class='fossil-doc'><h3>Error: " .. tostring(err) .. "</h3></div>")
        end
        if view.is_approved(db_path, view_def) == false then
            return print_response("403 Forbidden", "text/html", "<div class='fossil-doc'><h3>Error: view '" .. html_escape(view_name) .. "' is not approved</h3></div>")
        end

        param_value = nil
        if view_def.param != nil then
            param_value = params[view_def.param.name]
        end

        rows, err = view.run(db_path, view_def, param_value)
        if rows == nil then
            return print_response("500 Internal Server Error", "text/html", "<div class='fossil-doc'><h3>Error: " .. tostring(err) .. "</h3></div>")
        end
        body = html.render_view(view_def, rows, param_value)
        return print_response("200 OK", "text/html", body)
    end

    if path_info == "/sql" then
        -- Setup or Admin only -- this runs arbitrary (SELECT-only)
        -- SQL an authenticated user typed themselves, so gating it
        -- behind the baseline "i" capability every other route uses
        -- would be far too permissive.
        capabilities = os.getenv("FOSSIL_CAPABILITIES")
        if cgi.has_capability(capabilities, "s") == false and cgi.has_capability(capabilities, "a") == false then
            return print_response("403 Forbidden", "text/html", "<div class='fossil-doc'><h3>Forbidden: requires Setup or Admin capability</h3></div>")
        end

        -- "q" absent entirely (bare /sql, never submitted) vs. "q"
        -- present-but-empty (form submitted with a blank box) are
        -- different cases -- distinguish them so a bare visit shows a
        -- real, runnable example instead of a query that only ever
        -- existed as unsubmitted placeholder text, and an actual empty
        -- submission gets a visible hint instead of silently doing
        -- nothing (which looked exactly like "ran it, got zero rows").
        sql_text = params.q
        column_names = nil
        rows = nil
        sql_err = nil
        ref_columns = {}
        if sql_text == nil then
            sql_text = "SELECT * FROM sample LIMIT 20;"
        elseif sql_text != "" then
            column_names, rows, sql_err = view.run_adhoc(db_path, sql_text)
            ref_columns = view.reference_columns(db_path, view.guess_from_table(sql_text))
        end
        body = html.render_sql(db_path, sql_text, column_names, rows, sql_err, ref_columns)
        return print_response("200 OK", "text/html", body)
    end

    if path_info == "/templates" then
        templates_dir = config.templates_dir(root)
        body = html.render_templates_list(template.all(templates_dir))
        return print_response("200 OK", "text/html", body)
    end

    if path_info == "/template" then
        template_name = params.template_name -- not "name" -- see /detail's comment
        if template_name == nil or template_name == "" then
            return print_response("400 Bad Request", "text/html", "<div class='fossil-doc'><h3>Error: Missing 'template_name' parameter</h3></div>")
        end

        templates_dir = config.templates_dir(root)
        template_def, err = template.load(templates_dir, template_name)
        if template_def == nil then
            return print_response("404 Not Found", "text/html", "<div class='fossil-doc'><h3>Error: " .. tostring(err) .. "</h3></div>")
        end

        rendered = template.render(template_def)
        body = html.render_template(template_def, rendered)
        return print_response("200 OK", "text/html", body)
    end

    if path_info == "/api/autocomplete" then
        return handle_autocomplete(db_path, params)
    end

    if path_info == "/api/validate" and method == "POST" then
        entity_type = params.type
        if entity_type == nil or entity_type == "" then
            return print_response("400 Bad Request", "application/json", json.encode({error = "Missing type"}))
        end
        input = io.read("*all")
        rows_values, _, err = json.decode(input)
        if rows_values == nil then
            return print_response("400 Bad Request", "application/json", json.encode({error = "Invalid JSON: " .. tostring(err)}))
        end
        batch_issues = entity.validate_batch(db_path, entity_type, rows_values)
        return print_response("200 OK", "application/json", json.encode(batch_issues))
    end

    if path_info == "/api/submit" and method == "POST" then
        entity_type = params.type
        if entity_type == nil or entity_type == "" then
            return print_response("400 Bad Request", "application/json", json.encode({error = "Missing type"}))
        end
        input = io.read("*all")
        rows_values, _, err = json.decode(input)
        if rows_values == nil then
            return print_response("400 Bad Request", "application/json", json.encode({error = "Invalid JSON: " .. tostring(err)}))
        end

        created_ids, batch_issues = entity.create_batch(db_path, entity_type, rows_values, author, source_from_params(params))
        response = {
            issues = batch_issues
        }
        if created_ids != nil then
            response.created_ids = created_ids
            response.success = true
        else
            response.success = false
        end
        return print_response("200 OK", "application/json", json.encode(response))
    end

    if path_info == "/api/update" and method == "POST" then
        entity_type = params.type
        entity_id = tonumber(params.entity_id) -- not "id" -- see /detail's comment
        if entity_type == nil or entity_type == "" or entity_id == nil then
            return print_response("400 Bad Request", "application/json", json.encode({error = "Missing type or entity_id"}))
        end
        input = io.read("*all")
        values, _, err = json.decode(input)
        if values == nil then
            return print_response("400 Bad Request", "application/json", json.encode({error = "Invalid JSON: " .. tostring(err)}))
        end

        updated_id, issues = entity.update(db_path, entity_type, entity_id, values, author, source_from_params(params))
        response = {
            issues = issues
        }
        if updated_id != nil then
            response.updated_id = updated_id
            response.success = true
        else
            response.success = false
        end
        return print_response("200 OK", "application/json", json.encode(response))
    end

    return print_response("404 Not Found", "text/plain", "Not Found")
end

return cgi
