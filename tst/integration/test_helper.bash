# tst/integration/test_helper.bash
# Shared setup for bats CLI/CGI integration tests -- each test gets a
# fresh scratch directory (never the repo root, to avoid colliding with
# a developer's own .fossci/ store) and the real, built fossci binary.

resolve_fossci() {
    if [ -x "$PROJECT_ROOT/bin/fossci" ]; then
        FOSSCI="$PROJECT_ROOT/bin/fossci"
    else
        FOSSCI="fossci"
    fi
}

setup_test_env() {
    export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    resolve_fossci
    export TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
}

cleanup_test_env() {
    cd "$PROJECT_ROOT"
    rm -rf "$TEST_DIR"
}

# Runs the fossci binary in real CGI mode -- the same GATEWAY_INTERFACE
# env-var trigger Fossil's own /ext dispatch uses (see fossci.lua's
# main()), not the CLI dispatch. Sets sane defaults for the env vars
# Fossil would normally inject; override any of them by exporting the
# var before calling this.
run_cgi() {
    local path_info="$1"
    local query_string="${2:-}"
    local method="${3:-GET}"
    GATEWAY_INTERFACE="CGI/1.1" \
    REQUEST_METHOD="$method" \
    PATH_INFO="$path_info" \
    QUERY_STRING="$query_string" \
    FOSSIL_USER="${FOSSIL_USER:-testuser}" \
    FOSSIL_CAPABILITIES="${FOSSIL_CAPABILITIES:-i}" \
    FOSSIL_NONCE="${FOSSIL_NONCE:-testnonce}" \
    run "$FOSSCI"
}
