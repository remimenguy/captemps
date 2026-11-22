#!/bin/bash
set -euo pipefail

project="$(cd "$(dirname "$0")/.." && pwd)"
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT

xcrun swiftc "$project/Shared/BlockPhase.swift" "$project/Tests/BlockPhaseTests.swift" -o "$build/tests"
"$build/tests"
