#!/bin/sh
# Keep compiler/package caches in this checkout, including in restricted workspaces.
set -eu
cd "$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p .cache/clang .cache/swift .cache/swiftpm .cache/config .cache/security
export CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang"
export SWIFT_MODULECACHE_PATH="$PWD/.cache/swift"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.cache/swift"
# Command Line Tools ship Swift Testing but may omit XCTest.
if [ "${1:-}" = "test" ]; then
    set -- "$@" --disable-xctest
    if [ "$(uname -s)" = Darwin ]; then
        developer_path=$(xcode-select -p)
        testing_frameworks="$developer_path/Library/Developer/Frameworks"
        testing_plugin="$developer_path/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
        if [ -d "$testing_frameworks/Testing.framework" ]; then
            set -- "$@" -Xswiftc "-F$testing_frameworks" -Xlinker "-F$testing_frameworks" -Xlinker -rpath -Xlinker "$testing_frameworks"
        fi
        if [ -f "$testing_plugin" ]; then
            set -- "$@" -Xswiftc -load-plugin-library -Xswiftc "$testing_plugin"
        fi
    fi
fi
exec swift "$@" --build-system native --cache-path "$PWD/.cache/swiftpm" --config-path "$PWD/.cache/config" --security-path "$PWD/.cache/security" --disable-sandbox
