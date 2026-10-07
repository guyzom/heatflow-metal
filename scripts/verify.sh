#!/bin/sh
set -eu
cd "$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
./scripts/swift.sh test -c release
./scripts/swift.sh build -c release
python3 scripts/check_cli.py
python3 scripts/verify_artifacts.py
