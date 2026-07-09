-- Entity CRUD on top of the ledger: this is where "all-or-nothing per
-- submit" validation happens (doc/project_plan.md M1, and the earlier
-- validation-rules design) -- nothing is written to the ledger or the
-- projected table unless every value passes.
--
-- v0 validates structurally (required/type/enum/reference-exists) only.
-- Scriptable before-hooks (extension-authored validation rules) are M1;
-- this is the contract they'll plug into, not a separate mechanism.

db = require("db")
ledger = require("ledger")
schema = require("schema")

entity = {}

function is_number(v)
    return tonumber(v) != nil
end

-- Structural validation against a registered schema. Returns a list of
-- {field, severity, message} issues -- empty if the row is clean. This
-- is the exact shape a scriptable before-hook will also return (M1), so
-- structural checks and rule-authored checks compose without a second
-- issue format to reconcile.
function entity.validate(db_path, entity_type, values)
    issues = {}
    fields = schema.fields(db_path, entity_type)
    if #fields == 0 then
        table.insert(issues, {field = nil, severity = "error",
            message = "unknown entity type: " .. tostring(entity_type)})
        return issues
    end

    for _, field in ipairs(fields) do
        value = values[field.name]

        if (value == nil or value == "") then
            if tonumber(field.required) == 1 then
                table.insert(issues, {field = field.name, severity = "error",
                    message = "required field is missing"})
            end
        else
            if field.type == "number" and is_number(value) == false then
                table.insert(issues, {field = field.name, severity = "error",
                    message = "must be a number"})
            end

            if field.type == "select" then
                json = require("dkjson")
                allowed = json.decode(field.enum_values)
                if allowed == nil then
                    allowed = {}
                end
                ok = false
                for _, v in ipairs(allowed) do
                    if tostring(v) == tostring(value) then
                        ok = true
                    end
                end
                if ok == false then
                    table.insert(issues, {field = field.name, severity = "error",
                        message = "must be one of the declared values"})
                end
            end

            if field.type == "reference" then
                ref_type = entity_type
                if field.ref_entity_type != nil then
                    ref_type = field.ref_entity_type
                end
                found = entity.get(db_path, ref_type, tonumber(value))
                if found == nil then
                    table.insert(issues, {field = field.name, severity = "error",
                        message = "references a nonexistent " .. ref_type .. " entity"})
                end
            end
        end
    end

    return issues
end

function has_error(issues)
    for _, issue in ipairs(issues) do
        if issue.severity == "error" then
            return true
        end
    end
    return false
end

-- Creates an entity. Returns (entity_id, issues) on success, or
-- (nil, issues) if validation failed -- issues is always the full list,
-- callers render it whichever way is appropriate (CLI print, inline
-- banner in the registration table UI, ...).
function entity.create(db_path, entity_type, values, author, source)
    issues = entity.validate(db_path, entity_type, values)
    if has_error(issues) then
        return nil, issues
    end

    entity_id = ledger.append_create(db_path, entity_type, values, author, source)

    columns = {"id"}
    literals = {tostring(entity_id)}
    for name, value in pairs(values) do
        table.insert(columns, name)
        table.insert(literals, db.literal(value))
    end
    table.insert(columns, "created_by")
    table.insert(literals, db.literal(author))
    table.insert(columns, "last_event_id")
    table.insert(literals, tostring(entity_id))

    db.exec(db_path, string.format(
        "INSERT INTO %s (%s) VALUES (%s);",
        entity_type, table.concat(columns, ", "), table.concat(literals, ", ")
    ))

    return entity_id, issues
end

-- Updates an entity. Computes the old/new diff itself (from the current
-- projected row) so the ledger event records exactly what changed, not
-- just the new snapshot.
function entity.update(db_path, entity_type, entity_id, values, author, source)
    current = entity.get(db_path, entity_type, entity_id)
    if current == nil then
        return nil, {{field = nil, severity = "error", message = "no such entity"}}
    end

    merged = {}
    for k, v in pairs(current) do
        merged[k] = v
    end
    for k, v in pairs(values) do
        merged[k] = v
    end

    issues = entity.validate(db_path, entity_type, merged)
    if has_error(issues) then
        return nil, issues
    end

    field_changes = {}
    assignments = {}
    for name, new_value in pairs(values) do
        old_value = current[name]
        if tostring(old_value) != tostring(new_value) then
            field_changes[name] = {old = old_value, new = new_value}
            table.insert(assignments, name .. " = " .. db.literal(new_value))
        end
    end

    if #assignments == 0 then
        return entity_id, issues
    end

    event_id = ledger.append_update(db_path, entity_type, entity_id, field_changes, author, source)

    table.insert(assignments, "updated_by = " .. db.literal(author))
    table.insert(assignments, "last_event_id = " .. tostring(event_id))
    db.exec(db_path, string.format(
        "UPDATE %s SET %s WHERE id = %d;", entity_type, table.concat(assignments, ", "), entity_id
    ))

    return entity_id, issues
end

function entity.get(db_path, entity_type, entity_id)
    if db.table_exists(db_path, entity_type) == false then
        return nil
    end
    rows = db.query(db_path, string.format(
        "SELECT * FROM %s WHERE id = %d;", entity_type, entity_id
    ))
    if rows == nil then
        return nil
    end
    return rows[1]
end

function entity.list(db_path, entity_type)
    if db.table_exists(db_path, entity_type) == false then
        return {}
    end
    rows = db.query(db_path, "SELECT * FROM " .. entity_type .. ";")
    if rows == nil then
        return {}
    end
    return rows
end

function print_issues(issues)
    for _, issue in ipairs(issues) do
        label = "(row)"
        if issue.field != nil then
            label = issue.field
        end
        print(string.format("  [%s] %s: %s", issue.severity, label, issue.message))
    end
end

function parse_kv_args(args, start)
    values = {}
    for i = start, #args do
        key, value = string.match(args[i], "^([%w_]+)=(.*)$")
        if key != nil then
            values[key] = value
        end
    end
    return values
end

-- CLI entry point: `fossci entity <create|list|show> [args]`
function entity.do_entity(cmd_args, db_path)
    action = cmd_args[1]

    if action == "create" then
        entity_type = cmd_args[2]
        if entity_type == nil then
            print("Usage: fossci entity create <type> field=value [field=value ...]")
            return
        end
        values = parse_kv_args(cmd_args, 3)
        id, issues = entity.create(db_path, entity_type, values, os.getenv("USER"))
        if id == nil then
            print("Registration failed:")
            print_issues(issues)
            return
        end
        print(string.format("Created %s #%d", entity_type, id))
        if #issues > 0 then
            print_issues(issues)
        end
        return
    end

    if action == "list" then
        entity_type = cmd_args[2]
        if entity_type == nil then
            print("Usage: fossci entity list <type>")
            return
        end
        for _, row in ipairs(entity.list(db_path, entity_type)) do
            print(string.format("#%s", tostring(row.id)))
        end
        return
    end

    if action == "show" then
        entity_type = cmd_args[2]
        id = tonumber(cmd_args[3])
        if entity_type == nil or id == nil then
            print("Usage: fossci entity show <type> <id>")
            return
        end
        row = entity.get(db_path, entity_type, id)
        if row == nil then
            print("Not found")
            return
        end
        for k, v in pairs(row) do
            print(string.format("%-20s %s", k, tostring(v)))
        end
        return
    end

    print("Usage: fossci entity <create|list|show> [args]")
end

return entity
