///|
/// CLI entry point. `--root/--dir/--verify-artifacts` mirrors
/// `tools/validate.py`; `pixel-guard --before/--after/--mask` exposes the
/// pixel-scope guard over decoded PNG files.

///|
fn field_path(v : @core.Val, keys : Array[String]) -> @core.Val raise @core.ContractError {
  let mut current = v
  for key in keys {
    current = @core.vobj_get_required(@core.as_obj(current), key)
  }
  current
}

///|
fn run_validate(argv : Array[String]) -> Unit raise @core.ContractError {
  let fs = @host.real_fs()
  let mut root_opt : String? = None
  let mut dir = "examples"
  let mut verify = false
  let mut i = 0
  while i < argv.length() {
    let a = argv[i]
    if a == "--root" && i + 1 < argv.length() {
      root_opt = Some(argv[i + 1])
      i = i + 2
    } else if a == "--dir" && i + 1 < argv.length() {
      dir = argv[i + 1]
      i = i + 2
    } else if a == "--verify-artifacts" {
      verify = true
      i = i + 1
    } else {
      raise @core.ContractError("Unknown argument: " + a)
    }
  }
  let root = match root_opt {
    Some(r) => (fs.realpath)(r)
    None => @host.default_root()
  }
  let folder = if dir.has_prefix("/") { dir } else { (fs.join)(root, dir) }
  let asset_path = (fs.join)(folder, "asset.yaml")
  let motion_path = (fs.join)(folder, "motion.yaml")
  let pack_path = (fs.join)(folder, "review-pack.json")
  let review_path = (fs.join)(folder, "review.json")
  let asset = @core.load(fs, asset_path)
  let motion = @core.load(fs, motion_path)
  let pack = @core.load(fs, pack_path)
  let review = @core.load(fs, review_path)
  if @core.sha256_file(fs, asset_path) != @core.as_str(field_path(pack, ["bindings", "asset_spec", "sha256"])) {
    raise @core.ContractError("Asset file bytes differ from the bound spec")
  }
  if @core.sha256_file(fs, motion_path) != @core.as_str(field_path(pack, ["bindings", "motion_spec", "sha256"])) {
    raise @core.ContractError("Motion file bytes differ from the bound spec")
  }
  let plan_path = (fs.join)(folder, "repair-plan.json")
  let plan : @core.Val? = if (fs.is_file)(plan_path) {
    Some(@core.load(fs, plan_path))
  } else {
    None
  }
  let schemas = @host.load_schemas(fs, root)
  @core.validate_bundle(
    schemas,
    asset,
    motion,
    pack,
    review,
    @core.sha256_file(fs, pack_path),
    plan,
    Some(@core.sha256_file(fs, review_path)),
  )
  if verify {
    let documents : Array[@core.Val] = [pack]
    match plan {
      Some(p) => documents.push(p)
      None => ()
    }
    let errors = @core.verify_references(fs, root, documents)
    if errors.length() > 0 {
      raise @core.ContractError(errors.join("\n"))
    }
    @host.print_out("PASS: schema, cross-file contracts, and referenced-file hashes.\n")
  } else {
    @host.print_out("PASS: schema and cross-file contracts only; image artifacts NOT verified.\n")
  }
  @host.print_out("This result is NOT visual approval, runtime approval, or execution authorization.\n")
}

///|
fn run_pixel_guard(argv : Array[String]) -> Unit raise @core.ContractError {
  let mut before : String? = None
  let mut after : String? = None
  let mut mask : String? = None
  let mut i = 0
  while i < argv.length() {
    let a = argv[i]
    if a == "--before" && i + 1 < argv.length() {
      before = Some(argv[i + 1])
      i = i + 2
    } else if a == "--after" && i + 1 < argv.length() {
      after = Some(argv[i + 1])
      i = i + 2
    } else if a == "--mask" && i + 1 < argv.length() {
      mask = Some(argv[i + 1])
      i = i + 2
    } else {
      raise @core.ContractError("Unknown argument: " + a)
    }
  }
  let before_path = match before {
    Some(p) => p
    None => raise @core.ContractError("pixel-guard requires --before")
  }
  let after_path = match after {
    Some(p) => p
    None => raise @core.ContractError("pixel-guard requires --after")
  }
  let mask_path = match mask {
    Some(p) => p
    None => raise @core.ContractError("pixel-guard requires --mask")
  }
  let diff = @core.inspect_patch(
    @host.decode_image(before_path),
    @host.decode_image(after_path),
    @host.decode_image(mask_path),
  )
  if @core.pixel_diff_allowed(diff) {
    @host.print_out("PASS: " + diff.changed_pixels.to_string() + " changed pixel(s), none outside the mask.\n")
  } else {
    raise @core.ContractError(diff.unauthorized_pixels.to_string() + " changed pixel(s) outside the authorized mask")
  }
}

///|
fn main {
  let argv = @host.cli_args()
  let rest : Array[String] = []
  for i = 0; i < argv.length(); i = i + 1 {
    if i >= 2 {
      rest.push(argv[i])
    }
  }
  try {
    if rest.length() > 0 && rest[0] == "pixel-guard" {
      run_pixel_guard(rest[1:].to_array())
    } else {
      run_validate(rest)
    }
  } catch {
    @core.ContractError(message) => {
      @host.print_err("FAIL: " + message + "\n")
      @host.exit_with(1)
    }
  }
}
