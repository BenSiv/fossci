#!/usr/bin/env bats

load test_helper.bash

setup() {
    setup_test_env
    "$FOSSCI" init
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
    "$FOSSCI" schema add schemas/reagent.lua
}

teardown() {
    cleanup_test_env
}

@test "entity create succeeds with all required fields" {
    run "$FOSSCI" entity create reagent lot_number=LOT-1 concentration=5
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Created reagent #1" ]]
}

@test "entity create fails when a required field is missing" {
    run "$FOSSCI" entity create reagent lot_number=LOT-1
    [[ "$output" =~ "required field is missing" ]]
}

@test "entity list shows a created entity's id" {
    "$FOSSCI" entity create reagent lot_number=LOT-1 concentration=5
    # entity list only prints "#<id>" per entity, not field values --
    # entity show/detail pages are where field values render.
    run "$FOSSCI" entity list reagent
    [ "$status" -eq 0 ]
    [[ "$output" =~ "#1" ]]
}

@test "entity update changes a field value" {
    "$FOSSCI" entity create reagent lot_number=LOT-1 concentration=5
    run "$FOSSCI" entity update reagent 1 concentration=10
    [ "$status" -eq 0 ]

    run "$FOSSCI" entity show reagent 1
    [[ "$output" =~ "10" ]]
}

@test "ledger records full history for an entity" {
    "$FOSSCI" entity create reagent lot_number=LOT-1 concentration=5
    "$FOSSCI" entity update reagent 1 concentration=10

    run "$FOSSCI" ledger history 1
    [ "$status" -eq 0 ]
    # Both the create and the update should show up in the event history.
    [[ "$output" =~ "create" ]]
    [[ "$output" =~ "update" ]]
}
