///|
/// Host filesystem/crypto/YAML abstraction. The MoonBit core never touches the
/// OS directly; platform adapters provide these functions. This keeps schema,
/// semantic and pixel logic pure and testable while confining Node.js usage to
/// the documented platform boundary.
pub(all) struct Fs {
  pub read_text : (String) -> String raise ContractError
  pub read_bytes : (String) -> Bytes raise ContractError
  pub sha256_hex : (Bytes) -> String
  pub is_file : (String) -> Bool
  pub realpath : (String) -> String
  pub is_within : (String, String) -> Bool
  pub join : (String, String) -> String
  pub parse_yaml : (String) -> String raise ContractError
}

///|
pub fn require(condition : Bool, message : String) -> Unit raise ContractError {
  if not(condition) {
    raise ContractError(message)
  }
}

///|
pub fn load(fs : Fs, path : String) -> Val raise ContractError {
  let text = (fs.read_text)(path)
  if path.has_suffix(".yaml") || path.has_suffix(".yml") {
    parse_json((fs.parse_yaml)(text))
  } else {
    parse_json(text)
  }
}

///|
pub fn sha256_file(fs : Fs, path : String) -> String raise ContractError {
  (fs.sha256_hex)((fs.read_bytes)(path))
}

// ---- typed field accessors -------------------------------------------------

///|
fn f_obj(o : Array[(String, Val)], k : String) -> Array[(String, Val)] raise ContractError {
  as_obj(vobj_get_required(o, k))
}

///|
fn f_arr(o : Array[(String, Val)], k : String) -> Array[Val] raise ContractError {
  as_arr(vobj_get_required(o, k))
}

///|
fn f_str(o : Array[(String, Val)], k : String) -> String raise ContractError {
  as_str(vobj_get_required(o, k))
}

///|
fn f_int(o : Array[(String, Val)], k : String) -> Int raise ContractError {
  as_int(vobj_get_required(o, k))
}

///|
fn f_bool(o : Array[(String, Val)], k : String) -> Bool raise ContractError {
  as_bool(vobj_get_required(o, k))
}

// ---- small set helpers -----------------------------------------------------

///|
fn contains_int(xs : Array[Int], x : Int) -> Bool {
  let mut found = false
  for y in xs {
    if y == x {
      found = true
    }
  }
  found
}

///|
fn contains_str(xs : Array[String], x : String) -> Bool {
  let mut found = false
  for y in xs {
    if y == x {
      found = true
    }
  }
  found
}

///|
fn set_eq_int(a : Array[Int], b : Array[Int]) -> Bool {
  let mut ok = true
  for x in a {
    if not(contains_int(b, x)) {
      ok = false
    }
  }
  for x in b {
    if not(contains_int(a, x)) {
      ok = false
    }
  }
  ok
}

///|
fn set_eq_str(a : Array[String], b : Array[String]) -> Bool {
  let mut ok = true
  for x in a {
    if not(contains_str(b, x)) {
      ok = false
    }
  }
  for x in b {
    if not(contains_str(a, x)) {
      ok = false
    }
  }
  ok
}

///|
fn subset_str(a : Array[String], b : Array[String]) -> Bool {
  let mut ok = true
  for x in a {
    if not(contains_str(b, x)) {
      ok = false
    }
  }
  ok
}

///|
fn intersects_str(a : Array[String], b : Array[String]) -> Bool {
  let mut hit = false
  for x in a {
    if contains_str(b, x) {
      hit = true
    }
  }
  hit
}

///|
fn unique_or_raise(values : Array[String], label : String) -> Unit raise ContractError {
  for i = 0; i < values.length(); i = i + 1 {
    for j = i + 1; j < values.length(); j = j + 1 {
      if values[i] == values[j] {
        raise ContractError("Duplicate " + label)
      }
    }
  }
}

///|
fn unique_int_or_raise(values : Array[Int], label : String) -> Unit raise ContractError {
  for i = 0; i < values.length(); i = i + 1 {
    for j = i + 1; j < values.length(); j = j + 1 {
      if values[i] == values[j] {
        raise ContractError("Duplicate " + label)
      }
    }
  }
}

///|
fn rect_check(
  rect : Array[(String, Val)],
  width : Int,
  height : Int,
  label : String,
) -> Unit raise ContractError {
  let x0 = f_int(rect, "x0")
  let y0 = f_int(rect, "y0")
  let x1 = f_int(rect, "x1")
  let y1 = f_int(rect, "y1")
  require(0 <= x0 && x0 < x1 && x1 <= width, label + ": invalid x bounds")
  require(0 <= y0 && y0 < y1 && y1 <= height, label + ": invalid y bounds")
}

///|
/// Map a board pixel to the source canvas. Cell interior only; never clamp.
pub fn board_to_canvas(cell : Array[(String, Val)], x : Int, y : Int) -> (Int, Int) raise ContractError {
  let board = f_obj(cell, "board_rect")
  let source = f_obj(cell, "source_rect")
  let scale = f_int(cell, "scale")
  let bx0 = f_int(board, "x0")
  let by0 = f_int(board, "y0")
  let bx1 = f_int(board, "x1")
  let by1 = f_int(board, "y1")
  require(bx0 <= x && x < bx1 && by0 <= y && y < by1, "Point is outside the cell; never clamp it")
  (f_int(source, "x0") + (x - bx0) / scale, f_int(source, "y0") + (y - by0) / scale)
}

// ---- schema selection ------------------------------------------------------

///|
pub struct Schemas {
  asset : Val
  motion : Val
  review_pack : Val
  review : Val
  repair_plan : Val
}

///|
pub fn schemas_from_json(
  asset : String,
  motion : String,
  review_pack : String,
  review : String,
  repair_plan : String,
) -> Schemas raise ContractError {
  {
    asset: parse_json(asset),
    motion: parse_json(motion),
    review_pack: parse_json(review_pack),
    review: parse_json(review),
    repair_plan: parse_json(repair_plan),
  }
}

///|
pub fn validate_document(schemas : Schemas, kind : String, data : Val) -> Unit raise ContractError {
  let schema = if kind == "asset" {
    schemas.asset
  } else if kind == "motion" {
    schemas.motion
  } else if kind == "review-pack" {
    schemas.review_pack
  } else if kind == "review" {
    schemas.review
  } else if kind == "repair-plan" {
    schemas.repair_plan
  } else {
    raise ContractError("Unknown schema kind: " + kind)
  }
  validate_document_schema(schema, data)
}

// ---- evidence --------------------------------------------------------------

///|
fn validate_evidence(
  ev : Array[(String, Val)],
  image_map : Array[(String, Val)],
  width : Int,
  height : Int,
) -> Unit raise ContractError {
  let image_id = f_str(ev, "image_id")
  let image = match vobj_get(image_map, image_id) {
    Some(im) => as_obj(im)
    None => raise ContractError("Unknown evidence image ID")
  }
  let visible : Array[Int] = []
  for cell_val in f_arr(image, "cells") {
    let cell = as_obj(cell_val)
    if f_str(cell, "subject") == "candidate" {
      match vobj_get(cell, "frame_index") {
        Some(VInt(i)) => visible.push(i)
        _ => ()
      }
    }
  }
  for fv in f_arr(ev, "frame_indices") {
    require(contains_int(visible, as_int(fv)), "Evidence cites a frame absent from that image")
  }
  match vobj_get(ev, "region") {
    Some(region) =>
      match region {
        VNull => ()
        _ => rect_check(as_obj(region), width, height, "Evidence region")
      }
    None => ()
  }
}

// ---- requirements ----------------------------------------------------------

///|
fn requirement_ids(reqs : Array[Val]) -> Array[String] raise ContractError {
  let ids : Array[String] = []
  for r in reqs {
    ids.push(f_str(as_obj(r), "id"))
  }
  ids
}

///|
fn blocking_ids(reqs : Array[Val]) -> Array[String] raise ContractError {
  let ids : Array[String] = []
  for r in reqs {
    let o = as_obj(r)
    if f_bool(o, "blocking") {
      ids.push(f_str(o, "id"))
    }
  }
  ids
}

///|
fn allowed_pixel_modes(kind : String) -> Array[String] {
  if kind == "pixel_patch" {
    ["masked"]
  } else if kind == "provider_edit" {
    ["masked", "full_frames"]
  } else if kind == "metadata_patch" {
    ["none"]
  } else if kind == "spec_change" {
    ["none"]
  } else if kind == "regenerate" {
    ["new_candidate"]
  } else {
    []
  }
}

// ---- main bundle validation ------------------------------------------------

///|
pub fn validate_bundle(
  schemas : Schemas,
  asset : Val,
  motion : Val,
  pack : Val,
  review : Val,
  pack_sha256 : String,
  plan : Val?,
  review_sha256 : String?,
) -> Unit raise ContractError {
  let asset_o = as_obj(asset)
  let motion_o = as_obj(motion)
  let pack_o = as_obj(pack)
  let review_o = as_obj(review)
  validate_document(schemas, "asset", asset)
  validate_document(schemas, "motion", motion)
  validate_document(schemas, "review-pack", pack)
  validate_document(schemas, "review", review)

  let canvas = f_obj(asset_o, "canvas")
  let width = f_int(canvas, "width")
  let height = f_int(canvas, "height")
  let anchor = f_obj(canvas, "anchor")
  let ax = f_int(anchor, "x")
  let ay = f_int(anchor, "y")
  require(0 <= ax && ax <= width && 0 <= ay && ay <= height, "Anchor outside canvas")

  let asset_id = f_str(asset_o, "asset_id")
  require(f_str(motion_o, "asset_id") == asset_id && f_str(pack_o, "asset_id") == asset_id, "Asset ID mismatch")
  require(f_str(motion_o, "motion_id") == f_str(pack_o, "motion_id"), "Motion ID mismatch")
  let directions : Array[String] = []
  for d in f_arr(asset_o, "directions") {
    directions.push(as_str(d))
  }
  require(contains_str(directions, f_str(motion_o, "direction")), "Direction not allowed by asset")
  let asset_runtime = f_obj(asset_o, "runtime")
  require(f_str(motion_o, "root_motion") == f_str(asset_runtime, "root_motion"), "Root motion mismatch")

  let frames = f_arr(motion_o, "frames")
  let count = frames.length()
  let indices : Array[Int] = []
  for frame in frames {
    indices.push(f_int(as_obj(frame), "index"))
  }
  let mut contiguous = indices.length() == count
  for i = 0; i < indices.length(); i = i + 1 {
    if indices[i] != i {
      contiguous = false
    }
  }
  require(contiguous, "Frame indices must be contiguous and zero-based")
  for event in f_arr(motion_o, "events") {
    let eo = as_obj(event)
    let frame_index = f_int(eo, "frame")
    require(frame_index < count, "Event frame out of range")
    require(f_int(eo, "offset_ms") < f_int(as_obj(frames[frame_index]), "duration_ms"), "Event offset must be inside its frame")
  }

  let asset_reqs = f_arr(asset_o, "requirements")
  let motion_reqs = f_arr(motion_o, "requirements")
  let runtime_reqs = f_arr(asset_runtime, "requirements")
  let all_reqs : Array[Val] = []
  all_reqs.append(asset_reqs)
  all_reqs.append(motion_reqs)
  all_reqs.append(runtime_reqs)
  unique_or_raise(requirement_ids(all_reqs), "requirement ID")

  let expected : Array[Val] = []
  expected.append(asset_reqs)
  expected.append(motion_reqs)
  let stage = f_str(pack_o, "stage")
  if stage == "runtime" {
    expected.append(runtime_reqs)
    let bindings = f_obj(pack_o, "bindings")
    let runtime_manifest = vobj_get_required(bindings, "runtime_manifest")
    require(not(is_null(runtime_manifest)), "Runtime stage needs a runtime manifest")
    let has_runtime_image = {
      let mut found = false
      for im in f_arr(pack_o, "images") {
        if f_str(as_obj(im), "role") == "runtime_frame" {
          found = true
        }
      }
      found
    }
    require(has_runtime_image, "Runtime stage needs actual runtime images")
  }
  let required_checks = f_arr(pack_o, "required_checks")
  require(veq(VArr(required_checks), VArr(expected)), "Required checks differ from authoritative specs")
  let expected_ids = requirement_ids(expected)
  let blocking = blocking_ids(expected)

  let images = f_arr(pack_o, "images")
  let image_ids : Array[String] = []
  let image_map : Array[(String, Val)] = []
  for im in images {
    let io = as_obj(im)
    let id = f_str(io, "id")
    image_ids.push(id)
    image_map.push((id, im))
  }
  unique_or_raise(image_ids, "image ID")
  let has_reference = {
    let mut found = false
    for im in images {
      if f_str(as_obj(im), "role") == "reference" {
        found = true
      }
    }
    found
  }
  require(has_reference, "Reference image missing")

  let covered : Array[Int] = []
  let cell_ids : Array[String] = []
  for im in images {
    let io = as_obj(im)
    let role = f_str(io, "role")
    let iw = f_int(io, "width")
    let ih = f_int(io, "height")
    for cell_val in f_arr(io, "cells") {
      let cell = as_obj(cell_val)
      cell_ids.push(f_str(cell, "id"))
      let sr = f_obj(cell, "source_rect")
      let br = f_obj(cell, "board_rect")
      let scale = f_int(cell, "scale")
      rect_check(sr, width, height, "Source rect")
      rect_check(br, iw, ih, "Board rect")
      require(f_int(br, "x1") - f_int(br, "x0") == (f_int(sr, "x1") - f_int(sr, "x0")) * scale, "Horizontal scale mismatch")
      require(f_int(br, "y1") - f_int(br, "y0") == (f_int(sr, "y1") - f_int(sr, "y0")) * scale, "Vertical scale mismatch")
      let subject = f_str(cell, "subject")
      let index_val = vobj_get_required(cell, "frame_index")
      if subject == "reference" {
        require(is_null(index_val), "Reference cell must not impersonate a candidate frame")
      } else {
        match index_val {
          VInt(i) => require(0 <= i && i < count, "Cell frame index out of range")
          _ => raise ContractError("Cell frame index out of range")
        }
      }
      if subject == "candidate" && (role == "contact_sheet" || role == "runtime_frame") && f_int(sr, "x0") == 0 && f_int(sr, "y0") == 0 && f_int(sr, "x1") == width && f_int(sr, "y1") == height {
        match index_val {
          VInt(i) => if not(contains_int(covered, i)) { covered.push(i) }
          _ => ()
        }
      }
    }
  }
  unique_or_raise(cell_ids, "cell ID")
  let all_frames : Array[Int] = []
  for i = 0; i < count; i = i + 1 {
    all_frames.push(i)
  }
  require(set_eq_int(covered, all_frames), "Some full candidate frames are missing from evidence")

  require(f_str(review_o, "pack_id") == f_str(pack_o, "pack_id"), "Review pack ID mismatch")
  require(f_str(review_o, "pack_sha256") == pack_sha256, "Review is bound to stale or different pack bytes")
  require(f_str(review_o, "candidate_id") == f_str(pack_o, "candidate_id"), "Review candidate ID mismatch")
  require(f_str(review_o, "stage") == stage, "Review stage mismatch")

  let checks = f_arr(review_o, "checks")
  let criterion_ids : Array[String] = []
  for c in checks {
    criterion_ids.push(f_str(as_obj(c), "criterion_id"))
  }
  unique_or_raise(criterion_ids, "review criterion")
  require(set_eq_str(criterion_ids, expected_ids), "Missing or unknown review criterion")
  let check_map : Array[(String, Val)] = []
  for c in checks {
    check_map.push((f_str(as_obj(c), "criterion_id"), c))
  }

  for c in checks {
    let co = as_obj(c)
    let result = f_str(co, "result")
    if result == "pass" || result == "fail" {
      require(f_arr(co, "evidence").length() > 0, "Observable check needs evidence")
    }
    for ev in f_arr(co, "evidence") {
      validate_evidence(as_obj(ev), image_map, width, height)
    }
  }

  let issues = f_arr(review_o, "issues")
  let issue_ids : Array[String] = []
  let issue_criteria : Array[String] = []
  for issue in issues {
    let io = as_obj(issue)
    issue_ids.push(f_str(io, "id"))
    issue_criteria.push(f_str(io, "criterion_id"))
  }
  unique_or_raise(issue_ids, "issue ID")
  for issue in issues {
    let io = as_obj(issue)
    let criterion_id = f_str(io, "criterion_id")
    match vobj_get(check_map, criterion_id) {
      Some(c) => require(f_str(as_obj(c), "result") == "fail", "Issue must correspond to a failed check")
      None => raise ContractError("Issue has unknown criterion")
    }
    for ev in f_arr(io, "evidence") {
      validate_evidence(as_obj(ev), image_map, width, height)
    }
  }
  let failures : Array[String] = []
  let unobserved : Array[String] = []
  for c in checks {
    let co = as_obj(c)
    let result = f_str(co, "result")
    let id = f_str(co, "criterion_id")
    if result == "fail" {
      failures.push(id)
    } else if result == "not_observable" {
      unobserved.push(id)
    }
  }
  require(set_eq_str(failures, issue_criteria), "Every failed check needs an issue")
  let requests : Array[String] = []
  for r in f_arr(review_o, "evidence_requests") {
    requests.push(f_str(as_obj(r), "criterion_id"))
  }
  require(set_eq_str(unobserved, requests), "Evidence requests must cover exactly the unobservable checks")

  let verdict = f_str(review_o, "verdict")
  if intersects_str(blocking, unobserved) {
    require(verdict == "needs_evidence", "Unobservable blocking checks cannot pass")
  } else if intersects_str(blocking, failures) {
    require(verdict == "repair" || verdict == "reject", "Blocking failures cannot pass")
  } else {
    require(verdict == "pass", "No blocking failure: record advisory issues without vetoing")
  }

  match plan {
    None => ()
    Some(plan_val) => {
      validate_document(schemas, "repair-plan", plan_val)
      let plan_o = as_obj(plan_val)
      require(f_str(plan_o, "parent_candidate_id") == f_str(pack_o, "candidate_id"), "Repair parent mismatch")
      let pack_bindings = f_obj(pack_o, "bindings")
      let candidate_manifest = f_obj(pack_bindings, "candidate_manifest")
      require(f_str(plan_o, "parent_manifest_sha256") == f_str(candidate_manifest, "sha256"), "Repair parent hash mismatch")
      let matches_review = match review_sha256 {
        Some(h) => f_str(plan_o, "source_review_sha256") == h
        None => false
      }
      require(matches_review, "Repair review hash mismatch")
      let plan_issue_ids : Array[String] = []
      for v in f_arr(plan_o, "issue_ids") {
        plan_issue_ids.push(as_str(v))
      }
      require(subset_str(plan_issue_ids, issue_ids), "Repair refers to an unknown issue")
      let scope = f_obj(plan_o, "scope")
      let frame_indices : Array[Int] = []
      for v in f_arr(scope, "frame_indices") {
        frame_indices.push(as_int(v))
      }
      for fi in frame_indices {
        require(fi < count, "Repair frame out of range")
      }
      let mask_frames : Array[Int] = []
      for m in f_arr(scope, "writable_masks") {
        mask_frames.push(f_int(as_obj(m), "frame_index"))
      }
      unique_int_or_raise(mask_frames, "mask frame")
      for mf in mask_frames {
        require(contains_int(frame_indices, mf), "Mask is outside declared repair frames")
      }
      let pixel_mode = f_str(scope, "pixel_mode")
      if pixel_mode == "masked" {
        require(mask_frames.length() > 0 && set_eq_int(mask_frames, frame_indices), "Masked repair needs one mask per changed frame")
      } else {
        require(mask_frames.length() == 0, "Masks are only valid for masked edits")
      }
      if pixel_mode == "none" {
        require(frame_indices.length() == 0, "Metadata-only edit cannot declare pixel frame changes")
      }
      let operation = f_obj(plan_o, "operation")
      let kind = f_str(operation, "kind")
      if kind == "metadata_patch" {
        require(pixel_mode == "none", "Metadata patch must not edit pixels")
      }
      if kind == "regenerate" {
        require(pixel_mode == "new_candidate", "Regeneration must produce a new candidate")
      }
      require(contains_str(allowed_pixel_modes(kind), pixel_mode), "Operation and pixel permissions disagree")
      if kind == "metadata_patch" {
        require(f_arr(scope, "allowed_metadata_paths").length() > 0, "Metadata edit needs explicit field permissions")
      }
    }
  }
}

// ---- referenced artifact verification --------------------------------------

///|
fn has_dotdot(name : String) -> Bool {
  let mut found = false
  for part in name.split("/") {
    if part.to_string() == ".." {
      found = true
    }
  }
  found
}

///|
fn visit_references(
  fs : Fs,
  root : String,
  value : Val,
  errors : Array[String],
  seen : Array[(String, String)],
) -> Unit raise ContractError {
  match value {
    VArr(items) =>
      for item in items {
        visit_references(fs, root, item, errors, seen)
      }
    VObj(entries) => {
      match vobj_get(entries, "fixture") {
        Some(VBool(true)) => errors.push("Fixture document cannot be treated as production evidence")
        _ => ()
      }
      match (vobj_get(entries, "path"), vobj_get(entries, "sha256")) {
        (Some(VStr(name)), Some(VStr(expected))) => {
          let key = (name, expected)
          let mut already = false
          for k in seen {
            if k.0 == name && k.1 == expected {
              already = true
            }
          }
          if not(already) {
            seen.push(key)
            if name.has_prefix("/") || has_dotdot(name) || name.contains("\\") {
              errors.push("Unsafe artifact path: " + name)
            } else {
              let joined = (fs.join)(root, name)
              let resolved = (fs.realpath)(joined)
              if not((fs.is_within)(resolved, root)) {
                errors.push("Artifact escapes root: " + name)
              } else if not((fs.is_file)(resolved)) {
                errors.push("Missing artifact: " + name)
              } else {
                let actual = (fs.sha256_hex)((fs.read_bytes)(resolved))
                if actual != expected {
                  errors.push("Artifact hash mismatch: " + name)
                } else if name.has_suffix(".json") || name.has_suffix(".yaml") || name.has_suffix(".yml") {
                  try {
                    let nested = load(fs, resolved)
                    visit_references(fs, root, nested, errors, seen)
                  } catch {
                    ContractError(message) =>
                      errors.push("Invalid referenced document " + name + ": " + message)
                  }
                }
              }
            }
          }
        }
        _ => ()
      }
      for entry in entries {
        match entry.1 {
          VObj(_) | VArr(_) => visit_references(fs, root, entry.1, errors, seen)
          _ => ()
        }
      }
    }
    _ => ()
  }
}

///|
/// Check local referenced bytes, paths and fixture markers. Never fetches URLs.
pub fn verify_references(fs : Fs, root : String, documents : Array[Val]) -> Array[String] raise ContractError {
  let resolved_root = (fs.realpath)(root)
  let errors : Array[String] = []
  let seen : Array[(String, String)] = []
  for document in documents {
    visit_references(fs, resolved_root, document, errors, seen)
  }
  errors
}
