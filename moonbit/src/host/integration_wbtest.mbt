///|
/// Ports of the Python contract scenarios in tests/test_contracts.py against
/// the real example files, using the Node platform adapter. Runs under
/// `moon test --target js` with the adapter preloaded.

///|
struct Bundle {
  asset : @core.Val
  motion : @core.Val
  pack : @core.Val
  review : @core.Val
  plan : @core.Val
  pack_hash : String
  review_hash : String
}

///|
fn kit_root() -> String {
  default_root()
}

///|
fn load_bundle() -> Bundle raise @core.ContractError {
  let fs = real_fs()
  let folder = (fs.join)(kit_root(), "examples")
  let asset_path = (fs.join)(folder, "asset.yaml")
  let motion_path = (fs.join)(folder, "motion.yaml")
  let pack_path = (fs.join)(folder, "review-pack.json")
  let review_path = (fs.join)(folder, "review.json")
  {
    asset: @core.load(fs, asset_path),
    motion: @core.load(fs, motion_path),
    pack: @core.load(fs, pack_path),
    review: @core.load(fs, review_path),
    plan: @core.load(fs, (fs.join)(folder, "repair-plan.json")),
    pack_hash: @core.sha256_file(fs, pack_path),
    review_hash: @core.sha256_file(fs, review_path),
  }
}

///|
fn bundle_schemas() -> @core.Schemas raise @core.ContractError {
  load_schemas(real_fs(), kit_root())
}

///|
fn check(b : Bundle) -> Unit raise @core.ContractError {
  @core.validate_bundle(bundle_schemas(), b.asset, b.motion, b.pack, b.review, b.pack_hash, Some(b.plan), Some(b.review_hash))
}

///|
fn expects_error(b : Bundle) -> Bool {
  let mut raised = false
  try {
    check(b)
  } catch {
    _ => raised = true
  }
  raised
}

// ---- structural helpers ----------------------------------------------------

///|
fn get(b : @core.Val, key : String) -> @core.Val raise @core.ContractError {
  @core.vobj_get_required(@core.as_obj(b), key)
}

///|
fn get_obj(b : @core.Val, key : String) -> Array[(String, @core.Val)] raise @core.ContractError {
  @core.as_obj(get(b, key))
}

///|
fn get_list(b : @core.Val, key : String) -> Array[@core.Val] raise @core.ContractError {
  @core.as_arr(get(b, key))
}

///|
fn set_in(a : Array[(String, @core.Val)], key : String, value : @core.Val) -> Unit {
  let mut replaced = false
  for i = 0; i < a.length(); i = i + 1 {
    if a[i].0 == key {
      a[i] = (key, value)
      replaced = true
    }
  }
  if not(replaced) {
    a.push((key, value))
  }
}

///|
fn set(b : @core.Val, key : String, value : @core.Val) -> Unit raise @core.ContractError {
  set_in(@core.as_obj(b), key, value)
}

///|
fn set_obj(a : Array[(String, @core.Val)], key : String, value : @core.Val) -> Unit {
  set_in(a, key, value)
}

///|
fn int_of(v : @core.Val) -> Int raise @core.ContractError {
  @core.as_int(v)
}

///|
fn str_of(v : @core.Val) -> String raise @core.ContractError {
  @core.as_str(v)
}

///|
fn deep_copy(v : @core.Val) -> @core.Val {
  match v {
    @core.VNull => @core.VNull
    @core.VBool(x) => @core.VBool(x)
    @core.VInt(x) => @core.VInt(x)
    @core.VNum(x) => @core.VNum(x)
    @core.VStr(x) => @core.VStr(x)
    @core.VArr(a) => @core.VArr(a.map(fn(item) { deep_copy(item) }))
    @core.VObj(o) => @core.VObj(o.map(fn(entry) { (entry.0, deep_copy(entry.1)) }))
  }
}

///|
fn any_contains(items : Array[String], needle : String) -> Bool {
  let mut found = false
  for item in items {
    if item.contains(needle) {
      found = true
    }
  }
  found
}

///|
fn image_list(b : Bundle) -> Array[@core.Val] raise @core.ContractError {
  get_list(b.pack, "images")
}

///|
fn check_list(b : Bundle) -> Array[@core.Val] raise @core.ContractError {
  get_list(b.review, "checks")
}

// ---- contract scenarios (mirrors ContractsTest) ----------------------------

///|
test "example contracts pass" {
  assert_true(not(expects_error(load_bundle())))
}

///|
test "unknown top level field" {
  let b = load_bundle()
  set(b.asset, "quality_magic", @core.VBool(true))
  assert_true(expects_error(b))
}

///|
test "one based frames rejected" {
  let b = load_bundle()
  for frame in get_list(b.motion, "frames") {
    let fo = @core.as_obj(frame)
    set_obj(fo, "index", @core.VInt(int_of(@core.vobj_get_required(fo, "index")) + 1))
  }
  assert_true(expects_error(b))
}

///|
test "event at exclusive frame end rejected" {
  let b = load_bundle()
  let ev = @core.as_obj(get_list(b.motion, "events")[0])
  set_obj(ev, "offset_ms", @core.VInt(50))
  assert_true(expects_error(b))
}

///|
test "negative duration rejected" {
  let b = load_bundle()
  set_obj(@core.as_obj(get_list(b.motion, "frames")[0]), "duration_ms", @core.VInt(-1))
  assert_true(expects_error(b))
}

///|
test "unlisted direction rejected" {
  let b = load_bundle()
  set(b.motion, "direction", @core.VStr("N"))
  assert_true(expects_error(b))
}

///|
test "asset id mismatch" {
  let b = load_bundle()
  set(b.motion, "asset_id", @core.VStr("other"))
  assert_true(expects_error(b))
}

///|
test "anchor bounds" {
  let b = load_bundle()
  set_obj(get_obj(get(b.asset, "canvas"), "anchor"), "x", @core.VInt(65))
  assert_true(expects_error(b))
}

///|
test "missing frame in board" {
  let b = load_bundle()
  let cells = @core.as_arr(@core.vobj_get_required(@core.as_obj(image_list(b)[1]), "cells"))
  ignore(cells.pop())
  assert_true(expects_error(b))
}

///|
test "invalid board scale" {
  let b = load_bundle()
  let cells = @core.as_arr(@core.vobj_get_required(@core.as_obj(image_list(b)[1]), "cells"))
  set_obj(@core.as_obj(cells[0]), "scale", @core.VInt(3))
  assert_true(expects_error(b))
}

///|
test "duplicate image ids" {
  let b = load_bundle()
  set_obj(@core.as_obj(image_list(b)[1]), "id", @core.VStr("ref_e"))
  assert_true(expects_error(b))
}

///|
test "no reference image" {
  let b = load_bundle()
  set_obj(@core.as_obj(image_list(b)[0]), "role", @core.VStr("crop"))
  assert_true(expects_error(b))
}

///|
test "model cannot remove check" {
  let b = load_bundle()
  ignore(check_list(b).pop())
  assert_true(expects_error(b))
}

///|
test "model cannot add check" {
  let b = load_bundle()
  let checks = check_list(b)
  let extra = deep_copy(checks[0])
  set_obj(@core.as_obj(extra), "criterion_id", @core.VStr("invented.criterion"))
  checks.push(extra)
  assert_true(expects_error(b))
}

///|
test "pack cannot downgrade requirement" {
  let b = load_bundle()
  set_obj(@core.as_obj(get_list(b.pack, "required_checks")[0]), "blocking", @core.VBool(false))
  assert_true(expects_error(b))
}

///|
test "stale pack hash" {
  let b = load_bundle()
  set(b.review, "pack_sha256", @core.VStr("0".repeat(64)))
  assert_true(expects_error(b))
}

///|
test "unobservable cannot pass" {
  let b = load_bundle()
  set(b.review, "verdict", @core.VStr("pass"))
  assert_true(expects_error(b))
}

///|
test "failure cannot pass" {
  let b = load_bundle()
  let checks = check_list(b)
  let first_evidence = @core.as_arr(@core.vobj_get_required(@core.as_obj(checks[0]), "evidence"))
  for c in checks {
    let co = @core.as_obj(c)
    if str_of(@core.vobj_get_required(co, "result")) == "not_observable" {
      set_obj(co, "result", @core.VStr("pass"))
      set_obj(co, "evidence", @core.VArr(first_evidence.map(fn(e) { deep_copy(e) })))
    }
  }
  set(b.review, "evidence_requests", @core.VArr([]))
  set(b.review, "verdict", @core.VStr("pass"))
  assert_true(expects_error(b))
}

///|
test "no evidence for pass" {
  let b = load_bundle()
  set_obj(@core.as_obj(check_list(b)[0]), "evidence", @core.VArr([]))
  assert_true(expects_error(b))
}

///|
test "unknown image in evidence" {
  let b = load_bundle()
  let ev = @core.as_obj(@core.as_arr(@core.vobj_get_required(@core.as_obj(check_list(b)[0]), "evidence"))[0])
  set_obj(ev, "image_id", @core.VStr("invisible_image"))
  assert_true(expects_error(b))
}

///|
test "evidence cites invisible frame" {
  let b = load_bundle()
  let ev = @core.as_obj(@core.as_arr(@core.vobj_get_required(@core.as_obj(check_list(b)[0]), "evidence"))[0])
  set_obj(ev, "frame_indices", @core.VArr([@core.VInt(100)]))
  assert_true(expects_error(b))
}

///|
test "fail needs issue" {
  let b = load_bundle()
  set(b.review, "issues", @core.VArr([]))
  assert_true(expects_error(b))
}

///|
test "missing evidence request" {
  let b = load_bundle()
  set(b.review, "evidence_requests", @core.VArr([]))
  assert_true(expects_error(b))
}

///|
test "repair needs mask" {
  let b = load_bundle()
  set(get(b.plan, "scope"), "writable_masks", @core.VArr([]))
  assert_true(expects_error(b))
}

///|
test "repair parent hash" {
  let b = load_bundle()
  set(b.plan, "parent_manifest_sha256", @core.VStr("0".repeat(64)))
  assert_true(expects_error(b))
}

///|
test "repair unknown issue" {
  let b = load_bundle()
  set(b.plan, "issue_ids", @core.VArr([@core.VStr("invented_issue")]))
  assert_true(expects_error(b))
}

///|
test "runtime missing manifest" {
  let b = load_bundle()
  set(b.pack, "stage", @core.VStr("runtime"))
  set(b.review, "stage", @core.VStr("runtime"))
  assert_true(expects_error(b))
}

///|
test "board coordinate mapping" {
  let b = load_bundle()
  let cell = @core.as_obj(@core.as_arr(@core.vobj_get_required(@core.as_obj(image_list(b)[1]), "cells"))[0])
  let (x0, y0) = @core.board_to_canvas(cell, 32, 80)
  assert_eq(x0, 0)
  assert_eq(y0, 0)
  let (x1, y1) = @core.board_to_canvas(cell, 287, 335)
  assert_eq(x1, 63)
  assert_eq(y1, 63)
}

///|
test "board outside not clamped" {
  let b = load_bundle()
  let cell = @core.as_obj(@core.as_arr(@core.vobj_get_required(@core.as_obj(image_list(b)[1]), "cells"))[0])
  let mut raised = false
  try {
    let _ = @core.board_to_canvas(cell, 288, 80)
  } catch {
    _ => raised = true
  }
  assert_true(raised)
}

///|
test "artifact verification rejects fixture" {
  let b = load_bundle()
  let errors = @core.verify_references(real_fs(), kit_root(), [b.pack, b.plan])
  assert_true(any_contains(errors, "Fixture"))
  assert_true(any_contains(errors, "Missing artifact"))
}

///|
test "path traversal" {
  let zero = "0".repeat(64)
  let doc = @core.parse_json("{\"path\":\"../secret\",\"sha256\":\"" + zero + "\"}")
  let errors = @core.verify_references(real_fs(), kit_root(), [doc])
  assert_true(any_contains(errors, "Unsafe"))
}

///|
test "symlink escape" {
  let fs = real_fs()
  let base = (fs.join)(tmpdir(), "astrafact_symlink_test")
  ignore(mkdir(base))
  let outside = (fs.join)(tmpdir(), "astrafact_symlink_outside.txt")
  ignore(write_text(outside, "secret-bytes"))
  ignore(symlink(outside, (fs.join)(base, "link.txt")))
  let expected = @core.sha256_file(fs, outside)
  let doc = @core.parse_json("{\"path\":\"link.txt\",\"sha256\":\"" + expected + "\"}")
  let errors = @core.verify_references(fs, base, [doc])
  assert_true(any_contains(errors, "escapes root"))
}

///|
test "duplicate yaml keys" {
  let fs = real_fs()
  let p = (fs.join)(tmpdir(), "astrafact_dup_test.yaml")
  ignore(write_text(p, "a: 1\na: 2\n"))
  let mut raised = false
  try {
    let _ = @core.load(fs, p)
  } catch {
    _ => raised = true
  }
  assert_true(raised)
}

///|
test "duplicate json keys" {
  let fs = real_fs()
  let p = (fs.join)(tmpdir(), "astrafact_dup_test.json")
  ignore(write_text(p, "{\"a\": 1, \"a\": 2}"))
  let mut raised = false
  try {
    let _ = @core.load(fs, p)
  } catch {
    _ => raised = true
  }
  assert_true(raised)
}
