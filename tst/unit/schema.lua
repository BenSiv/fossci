-- tst/unit/schema_test.lua
-- Unit tests for src/schema.lua's structural validation (schema.validate).

schema = require("schema")

FAILURES = 0

function check(condition, message)
    if condition != true then
        FAILURES = FAILURES + 1
        print("FAIL: " .. message)
    end
end

function test_valid_schema_passes()
    print("Testing a well-formed schema definition")
    def = {
        name = "reagent",
        fields = {
            {name = "lot_number", type = "text", required = true},
            {name = "concentration", type = "number", required = true},
            {name = "prepared_on", type = "date", required = true},
            {name = "status", type = "select", required = true, values = {"active", "depleted"}},
            {name = "prepared_from", type = "reference", required = false, entity_type = "reagent"},
        },
    }
    err = schema.validate(def)
    check(err == nil, "expected no error, got: " .. tostring(err))
end

function test_non_table_rejected()
    print("Testing a non-table definition is rejected")
    err = schema.validate("not a table")
    check(err != nil, "expected an error for a non-table definition")
end

function test_missing_name_rejected()
    print("Testing a schema with no name is rejected")
    err = schema.validate({fields = {}})
    check(err != nil, "expected an error for missing name")
end

function test_empty_name_rejected()
    print("Testing a schema with an empty string name is rejected")
    err = schema.validate({name = "", fields = {}})
    check(err != nil, "expected an error for empty name")
end

function test_missing_fields_rejected()
    print("Testing a schema with no 'fields' list is rejected")
    err = schema.validate({name = "task"})
    check(err != nil, "expected an error for missing fields")
end

function test_field_missing_name_rejected()
    print("Testing a field with no name is rejected")
    def = {name = "task", fields = {{type = "text"}}}
    err = schema.validate(def)
    check(err != nil, "expected an error for a field with no name")
end

function test_invalid_field_type_rejected()
    print("Testing an unrecognized field type is rejected")
    def = {name = "task", fields = {{name = "priority", type = "integer"}}}
    err = schema.validate(def)
    check(err != nil, "expected an error for type 'integer' (not one of the five real types)")
end

function test_select_without_values_rejected()
    print("Testing a 'select' field with no 'values' list is rejected")
    def = {name = "task", fields = {{name = "status", type = "select"}}}
    err = schema.validate(def)
    check(err != nil, "expected an error for select with no values")
end

function test_select_with_values_passes()
    print("Testing a 'select' field with a 'values' list passes")
    def = {name = "task", fields = {{name = "status", type = "select", values = {"open", "done"}}}}
    err = schema.validate(def)
    check(err == nil, "expected no error, got: " .. tostring(err))
end

function test_every_real_field_type_individually()
    print("Testing each of the five real field types passes on its own")
    types_to_test = {"text", "number", "date", "reference"}
    for _, t in ipairs(types_to_test) do
        def = {name = "x", fields = {{name = "f", type = t}}}
        err = schema.validate(def)
        check(err == nil, "type '" .. t .. "' should be valid, got: " .. tostring(err))
    end
end

function test_number_field_min_max_valid()
    print("Testing a number field with valid min/max passes")
    def = {name = "task", fields = {{name = "importance", type = "number", min = 1, max = 5}}}
    err = schema.validate(def)
    check(err == nil, "expected no error, got: " .. tostring(err))
end

function test_number_field_min_greater_than_max_rejected()
    print("Testing min greater than max is rejected")
    def = {name = "task", fields = {{name = "importance", type = "number", min = 5, max = 1}}}
    err = schema.validate(def)
    check(err != nil, "expected an error when min > max")
end

function test_number_field_non_numeric_min_rejected()
    print("Testing a non-numeric min is rejected")
    def = {name = "task", fields = {{name = "importance", type = "number", min = "one"}}}
    err = schema.validate(def)
    check(err != nil, "expected an error for a non-numeric min")
end

-- Run them
test_valid_schema_passes()
test_non_table_rejected()
test_missing_name_rejected()
test_empty_name_rejected()
test_missing_fields_rejected()
test_field_missing_name_rejected()
test_invalid_field_type_rejected()
test_select_without_values_rejected()
test_select_with_values_passes()
test_every_real_field_type_individually()
test_number_field_min_max_valid()
test_number_field_min_greater_than_max_rejected()
test_number_field_non_numeric_min_rejected()

if FAILURES > 0 then
    print(FAILURES .. " test(s) failed")
    os.exit(1)
end
print("All schema.lua tests passed")
