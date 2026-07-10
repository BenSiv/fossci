db = require("db")
config = require("config")
schema = require("schema")
entity = require("entity")
html = require("html")
json = require("dkjson")
paths = require("paths")

cgi = {}

function parse_query(query_str)
    params = {}
    if not query_str then return params end
    for k, v in string.gmatch(query_str, "([^&=]+)=([^&=]*)") do
        -- simple url decoding for basic params
        decoded_v = string.gsub(string.gsub(v, "+", " "), "%%(%x%x)", function(h)
            return string.char(tonumber(h, 16))
        end)
        params[k] = decoded_v
    end
    return params
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
    query_str = params.query or ""
    if not ref_type or ref_type == "" then
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
    result = rows or {}
    return print_response("200 OK", "application/json", json.encode(result))
end

function cgi.handle_request()
    path_info = os.getenv("PATH_INFO") or "/register"
    query_string = os.getenv("QUERY_STRING") or ""
    method = os.getenv("REQUEST_METHOD") or "GET"
    params = parse_query(query_string)

    root = config.find_checkout_root()
    db_path = config.db_path(root)

    -- Auto-initialize or sync database schemas on request
    if not config.is_initialized(root) then
        paths.create_dir_if_not_exists(config.store_dir(root))
        paths.create_dir_if_not_exists(config.schemas_dir(root))
        paths.create_dir_if_not_exists(config.extensions_dir(root))
        ledger = require("ledger")
        ledger.init_schema(db_path)
    end
    schema.sync_all(db_path, root)

    author = os.getenv("FOSSIL_USER")
    if not author or author == "" then
        author = os.getenv("USER") or "anonymous"
    end

    if path_info == "/register" then
        entity_type = params.type
        if not entity_type or entity_type == "" then
            return print_response("400 Bad Request", "text/html", "<div class='fossil-doc'><h3>Error: Missing 'type' parameter</h3></div>")
        end

        layout_json, err = schema.show_json(db_path, entity_type)
        if not layout_json then
            return print_response("404 Not Found", "text/html", "<div class='fossil-doc'><h3>Error: " .. tostring(err) .. "</h3></div>")
        end

        body = html.render(entity_type, layout_json)
        return print_response("200 OK", "text/html", body)
    end

    if path_info == "/api/autocomplete" then
        return handle_autocomplete(db_path, params)
    end

    if path_info == "/api/validate" and method == "POST" then
        entity_type = params.type
        if not entity_type or entity_type == "" then
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
        if not entity_type or entity_type == "" then
            return print_response("400 Bad Request", "application/json", json.encode({error = "Missing type"}))
        end
        input = io.read("*all")
        rows_values, _, err = json.decode(input)
        if rows_values == nil then
            return print_response("400 Bad Request", "application/json", json.encode({error = "Invalid JSON: " .. tostring(err)}))
        end

        created_ids, batch_issues = entity.create_batch(db_path, entity_type, rows_values, author)
        response = {
            issues = batch_issues
        }
        if created_ids then
            response.created_ids = created_ids
            response.success = true
        else
            response.success = false
        end
        return print_response("200 OK", "application/json", json.encode(response))
    end

    return print_response("404 Not Found", "text/plain", "Not Found")
end

return cgi
