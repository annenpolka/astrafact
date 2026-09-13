///|
/// Node-backed host layer. Wires the pure core to the JS platform adapter and
/// exposes decoded images and the CLI building blocks.

///|
pub fn real_fs() -> @core.Fs {
  {
    read_text: fn(path) -> String raise @core.ContractError {
      match @platform.platform_read_text(path) {
        Some(text) => text
        None => raise @core.ContractError("Missing artifact: " + path)
      }
    },
    read_bytes: fn(path) -> Bytes raise @core.ContractError {
      match @platform.platform_read_bytes(path) {
        Some(data) => data
        None => raise @core.ContractError("Missing artifact: " + path)
      }
    },
    sha256_hex: fn(data) { @platform.platform_sha256_hex(data) },
    is_file: fn(path) { @platform.platform_is_file(path) },
    realpath: fn(path) { @platform.platform_realpath(path) },
    is_within: fn(child, root) { @platform.platform_is_within(child, root) },
    join: fn(a, b) { @platform.platform_join(a, b) },
    parse_yaml: fn(text) -> String raise @core.ContractError {
      match @platform.platform_parse_yaml(text) {
        Some(json) => json
        None => raise @core.ContractError("Invalid YAML document")
      }
    },
  }
}

///|
pub fn load_schemas(fs : @core.Fs, kit_root : String) -> @core.Schemas raise @core.ContractError {
  let read = fn(name) -> String raise @core.ContractError {
    (fs.read_text)((fs.join)(kit_root, "schemas/" + name))
  }
  @core.schemas_from_json(
    read("asset.schema.json"),
    read("motion.schema.json"),
    read("review-pack.schema.json"),
    read("review.schema.json"),
    read("repair-plan.schema.json"),
  )
}

///|
fn be32(data : Bytes, offset : Int) -> Int {
  data[offset].to_int() * 16777216 + data[offset + 1].to_int() * 65536 + data[offset + 2].to_int() * 256 + data[offset + 3].to_int()
}

///|
/// Decode a PNG through the platform adapter into raw pixels. The adapter
/// returns `[width][height][channels][reserved]` big-endian followed by the
/// interleaved pixel bytes.
pub fn decode_image(path : String) -> @core.ImageData raise @core.ContractError {
  match @platform.platform_decode_png(path) {
    Some(packed) => {
      let width = be32(packed, 0)
      let height = be32(packed, 4)
      let channels = be32(packed, 8)
      let payload = match packed.get_view(start=16, end=packed.length()) {
        Some(view) => Bytes::from_array(view.to_array())
        None => Bytes::new(0)
      }
      { width, height, channels, data: payload }
    }
    None => raise @core.ContractError("Cannot decode image: " + path)
  }
}

///|
pub fn encode_test_png(
  path : String,
  width : Int,
  height : Int,
  channels : Int,
  data : Bytes,
) -> Bool {
  @platform.platform_encode_png(path, width, height, channels, data)
}

///|
pub fn cli_args() -> Array[String] {
  @platform.platform_get_args()
}

///|
pub fn write_text(path : String, text : String) -> Bool {
  @platform.platform_write_text(path, text)
}

///|
pub fn tmpdir() -> String {
  @platform.platform_tmpdir()
}

///|
pub fn mkdir(path : String) -> Bool {
  @platform.platform_mkdir(path)
}

///|
pub fn symlink(target : String, link : String) -> Bool {
  @platform.platform_symlink(target, link)
}

///|
pub fn cwd() -> String {
  @platform.platform_cwd()
}

///|
pub fn print_out(text : String) -> Unit {
  @platform.platform_print_stdout(text)
}

///|
pub fn print_err(text : String) -> Unit {
  @platform.platform_print_stderr(text)
}

///|
pub fn exit_with(code : Int) -> Unit {
  @platform.platform_exit(code)
}

///|
/// Resolve the repository root the same way the Python tool defaults to its
/// package parent: prefer the current directory when it directly contains the
/// schemas, otherwise its parent (the MoonBit module lives in `moonbit/`).
pub fn default_root() -> String {
  let fs = real_fs()
  let here = cwd()
  if (fs.is_file)((fs.join)(here, "schemas/asset.schema.json")) {
    here
  } else {
    (fs.realpath)((fs.join)(here, ".."))
  }
}
