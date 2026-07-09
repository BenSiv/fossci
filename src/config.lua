-- Resolves the fossci store location: a `.fossci/` directory holding the
-- ledger database, alongside `schemas/` and `extensions/` directories
-- that mirror what would be Fossil-tracked paths in the full bolt-on
-- (see doc/architecture.md). For v0, standalone, these are plain local
-- directories; the Fossil-backed sync described in the architecture doc
-- lands in M1.

paths = require("paths")

config = {}

STORE_DIR = ".fossci"
DB_FILE = "fossci.db"

function config.store_dir(root)
    root = root or "."
    return paths.joinpath(root, STORE_DIR)
end

function config.db_path(root)
    return paths.joinpath(config.store_dir(root), DB_FILE)
end

function config.schemas_dir(root)
    return paths.joinpath(config.store_dir(root), "schemas")
end

function config.extensions_dir(root)
    return paths.joinpath(config.store_dir(root), "extensions")
end

function config.is_initialized(root)
    return paths.file_exists(config.db_path(root))
end

return config
