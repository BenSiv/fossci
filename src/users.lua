-- Users-as-code: a deployment's *additional* Fossil user accounts as one
-- versioned Luam file (users.lua at the checkout root, see
-- config.users_path) -- synced the same way layout.lua's nav/branding
-- syncs into Fossil's own tables, except this writes to Fossil's `user`
-- table in the Fossil *repository's* own sqlite file (given explicitly
-- via --repo-fossil, since that's a different database than fossci's
-- own ledger at config.db_path()).
--
-- users.lua only needs to declare logins *beyond* Fossil's own secure
-- defaults (see the fossil-scm fork's db_create_default_users, which
-- already ships "nobody"/"anonymous" with zero capabilities and
-- "developer"/"reader" as inert templates) -- e.g. just the admin
-- account. This module never touches those default logins; they're
-- Fossil's own responsibility, left alone entirely here.
--
-- Shape:
--   return {
--       {login = "admin", cap = "s", password_secret = "FOSSIL_ADMIN_PASSWORD"},
--   }
--
-- `password_secret` names an external secret (resolved by a separate,
-- Python-side sync step -- see elab/schema/fossci/sync_users.py) --
-- never a literal password. This module never computes or stores a
-- password hash itself: Fossil's own `pw` column hashing
-- (sha1_shared_secret, combining the repo's project-code + login +
-- cleartext password) is C-side and deliberately NOT reimplemented
-- here -- real password values are always applied via the canonical
-- `fossil user password` CLI, invoked by the Python wrapper, never via
-- a raw SQL write to `pw` from this file.

paths = require("paths")
sandbox = require("sandbox")
db = require("db")
json = require("dkjson")

users = {}

function users.load(root)
    path = config_users_path(root)
    if paths.file_exists(path) == false then
        return {}
    end
    file = io.open(path, "r")
    if file == nil then
        return nil, "cannot open users file: " .. path
    end
    source = io.read(file, "*all")
    io.close(file)

    ok, result = sandbox.run(source, path, sandbox.data_env())
    if ok == nil or ok == false then
        return nil, "error loading users.lua: " .. tostring(result)
    end
    if type(result) != "table" then
        return nil, "users.lua must return a table (a list of user definitions)"
    end
    return result
end

-- Kept as a separate helper (rather than requiring "config" at module
-- load time) to avoid a require-cycle risk -- same reasoning as
-- layout.lua's own config_layout_path.
function config_users_path(root)
    config = require("config")
    return config.users_path(root)
end

-- Creates the login if missing (empty pw -- any real password is
-- applied separately via `fossil user password`, never here), then
-- always reconciles its capability string to the declared value. Never
-- touches logins absent from the declared list -- same conservative
-- stance schema.sync_all() already takes toward tables absent from
-- schemas/*.lua.
function users.sync(repo_fossil, declared)
    for _, u in ipairs(declared) do
        cap = ""
        if u.cap != nil then
            cap = u.cap
        end
        db.exec(repo_fossil, string.format(
            "INSERT OR IGNORE INTO user(login, pw, cap, info) VALUES (%s, '', '', '');",
            db.quote(u.login)
        ))
        db.exec(repo_fossil, string.format(
            "UPDATE user SET cap = %s, mtime = strftime('%%s','now') WHERE login = %s;",
            db.quote(cap), db.quote(u.login)
        ))
    end
end

function find_repo_fossil_arg(cmd_args)
    for i, a in ipairs(cmd_args) do
        if a == "--repo-fossil" then
            return cmd_args[i + 1]
        end
    end
    return nil
end

function users.do_users(cmd_args)
    action = cmd_args[1]

    if action != "sync" and action != "list" then
        print("Usage: fossci users <sync|list> --repo-fossil <path>")
        return
    end

    config = require("config")
    declared, err = users.load(config.find_checkout_root())
    if declared == nil then
        print("Error: " .. tostring(err))
        return
    end

    if action == "list" then
        print(json.encode(declared))
        return
    end

    -- action == "sync"
    repo_fossil = find_repo_fossil_arg(cmd_args)
    if repo_fossil == nil then
        print("Usage: fossci users sync --repo-fossil <path>")
        return
    end
    users.sync(repo_fossil, declared)
    print("Synced " .. #declared .. " declared user(s) into " .. repo_fossil)
end

return users
