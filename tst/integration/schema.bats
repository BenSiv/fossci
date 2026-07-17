#!/usr/bin/env bats

load test_helper.bash

setup() {
    setup_test_env
    "$FOSSCI" init
}

teardown() {
    cleanup_test_env
}

write_reagent_schema() {
    mkdir -p schemas
    cat > schemas/reagent.lua <<'EOF'
return {
  name = "reagent",
  fields = {
    {name = "lot_number", type = "text", required = true},
    {name = "concentration", type = "number", required = true},
  },
}
EOF
}

@test "schema add registers a well-formed schema" {
    write_reagent_schema
    run "$FOSSCI" schema add schemas/reagent.lua
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Registered entity type 'reagent'" ]]
}

@test "schema list shows a registered type" {
    write_reagent_schema
    "$FOSSCI" schema add schemas/reagent.lua

    run "$FOSSCI" schema list
    [ "$status" -eq 0 ]
    [[ "$output" =~ "reagent" ]]
}

@test "schema add rejects a select field with no values" {
    mkdir -p schemas
    cat > schemas/bad.lua <<'EOF'
return {
  name = "bad",
  fields = {
    {name = "status", type = "select"},
  },
}
EOF
    run "$FOSSCI" schema add schemas/bad.lua
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Error" ]]

    run "$FOSSCI" schema list
    [[ ! "$output" =~ "bad" ]]
}

@test "schema add rejects an unrecognized field type" {
    mkdir -p schemas
    cat > schemas/bad_type.lua <<'EOF'
return {
  name = "bad_type",
  fields = {
    {name = "priority", type = "integer"},
  },
}
EOF
    run "$FOSSCI" schema add schemas/bad_type.lua
    [[ "$output" =~ "Error" ]]
}
