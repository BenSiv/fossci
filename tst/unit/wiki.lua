-- tst/unit/wiki.lua
-- Unit tests for src/wiki.lua's wiki.fossil_bin() fallback chain: env
-- var, then the repo's own config table, then a bare "fossil" -- the
-- env var alone was found to be unreliable on a real HTTP request (see
-- wiki.lua's own comment), since fossil-scm's /ext dispatch wipes it
-- (and everything else outside its own fixed CGI whitelist) before
-- fossci ever starts. FOSSIL_BIN must be unset in the environment
-- running this file (true for a normal `bld/test.sh` run) -- Luam has
-- no os.setenv to control that from within the script itself.

db = require("db")
wiki = require("wiki")

FAILURES = 0

function check(condition, message)
    if condition != true then
        FAILURES = FAILURES + 1
        print("FAIL: " .. message)
    end
end

function scratch_db_path()
    path = os.tmpname()
    os.remove(path)
    return path .. ".db"
end

function test_env_var_precondition()
    check(os.getenv("FOSSIL_BIN") == nil, "FOSSIL_BIN must be unset for these tests to be meaningful")
end

function test_config_table_used_when_env_var_unset()
    print("Testing the repo config table is used when FOSSIL_BIN is unset")
    db_path = scratch_db_path()
    db.exec(db_path, "CREATE TABLE config (name TEXT, value TEXT);")
    db.exec(db_path, "INSERT INTO config (name, value) VALUES ('fossci-fossil-bin', '/from/config/fossil');")
    result = wiki.fossil_bin(db_path)
    os.remove(db_path)
    check(result == "/from/config/fossil", "expected the config table's value, got: " .. tostring(result))
end

function test_bare_fossil_when_neither_set()
    print("Testing the bare 'fossil' fallback when the config table has no matching row")
    db_path = scratch_db_path()
    db.exec(db_path, "CREATE TABLE config (name TEXT, value TEXT);")
    result = wiki.fossil_bin(db_path)
    os.remove(db_path)
    check(result == "fossil", "expected the bare 'fossil' fallback, got: " .. tostring(result))
end

function test_bare_fossil_when_repo_fossil_is_nil()
    print("Testing the bare 'fossil' fallback when repo_fossil itself is nil")
    result = wiki.fossil_bin(nil)
    check(result == "fossil", "expected the bare 'fossil' fallback, got: " .. tostring(result))
end

-- Run them
test_env_var_precondition()
test_config_table_used_when_env_var_unset()
test_bare_fossil_when_neither_set()
test_bare_fossil_when_repo_fossil_is_nil()

if FAILURES > 0 then
    print(FAILURES .. " test(s) failed")
    os.exit(1)
end
print("All wiki.lua tests passed")
