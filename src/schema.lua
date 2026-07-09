-- Schema-as-code: loads entity type definitions (Luam table files, see
-- doc/schema.md) and generates/migrates the real typed SQL table each
-- one describes. This is the only place field-type -> SQL-type mapping
-- happens.

db = require("db")
sandbox = require("sandbox")
paths = require("paths")

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

-- Creates the projected table if it doesn't exist, or adds any columns
-- for fields that aren't present yet. Never drops or renames a column --
-- that's a deliberately manual, reviewed operation, not an automatic one.
function schema.sync_table(db_path, def)
    if db.table_exists(db_path, def.name) == false then
        columns = {"id INTEGER PRIMARY KEY AUTOINCREMENT"}
        for _, field in ipairs(def.fields) do
            table.insert(columns, field.name .. " " .. SQL_TYPE[field.type])
        end
        table.insert(columns, "created_by TEXT")
        table.insert(columns, "created_at TEXT DEFAULT (datetime('now', 'localtime'))")
        table.insert(columns, "updated_by TEXT")
        table.insert(columns, "updated_at TEXT DEFAULT (datetime('now', 'localtime'))")
        table.insert(columns, "last_event_id INTEGER")
        db.exec(db_path, string.format(
            "CREATE TABLE %s (%s);", def.name, table.concat(columns, ", ")
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

-- CLI entry point: `fossci schema <add|list|show> [args]`
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
        for _, row in ipairs(schema.list(db_path)) do
            print(row.name)
        end
        return
    end

    if action == "show" then
        name = cmd_args[2]
        if name == nil then
            print("Usage: fossci schema show <name>")
            return
        end
        for _, field in ipairs(schema.fields(db_path, name)) do
            required = "optional"
            if tonumber(field.required) == 1 then
                required = "required"
            end
            print(string.format("%-20s %-10s %s", field.name, field.type, required))
        end
        return
    end

    print("Usage: fossci schema <add|list|show> [args]")
end

return schema
