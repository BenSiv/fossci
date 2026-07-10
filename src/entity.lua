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
paths = require("paths")
lfs = require("lfs")
sandbox = require("sandbox")
json = require("dkjson")

entity = {}

function is_number(v)
    return tonumber(v) != nil
end

function run_before_hooks(db_path, entity_type, new_values, old_values, is_update)
    config = require("config")
    ext_dir = config.extensions_dir()
    attr = lfs.attributes(ext_dir)
    issues = {}
    if attr == nil or attr.mode != "directory" then
        return issues
    end

    event_name = is_update and "entity.before_update" or "entity.before_create"

    for dir_name in lfs.dir(ext_dir) do
        if dir_name != "." and dir_name != ".." then
            manifest_path = paths.joinpath(ext_dir, dir_name, "manifest.lua")
            main_path = paths.joinpath(ext_dir, dir_name, "main.lua")

            if paths.file_exists(manifest_path) and paths.file_exists(main_path) then
                manifest_file = io.open(manifest_path, "r")
                if manifest_file then
                    manifest_src = io.read(manifest_file, "*all")
                    io.close(manifest_file)

                    ok, manifest = sandbox.run(manifest_src, manifest_path, sandbox.data_env())
                    if ok and type(manifest) == "table" then
                        matches_event = false
                        if manifest.events then
                            for _, ev in ipairs(manifest.events) do
                                if ev == event_name then
                                    matches_event = true
                                    break
                                end
                            end
                        end

                        matches_entity = false
                        if manifest.entity_types then
                            for _, et in ipairs(manifest.entity_types) do
                                if et == entity_type then
                                    matches_entity = true
                                    break
                                end
                            end
                        end

                        if matches_event and matches_entity then
                            main_file = io.open(main_path, "r")
                            if main_file then
                                main_src = io.read(main_file, "*all")
                                io.close(main_file)

                                env = sandbox.extension_env(manifest.capabilities)
                                env.on_before = nil

                                run_ok, err = sandbox.run(main_src, main_path, env)
                                if run_ok then
                                    if type(env.on_before) == "function" then
                                        ctx = {}
                                        function ctx.query(target_type, filter)
                                            can_read = false
                                            if manifest.capabilities and manifest.capabilities.read then
                                                for _, cap in ipairs(manifest.capabilities.read) do
                                                    if cap == "entity" then
                                                        can_read = true
                                                    end
                                                end
                                            end
                                            if not can_read then
                                                error("Extension does not have read.entity capability")
                                            end

                                            if not db.table_exists(db_path, target_type) then
                                                return {}
                                            end
                                            where = {}
                                            for k, v in pairs(filter) do
                                                table.insert(where, k .. " = " .. db.quote(tostring(v)))
                                            end
                                            q = "SELECT * FROM " .. target_type
                                            if #where > 0 then
                                                q = q .. " WHERE " .. table.concat(where, " AND ")
                                            end
                                            q = q .. ";"
                                            rows = db.query(db_path, q)
                                            return rows or {}
                                        end

                                        hook_ok, hook_issues = pcall(env.on_before, new_values, old_values, ctx)
                                        if hook_ok and type(hook_issues) == "table" then
                                            for _, issue in ipairs(hook_issues) do
                                                table.insert(issues, issue)
                                            end
                                        elseif not hook_ok then
                                            table.insert(issues, {field = nil, severity = "error",
                                                message = "Hook execution error: " .. tostring(hook_issues)})
                                        end
                                    end
                                else
                                    table.insert(issues, {field = nil, severity = "error",
                                        message = "Error running extension main.lua: " .. tostring(err)})
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return issues
end

-- Structural validation against a registered schema. Returns a list of
-- {field, severity, message} issues -- empty if the row is clean.
function entity.validate(db_path, entity_type, values, old)
    is_update = (old != nil)
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

    -- Run before-hooks if there are no severe structural errors
    if not has_error(issues) then
        hooks_issues = run_before_hooks(db_path, entity_type, values, old, is_update)
        for _, issue in ipairs(hooks_issues) do
            table.insert(issues, issue)
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
-- (nil, issues) if validation failed.
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
-- projected row).
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

    issues = entity.validate(db_path, entity_type, merged, current)
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

-- Runs validation on a batch of row values.
function entity.validate_batch(db_path, entity_type, rows_values)
    batch_issues = {}
    for i, values in ipairs(rows_values) do
        issues = entity.validate(db_path, entity_type, values)
        for _, issue in ipairs(issues) do
            table.insert(batch_issues, {
                row_index = i,
                field = issue.field,
                severity = issue.severity,
                message = issue.message
            })
        end
    end
    return batch_issues
end

-- Creates a batch of entities atomically.
function entity.create_batch(db_path, entity_type, rows_values, author, source)
    batch_issues = entity.validate_batch(db_path, entity_type, rows_values)
    if has_error(batch_issues) then
        return nil, batch_issues
    end

    created_ids = {}
    for i, values in ipairs(rows_values) do
        id, issues = entity.create(db_path, entity_type, values, author, source)
        if id then
            table.insert(created_ids, id)
        else
            return nil, issues
        end
    end
    return created_ids, batch_issues
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

-- CLI entry point: `fossci entity <create|list|show|validate-json|create-json> [args]`
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

    if action == "validate-json" then
        entity_type = cmd_args[2]
        if entity_type == nil then
            print("Usage: fossci entity validate-json <type>")
            return
        end
        input = io.read("*all")
        rows_values, _, err = json.decode(input)
        if rows_values == nil then
            print(json.encode({error = "Invalid JSON input: " .. tostring(err)}))
            return
        end
        batch_issues = entity.validate_batch(db_path, entity_type, rows_values)
        print(json.encode(batch_issues))
        return
    end

    if action == "create-json" then
        entity_type = cmd_args[2]
        if entity_type == nil then
            print("Usage: fossci entity create-json <type>")
            return
        end
        input = io.read("*all")
        rows_values, _, err = json.decode(input)
        if rows_values == nil then
            print(json.encode({error = "Invalid JSON input: " .. tostring(err)}))
            return
        end
        author = os.getenv("USER")
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
        print(json.encode(response))
        return
    end

    print("Usage: fossci entity <create|list|show|validate-json|create-json> [args]")
end

return entity
