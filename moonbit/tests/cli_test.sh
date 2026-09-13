#!/bin/sh
# Integration checks for the MoonBit CLI. Exercises the same acceptance
# boundaries the Python oracle covers: valid contracts-only pass, intentional
# --verify-artifacts failure, mutated spec bytes, stale/malformed/duplicate
# data, and the pixel guard over real decoded PNGs.
set -u

HERE=$(cd "$(dirname "$0")/.." && pwd)
ROOT=$(cd "$HERE/.." && pwd)
CLI="$HERE/bin/astrafact"
ADAPTER="$HERE/js/adapter.cjs"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

check() {
  name=$1
  expected=$2
  shift 2
  "$@" >"$TMP/out.txt" 2>"$TMP/err.txt"
  code=$?
  if [ "$code" -eq "$expected" ]; then
    pass=$((pass + 1))
    echo "ok   - $name"
  else
    fail=$((fail + 1))
    echo "FAIL - $name (exit $code, expected $expected)"
    cat "$TMP/out.txt" "$TMP/err.txt"
  fi
}

# 1. Contracts-only pass on examples.
check "examples contracts-only pass" 0 "$CLI" --root "$ROOT" --dir examples
grep -q "PASS: schema and cross-file contracts only" "$TMP/out.txt" || { echo "missing pass disclaimer"; fail=$((fail+1)); }
grep -q "NOT visual approval" "$TMP/out.txt" || { echo "missing disclaimer"; fail=$((fail+1)); }

# 2. Intentional failure of --verify-artifacts on the fixture examples.
check "examples verify-artifacts intentionally fails" 1 "$CLI" --root "$ROOT" --dir examples --verify-artifacts

# Build a mutable copy of the contract surface.
cp -R "$ROOT/schemas" "$TMP/schemas"
cp -R "$ROOT/examples" "$TMP/examples"
cp -R "$ROOT/prompts" "$TMP/prompts"

# 3. Mutated spec bytes must be detected through the binding hash.
printf '\n# mutate\n' >>"$TMP/examples/asset.yaml"
check "mutated spec bytes fail" 1 "$CLI" --root "$TMP" --dir examples
# Restore the original asset bytes.
cp "$ROOT/examples/asset.yaml" "$TMP/examples/asset.yaml"

# 4. Stale pack hash in the review.
node -e '
const fs=require("fs");
const p=process.argv[1];
const j=JSON.parse(fs.readFileSync(p,"utf8"));
j.pack_sha256="0".repeat(64);
fs.writeFileSync(p,JSON.stringify(j));
' "$TMP/examples/review.json"
check "stale pack hash fails" 1 "$CLI" --root "$TMP" --dir examples
cp "$ROOT/examples/review.json" "$TMP/examples/review.json"

# 5. Duplicate JSON keys must be rejected at load time.
printf '{"schema_version":"0.1","schema_version":"0.2"}' >"$TMP/examples/review.json"
check "duplicate json keys fail" 1 "$CLI" --root "$TMP" --dir examples
cp "$ROOT/examples/review.json" "$TMP/examples/review.json"

# 6. Malformed JSON must be rejected at load time.
printf '{"schema_version": ' >"$TMP/examples/review.json"
check "malformed json fails" 1 "$CLI" --root "$TMP" --dir examples
cp "$ROOT/examples/review.json" "$TMP/examples/review.json"

# 7. Re-added, verified examples pass again.
check "restored examples pass again" 0 "$CLI" --root "$TMP" --dir examples

# 8. Pixel guard fixtures.
mkdir -p "$TMP/px"
node -e '
require(process.argv[1]);
const a=globalThis.__astrafact;
const w=4,h=4;
const before=Buffer.alloc(w*h*4,0);
const after=Buffer.alloc(w*h*4,0);
after[(1*w+1)*4+3]=255; after[(1*w+1)*4+0]=255; after[(1*w+1)*4+1]=255; after[(1*w+1)*4+2]=255;
const mask=Buffer.alloc(w*h,0); mask[1*w+1]=255;
const maskZero=Buffer.alloc(w*h,0);
const soft=Buffer.alloc(w*h,0); soft[1*w+1]=128;
const rgbaBefore=Buffer.from(before), rgbaAfter=Buffer.from(after);
a.encodePng(process.argv[2]+"/before.png",w,h,4,rgbaBefore);
a.encodePng(process.argv[2]+"/after.png",w,h,4,rgbaAfter);
a.encodePng(process.argv[2]+"/after_unauth.png",w,h,4,Buffer.from(after));
a.encodePng(process.argv[2]+"/mask_ok.png",w,h,1,mask);
a.encodePng(process.argv[2]+"/mask_zero.png",w,h,1,maskZero);
a.encodePng(process.argv[2]+"/mask_soft.png",w,h,1,soft);
a.encodePng(process.argv[2]+"/mask_rgb.png",w,h,3,Buffer.alloc(w*h*3,255));
a.encodePng(process.argv[2]+"/after_big.png",8,8,4,Buffer.alloc(8*8*4,0));
' "$ADAPTER" "$TMP/px"

check "pixel guard authorized change passes" 0 "$CLI" pixel-guard --before "$TMP/px/before.png" --after "$TMP/px/after.png" --mask "$TMP/px/mask_ok.png"
check "pixel guard unauthorized change fails" 1 "$CLI" pixel-guard --before "$TMP/px/before.png" --after "$TMP/px/after_unauth.png" --mask "$TMP/px/mask_zero.png"
check "pixel guard soft mask fails" 1 "$CLI" pixel-guard --before "$TMP/px/before.png" --after "$TMP/px/after.png" --mask "$TMP/px/mask_soft.png"
check "pixel guard rgb mask fails" 1 "$CLI" pixel-guard --before "$TMP/px/before.png" --after "$TMP/px/after.png" --mask "$TMP/px/mask_rgb.png"
check "pixel guard size mismatch fails" 1 "$CLI" pixel-guard --before "$TMP/px/before.png" --after "$TMP/px/after_big.png" --mask "$TMP/px/mask_ok.png"

echo
echo "CLI integration: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
