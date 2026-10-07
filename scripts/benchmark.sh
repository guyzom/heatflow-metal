#!/bin/sh
set -eu
cd "$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
./scripts/swift.sh build -c release
mkdir -p output
# Separate metadata, no serial numbers or account identifiers.
{ swift --version 2>&1; uname -m; sw_vers; } > output/toolchain.txt
exec .build/release/heatflow benchmark "$@"
