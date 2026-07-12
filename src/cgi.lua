db = require("db")
config = require("config")
schema = require("schema")
entity = require("entity")
ledger = require("ledger")
html = require("html")
json = require("dkjson")
paths = require("paths")

cgi = {}

-- Fossil's /ext dispatch bypasses the repo's own read-capability check
-- (see doc/architecture.md), so fossci gates itself here. "i" (Check-In)
-- is the closest existing Fossil capability to "real contributor with
-- write access"; Setup/Admin logins already carry it via fullcap().
REQUIRED_CAPABILITY = "i"

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
        ledger.init_schema(db_path)
    end
    schema.sync_all(db_path, root)

    author = os.getenv("FOSSIL_USER")
    if author == nil or author == "" then
        author = default_value(os.getenv("USER"), "anonymous")
    end

    if path_info == "/register" then
        entity_type = params.type
        if entity_type == nil or entity_type == "" then
            return print_response("400 Bad Request", "text/html", "<div class='fossil-doc'><h3>Error: Missing 'type' parameter</h3></div>")
        end

        layout_json, err = schema.show_json(db_path, entity_type)
        if layout_json == nil then
            return print_response("404 Not Found", "text/html", "<div class='fossil-doc'><h3>Error: " .. tostring(err) .. "</h3></div>")
        end

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

        rows = entity.list(db_path, entity_type)
        body = html.render_browse(entity_type, layout, rows)
        return print_response("200 OK", "text/html", body)
    end

    if path_info == "/detail" then
        entity_type = params.type
        entity_id = tonumber(params.id)
        if entity_type == nil or entity_type == "" or entity_id == nil then
            return print_response("400 Bad Request", "text/html", "<div class='fossil-doc'><h3>Error: Missing 'type' or 'id' parameter</h3></div>")
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
        body = html.render_detail(entity_type, layout, row, history)
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
        entity_id = tonumber(params.id)
        if entity_type == nil or entity_type == "" or entity_id == nil then
            return print_response("400 Bad Request", "application/json", json.encode({error = "Missing type or id"}))
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
