#!/bin/bash
# Runs the tests and builds dist/MiddleClick.app: universal (Apple Silicon + Intel), ad-hoc signed.
set -euo pipefail
cd "$(dirname "$0")"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
clang -Wall -Wextra -framework CoreGraphics -framework CoreFoundation -o "$tmp/click_test" test/click_test.c
"$tmp/click_test"

app=dist/MiddleClick.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp src/Info.plist "$app/Contents/"
clang -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter \
    -arch arm64 -arch x86_64 -mmacosx-version-min=12.0 \
    -framework Cocoa -framework ApplicationServices -framework IOKit \
    -o "$app/Contents/MacOS/MiddleClick" src/main.m
codesign --force --sign - "$app"
echo "Built $app"
