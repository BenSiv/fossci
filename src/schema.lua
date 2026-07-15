-- Schema-as-code: loads entity type definitions (Luam table files, see
-- doc/schema.md) and generates/migrates the real typed SQL table each
-- one describes. This is the only place field-type -> SQL-type mapping
-- happens.

db = require("db")
sandbox = require("sandbox")
paths = require("paths")
lfs = require("lfs")

schema = {}

FIELD_TYPES = {"text", "number", "date", "select", "reference"}

SQL_TYPE = {
    text = "TEXT",
    number = "REAL",
    date = "TEXT",
    select = "TEXT",
    reference = "INTEGER",
}

function is_valid_field_type(t)
    for _, valid in ipairs(FIELD_TYPES) do
        if t == valid then
            return true
        end
    end
    return false
end

-- Loads a schema definition from a Luam table file, sandboxed (see
-- doc/schema.md: schema files are executable, not inert data, so they
-- run through the same environment extension code would).
function schema.load_file(path)
    file = io.open(path, "r")
    if file == nil then
        return nil, "cannot open schema file: " .. path
    end
    source = io.read(file, "*all")
    io.close(file)

    ok, result = sandbox.run(source, path, sandbox.data_env())
    if ok == nil or ok == false then
        return nil, "error loading schema " .. path .. ": " .. tostring(result)
    end
    def = result

    err = schema.validate(def)
    if err != nil then
        return nil, err
    end
    return def
end

-- Structural validation only -- does the definition make sense on its
-- own terms. Whether it's consistent with what's already registered
-- (e.g. a reference to an unknown entity_type) is checked at register
-- time, since that needs the database.
function schema.validate(def)
    if type(def) != "table" then
        return "schema definition must be a table"
    end
    if type(def.name) != "string" or def.name == "" then
        return "schema must have a non-empty string 'name'"
    end
    if type(def.fields) != "table" then
        return "schema '" .. tostring(def.name) .. "' must have a 'fields' list"
    end
    for i, field in ipairs(def.fields) do
        if type(field.name) != "string" or field.name == "" then
            return string.format("schema '%s' field #%d: missing 'name'", def.name, i)
        end
        if is_valid_field_type(field.type) == false then
            return string.format("schema '%s' field '%s': invalid type '%s'", def.name, field.name, tostring(field.type))
        end
        if field.type == "select" and type(field.values) != "table" then
            return string.format("schema '%s' field '%s': type 'select' requires a 'values' list", def.name, field.name)
        end
    end
    return nil
end

-- Registers a validated schema definition: upserts entity_type/entity_field
-- rows, then creates or migrates the projected table.
function schema.register(db_path, def)
    db.exec(db_path, string.format(
        "INSERT OR IGNORE INTO entity_type (name) VALUES (%s);", db.quote(def.name)
    ))

    for i, field in ipairs(def.fields) do
        enum_json = nil
        if field.values != nil then
            json = require("dkjson")
            enum_json = json.encode(field.values)
        end
        required_flag = 0
        if field.required == true then
            required_flag = 1
        end
        db.exec(db_path, string.format(
            "INSERT OR REPLACE INTO entity_field (entity_type, name, type, required, enum_values, ref_entity_type, field_order) VALUES (%s, %s, %s, %d, %s, %s, %d);",
            db.quote(def.name), db.quote(field.name), db.quote(field.type),
            required_flag,
            db.literal(enum_json),
            db.literal(field.entity_type),
            i
        ))
    end

    schema.sync_table(db_path, def)
    return true
end

-- Always-present bookkeeping columns, independent of anything a schema
-- file declares -- benchling_id lets an external importer (e.g.
-- import_data_rest.py) look up "does a row for this source record
-- already exist" and upsert instead of blindly re-creating it every
-- sync run (a real, confirmed-live duplication bug this fixed: entity
-- tables had no external-id concept at all, so every run re-inserted
-- every source row from scratch).
BUILTIN_COLUMNS = {
    {name = "created_by", sql_type = "TEXT"},
    {name = "created_at", sql_type = "TEXT DEFAULT (datetime('now', 'localtime'))"},
    {name = "updated_by", sql_type = "TEXT"},
    {name = "updated_at", sql_type = "TEXT DEFAULT (datetime('now', 'localtime'))"},
    {name = "last_event_id", sql_type = "INTEGER"},
    {name = "benchling_id", sql_type = "TEXT"},
}

-- Creates the projected table if it doesn't exist, or adds any columns
-- for fields/builtins that aren't present yet. Never drops or renames a
-- column -- that's a deliberately manual, reviewed operation, not an
-- automatic one.
function schema.sync_table(db_path, def)
    if db.table_exists(db_path, def.name) == false then
        columns = {"id INTEGER PRIMARY KEY AUTOINCREMENT"}
        for _, field in ipairs(def.fields) do
            table.insert(columns, field.name .. " " .. SQL_TYPE[field.type])
        end
        for _, builtin in ipairs(BUILTIN_COLUMNS) do
            table.insert(columns, builtin.name .. " " .. builtin.sql_type)
        end
        db.exec(db_path, string.format(
            "CREATE TABLE %s (%s);", def.name, table.concat(columns, ", ")
        ))
        db.exec(db_path, string.format(
            "CREATE INDEX IF NOT EXISTS idx_%s_benchling_id ON %s (benchling_id);", def.name, def.name
        ))
        return
    end

    existing = db.get_columns(db_path, def.name)
    have = {}
    for _, name in ipairs(existing) do
        have[name] = true
    end
    for _, field in ipairs(def.fields) do
        if have[field.name] == nil then
            db.exec(db_path, string.format(
                "ALTER TABLE %s ADD COLUMN %s %s;", def.name, field.name, SQL_TYPE[field.type]
            ))
        end
    end
    for _, builtin in ipairs(BUILTIN_COLUMNS) do
        if have[builtin.name] == nil then
            db.exec(db_path, string.format(
                "ALTER TABLE %s ADD COLUMN %s %s;", def.name, builtin.name, builtin.sql_type
            ))
        end
    end
    db.exec(db_path, string.format(
        "CREATE INDEX IF NOT EXISTS idx_%s_benchling_id ON %s (benchling_id);", def.name, def.name
    ))
end

-- Scans the schemas directory, registers any schema files found,
-- and ensures all projected tables are synced/created.
function schema.sync_all(db_path, root)
    config = require("config")
    schemas_dir = config.schemas_dir(root)
    attr = lfs.attributes(schemas_dir)
    if attr == nil or attr.mode != "directory" then
        return false, "schemas directory not found: " .. schemas_dir
    end
    for file_name in lfs.dir(schemas_dir) do
        if string.match(file_name, "%.lua$") != nil then
            full_path = paths.joinpath(schemas_dir, file_name)
            def, err = schema.load_file(full_path)
            if def != nil then
                schema.register(db_path, def)
            end
        end
    end
    return true
end

-- The schema layout as a plain Luam table: {name, fields = {{name, label,
-- type, required, values?, ref_entity_type?}, ...}}. Shared by
-- schema.show_json (JSON for the client-side registration table) and
-- the browse/detail HTML views (cgi.lua/html.lua) -- one source of
-- truth for "what does this entity type's layout look like", native
-- consumers don't need to decode JSON just to get a Luam table back.
-- Prefers labels from the version-controlled schema file if available,
-- falling back to the database description (e.g. for a schema whose
-- file was since removed but whose table/data still exists).
function schema.layout(db_path, name)
    config = require("config")
    schemas_dir = config.schemas_dir()
    path = paths.joinpath(schemas_dir, name .. ".lua")
    def = nil
    if paths.file_exists(path) then
        def = schema.load_file(path)
    end

    if def != nil then
        result = {
            name = def.name,
            fields = {}
        }
        for _, field in ipairs(def.fields) do
            required = (field.required == true)
            label = field.label
            if label == nil then
                label = string.gsub(string.gsub(field.name, "^%l", string.upper), "_", " ")
            end
            field_def = {
                name = field.name,
                label = label,
                type = field.type,
                required = required
            }
            if field.values != nil then
                field_def.values = field.values
            end
            if field.entity_type != nil then
                field_def.ref_entity_type = field.entity_type
            end
            table.insert(result.fields, field_def)
        end
        return result
    else
        dkjson = require("dkjson")
        if schema.is_registered(db_path, name) == false then
            return nil, "unknown entity type: " .. name
        end
        fields = schema.fields(db_path, name)
        result = {
            name = name,
            fields = {}
        }
        for _, f in ipairs(fields) do
            required = (tonumber(f.required) == 1)
            label = string.gsub(string.gsub(f.name, "^%l", string.upper), "_", " ")
            field_def = {
                name = f.name,
                label = label,
                type = f.type,
                required = required
            }
            if f.enum_values != nil and f.enum_values != "" then
                field_def.values = dkjson.decode(f.enum_values)
            end
            if f.ref_entity_type != nil and f.ref_entity_type != "" then
                field_def.ref_entity_type = f.ref_entity_type
            end
            table.insert(result.fields, field_def)
        end
        return result
    end
end

-- Renders the schema structure as a JSON string (see schema.layout).
function schema.show_json(db_path, name)
    layout, err = schema.layout(db_path, name)
    if layout == nil then
        return nil, err
    end
    dkjson = require("dkjson")
    return dkjson.encode(layout)
end

-- Whether `entity_type` has been registered at all. A registered type
-- can legitimately have zero custom fields (e.g. a schema whose only
-- data is its name plus the system-managed created/updated columns),
-- so callers must not use "schema.fields() returned nothing" as a
-- stand-in for "this type doesn't exist" -- that conflates the two.
function schema.is_registered(db_path, entity_type)
    rows = db.query(db_path, string.format(
        "SELECT 1 FROM entity_type WHERE name = %s;",
        db.quote(entity_type)
    ))
    return rows != nil and #rows > 0
end

-- The registered field list for an entity type, in declaration order --
-- what entity.lua validates rows against.
function schema.fields(db_path, entity_type)
    rows = db.query(db_path, string.format(
        "SELECT * FROM entity_field WHERE entity_type = %s ORDER BY field_order ASC;",
        db.quote(entity_type)
    ))
    if rows == nil then
        return {}
    end
    return rows
end

function schema.list(db_path)
    rows = db.query(db_path, "SELECT name FROM entity_type ORDER BY name ASC;")
    if rows == nil then
        return {}
    end
    return rows
end

-- CLI entry point: `fossci schema <add|list|show|show-json|sync> [args]`
function schema.do_schema(cmd_args, db_path)
    action = cmd_args[1]

    if action == "add" then
        path = cmd_args[2]
        if path == nil then
            print("Usage: fossci schema add <file>")
            return
        end
        def, err = schema.load_file(path)
        if def == nil then
            print("Error: " .. err)
            return
        end
        schema.register(db_path, def)
        print("Registered entity type '" .. def.name .. "'")
        return
    end

    if action == "list" then
        schema.sync_all(db_path)
        for _, row in ipairs(schema.list(db_path)) do
            print(row.name)
        end
        return
    end

    if action == "show-json" or (action == "show" and cmd_args[3] == "--json") then
        name = cmd_args[2]
        if name == nil then
            print("Usage: fossci schema show-json <name>")
            return
        end
        schema.sync_all(db_path)
        json_str, err = schema.show_json(db_path, name)
        if json_str == nil then
            print("Error: " .. tostring(err))
            return
        end
        print(json_str)
        return
    end

    if action == "show" then
        name = cmd_args[2]
        if name == nil then
            print("Usage: fossci schema show <name>")
            return
        end
        schema.sync_all(db_path)
        for _, field in ipairs(schema.fields(db_path, name)) do
            required = "optional"
            if tonumber(field.required) == 1 then
                required = "required"
            end
            print(string.format("%-20s %-10s %s", field.name, field.type, required))
        end
        return
    end

    if action == "sync" then
        ok, err = schema.sync_all(db_path)
        if not ok then
            print("Error: " .. tostring(err))
        else
            print("Schema sync complete")
        end
        return
    end

    print("Usage: fossci schema <add|list|show|show-json|sync> [args]")
end

return schema
