#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
export MACOSX_DEPLOYMENT_TARGET=13.0
sources=()
for file in Sources/*.swift; do
    [[ "$file" == "Sources/main.swift" ]] || sources+=("$file")
done
swiftc -O -import-objc-header Sources/Private.h -framework IOKit \
    "${sources[@]}" tools/tests/main.swift -o build/verify
ln -sfn "$PWD/assets/characters" build/Characters
BOOGIE_FAKE_LID=110 BOOGIE_FAKE_LUX=100 BOOGIE_FAKE_TILT=0 \
    ./build/verify "$PWD/assets/characters"
