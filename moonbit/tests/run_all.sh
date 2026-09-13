#!/bin/sh
# Full MoonBit regression + integration run.
set -e

TESTS=$(cd "$(dirname "$0")" && pwd)
MOONBIT=$(cd "$TESTS/.." && pwd)
ADAPTER="$MOONBIT/js/adapter.cjs"
ROOT=$(cd "$MOONBIT/.." && pwd)

cd "$MOONBIT"

echo "== moon check (wasm-gc, pure core) =="
moon check

echo "== moon check (js, platform + CLI) =="
moon check --target js

echo "== moon test (wasm-gc: JSON/schema/regex/pixel core) =="
moon test

echo "== moon test (js: platform-backed contract scenarios) =="
NODE_OPTIONS="--require $ADAPTER" moon test --target js

echo "== moon build (js release) =="
moon build --target js --release

echo "== CLI + pixel guard integration =="
sh "$TESTS/cli_test.sh"

echo
echo "All MoonBit checks and integration tests passed."
