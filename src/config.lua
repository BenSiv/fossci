-- Resolves the fossci store location: a `.fossci/` directory holding the
-- ledger database, alongside `schemas/` and `extensions/` directories
-- that mirror what would be Fossil-tracked paths in the full bolt-on
-- (see doc/architecture.md).

paths = require("paths")
lfs = require("lfs")

config = {}

STORE_DIR = ".fossci"
DB_FILE = "fossci.db"

function config.find_checkout_root()
    -- Try DOCUMENT_ROOT (CGI mode)
    cwd = os.getenv("DOCUMENT_ROOT")
    if cwd == nil or cwd == "" then
        -- Try SCRIPT_DIRECTORY (CGI mode)
        cwd = os.getenv("SCRIPT_DIRECTORY")
    end
    if cwd == nil or cwd == "" then
        -- Fall back to current working directory (CLI mode)
        cwd = lfs.currentdir()
    end

    if cwd == nil then
        return "."
    end

    -- Clean path separator
    cwd = string.gsub(cwd, "\\", "/")

    scan_dir = cwd
    while scan_dir != nil and scan_dir != "" do
        fslck = paths.joinpath(scan_dir, ".fslckout")
        fossil_file = paths.joinpath(scan_dir, "_FOSSIL_")
        if paths.file_exists(fslck) or paths.file_exists(fossil_file) then
            return scan_dir
        end
        -- Move to parent directory
        par = paths.get_parent_dir(scan_dir)
        if par == nil or par == scan_dir then
            break
        end
        scan_dir = string.gsub(par, "/$", "")
    end

    -- If no checkout was found, fall back to starting directory
    return cwd
end

function config.store_dir(root)
    if root == nil then
        root = config.find_checkout_root()
    end
    return paths.joinpath(root, STORE_DIR)
end

function config.db_path(root)
    return paths.joinpath(config.store_dir(root), DB_FILE)
end

function config.schemas_dir(root)
    if root == nil then
        root = config.find_checkout_root()
    end
    return paths.joinpath(root, "schemas")
end

function config.extensions_dir(root)
    if root == nil then
        root = config.find_checkout_root()
    end
    return paths.joinpath(root, "extensions")
end

function config.views_dir(root)
    if root == nil then
        root = config.find_checkout_root()
    end
    return paths.joinpath(root, "views")
end

function config.is_initialized(root)
    return paths.file_exists(config.db_path(root))
end

return config
