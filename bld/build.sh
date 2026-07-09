#!/usr/bin/env bash
set -euo pipefail

VERBOSE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            cat <<'EOF'
Usage: ./bld/build.sh [options]

Options:
  -v, --verbose   Print full build command output
  -h, --help      Show this help
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use --help for usage." >&2
            exit 1
            ;;
    esac
done

run_cmd() {
    if [[ "$VERBOSE" -eq 1 ]]; then
        "$@"
    else
        "$@" >>"$BUILD_LOG" 2>&1
    fi
}

on_error() {
    if [[ "$VERBOSE" -eq 0 ]]; then
        echo "Build failed. Re-run with --verbose for full output." >&2
        echo "Last build log lines:" >&2
        tail -n 40 "$BUILD_LOG" >&2 || true
    fi
}

# Create temp dir
TMPDIR=$(mktemp -d)
BUILD_LOG=$(mktemp)
trap on_error ERR
trap 'rm -rf "$TMPDIR" "$BUILD_LOG"' EXIT

# Change to project root (one level up from bld/)
cd "$(dirname "$0")/.."

# Determine absolute paths (allow env override, default to sibling checkout)
if [ -z "${LUAM_DIR:-}" ]; then
    LUAM_DIR=$(cd ../luam && pwd)
fi
LUAM_BIN="$LUAM_DIR/bin/luam"
STATIC_TOOL="$LUAM_DIR/lib/static/init.lua"
LUAM_LIB="$LUAM_DIR/obj/liblua.a"

if [ ! -f "$LUAM_LIB" ]; then
    echo "Error: $LUAM_LIB not found. Set LUAM_DIR to a built luam checkout." >&2
    exit 1
fi

echo "Preparing build"
# Copy fossci sources
run_cmd cp -R src/* "$TMPDIR"/

# Copy luam standard libraries
run_cmd cp "$LUAM_DIR/lib/"*.lua "$TMPDIR"/
run_cmd cp "$LUAM_DIR/lib/lfs/init.lua" "$TMPDIR/lfs_pure.lua" 2>/dev/null || true
run_cmd cp "$LUAM_DIR/lib/dkjson/init.lua" "$TMPDIR/dkjson.lua"

# Remove static.lua (tool) to prevent it from being compiled into the binary source list inadvertently
run_cmd rm -f "$TMPDIR"/static.lua

# Build
pushd "$TMPDIR" >/dev/null

# Construct file list; fossci.lua must be first (main entry point)
FILES="fossci.lua $(find . -type f -name '*.lua' | grep -v '^\./fossci\.lua$' | sed 's|^\./||' | tr '\n' ' ')"

echo "Files to bundle: $FILES"
echo "Generating C source"
run_cmd env CC="" "$LUAM_BIN" "$STATIC_TOOL" \
    $FILES \
    "$LUAM_LIB" \
    -I "$LUAM_DIR/src" \
    -lm -ldl -lreadline -lpthread

# Inject lsqlite3 preload. Schemas and extension manifests are plain Luam
# table files (loaded via loadstring+setfenv, see doc/schema.md) -- no
# YAML/JSON parser is linked in for that path. JSON (dkjson, pure Luam,
# already copied above) is only used for internal ledger serialization
# and, later, the Fossil API boundary.
run_cmd sed -i '/luaL_openlibs(L);/a \
  int luaopen_sqlite3(lua_State *L); \
  lua_getglobal(L, "package"); \
  lua_getfield(L, -1, "preload"); \
  lua_pushcfunction(L, luaopen_sqlite3); \
  lua_setfield(L, -2, "sqlite3"); \
  lua_pop(L, 2);' fossci.static.c

# Compile lsqlite3
run_cmd cc -c -O2 -I"$LUAM_DIR/src" "$LUAM_DIR/lib/sqlite/lsqlite3.c" -o lsqlite3.o

# Compile binary
run_cmd cc -Os fossci.static.c lsqlite3.o "$LUAM_LIB" \
    -I "$LUAM_DIR/src" \
    -lm -ldl -lreadline -lpthread -lsqlite3 \
    -Wl,--export-dynamic \
    -o fossci

popd >/dev/null

# bin/ holds only final binaries
run_cmd mkdir -p bin
run_cmd mv "$TMPDIR"/fossci bin/
echo "Build complete. Binary in bin/fossci"
if [[ "$VERBOSE" -eq 1 ]]; then
    ls -lh bin/fossci
fi
