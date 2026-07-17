#!/usr/bin/env bats

load test_helper.bash

setup() {
    setup_test_env
    "$FOSSCI" init
    mkdir -p views
    cat > views/samples.lua <<'EOF'
return {
  name = "samples",
  title = "All samples",
  sql = "SELECT id FROM sqlite_master WHERE type = 'table' LIMIT 5;",
  columns = {
    {name = "id", label = "ID"},
  },
}
EOF
}

teardown() {
    cleanup_test_env
}

@test "view list shows an unapproved view" {
    run "$FOSSCI" view list
    [ "$status" -eq 0 ]
    [[ "$output" =~ "samples" ]]
    [[ "$output" =~ "not approved" ]]
}

@test "view approve marks a view approved" {
    "$FOSSCI" view approve samples
    run "$FOSSCI" view show samples
    [[ "$output" =~ "status: approved" ]]
}

@test "view revoke unapproves a previously approved view" {
    "$FOSSCI" view approve samples
    "$FOSSCI" view revoke samples
    run "$FOSSCI" view show samples
    [[ "$output" =~ "status: not approved" ]]
}

@test "editing an approved view's sql requires re-approval" {
    "$FOSSCI" view approve samples
    cat > views/samples.lua <<'EOF'
return {
  name = "samples",
  title = "All samples",
  sql = "SELECT id FROM sqlite_master WHERE type = 'table' LIMIT 10;",
  columns = {
    {name = "id", label = "ID"},
  },
}
EOF
    run "$FOSSCI" view show samples
    [[ "$output" =~ "NOT APPROVED" ]]
}

@test "view add rejects sql with a stacked statement" {
    mkdir -p views
    cat > views/evil.lua <<'EOF'
return {
  name = "evil",
  title = "Evil",
  sql = "SELECT id FROM sqlite_master; DROP TABLE entity_field;",
  columns = {
    {name = "id", label = "ID"},
  },
}
EOF
    run "$FOSSCI" view show evil
    [[ "$output" =~ "Error" ]]
}
