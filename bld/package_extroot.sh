#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: ./bld/package_extroot.sh <extroot-dir>

Stages the built fossci binary as a Fossil "/ext" CGI extension (see
doc/deployment.md and doc/architecture.md's "Fossil integration" section).

<extroot-dir> is the directory a Fossil admin points the "extroot: DIR"
CGI-script directive (or "--extroot DIR" for `fossil server`/`ui`/`http`)
at. For fossci's own checkout-root discovery to work (src/config.lua
walks up from the directory looking for .fslckout/_FOSSIL_), <extroot-dir>
must be inside the Fossil checkout holding this repository's schemas/,
extensions/, and .fossci/ store -- typically "<checkout>/.ext".

Requires bin/fossci to already be built (./bld/build.sh).
EOF
}

if [[ $# -ne 1 || "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    exit 1
fi

EXTROOT="$1"

# Change to project root (one level up from bld/)
cd "$(dirname "$0")/.."

if [[ ! -x bin/fossci ]]; then
    echo "Error: bin/fossci not found or not executable. Run ./bld/build.sh first." >&2
    exit 1
fi

mkdir -p "$EXTROOT"
cp bin/fossci "$EXTROOT/fossci"
chmod +x "$EXTROOT/fossci"

EXTROOT_ABS="$(cd "$EXTROOT" && pwd)"
echo "Staged fossci at $EXTROOT_ABS/fossci"
echo
echo "Point Fossil at it with one of:"
echo "  extroot: $EXTROOT_ABS       # in the CGI launcher script"
echo "  fossil server --extroot $EXTROOT_ABS ..."
