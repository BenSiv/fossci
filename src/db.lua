-- Thin adapter over Luam's sqlite-backed database module.
--
-- Kept deliberately small and isolated: v0 runs on SQLite because that's
-- what Luam actually ships a binding for (see doc/architecture.md,
-- "SQLite now, Postgres later"). Nothing above this file should call
-- sqlite3/database directly -- when a Postgres adapter is written, only
-- this file needs to change.

database = require("database")

db = {}

function db.query(db_path, query, ...)
    return database.local_query(db_path, query, ...)
end

function db.exec(db_path, statement, ...)
    return database.local_update(db_path, statement, ...)
end

function db.get_tables(db_path)
    return database.get_tables(db_path)
end

function db.get_columns(db_path, table_name)
    return database.get_columns(db_path, table_name)
end

function db.table_exists(db_path, table_name)
    tables = db.get_tables(db_path)
    if tables == nil then
        return false
    end
    for _, name in ipairs(tables) do
        if name == table_name then
            return true
        end
    end
    return false
end

-- Quotes a value as a SQLite string literal, escaping embedded quotes.
-- Uses database.escape_sqlite rather than re-implementing the same
-- one-line gsub -- that function was already there, just not exported.
function db.quote(value)
    return "'" .. database.escape_sqlite(value) .. "'"
end

-- Renders `value` as a safe SQL literal: NULL for nil, a quoted string
-- otherwise. Numbers/booleans are stringified and quoted too, which is
-- harmless for SQLite's dynamic typing and keeps callers from needing
-- two code paths.
function db.literal(value)
    if value == nil then
        return "NULL"
    end
    return db.quote(value)
end

return db
