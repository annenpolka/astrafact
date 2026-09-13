///|
/// Non-JS targets have no platform adapter. These stubs keep `moon check` and
/// pure-core tests building on wasm/wasm-gc/native; any attempt to use the
/// platform there aborts with a clear message.

///|
fn unavailable() -> Unit {
  abort("The Node platform adapter is only available for the js target")
}

///|
pub fn platform_read_text(path : String) -> String? {
  ignore(path)
  unavailable()
  None
}

///|
pub fn platform_read_bytes(path : String) -> Bytes? {
  ignore(path)
  unavailable()
  None
}

///|
pub fn platform_sha256_hex(data : Bytes) -> String {
  ignore(data)
  unavailable()
  ""
}

///|
pub fn platform_is_file(path : String) -> Bool {
  ignore(path)
  unavailable()
  false
}

///|
pub fn platform_realpath(path : String) -> String {
  ignore(path)
  unavailable()
  ""
}

///|
pub fn platform_is_within(child : String, root : String) -> Bool {
  ignore(child)
  ignore(root)
  unavailable()
  false
}

///|
pub fn platform_join(a : String, b : String) -> String {
  ignore(a)
  ignore(b)
  unavailable()
  ""
}

///|
pub fn platform_parse_yaml(text : String) -> String? {
  ignore(text)
  unavailable()
  None
}

///|
pub fn platform_write_text(path : String, text : String) -> Bool {
  ignore(path)
  ignore(text)
  unavailable()
  false
}

///|
pub fn platform_tmpdir() -> String {
  unavailable()
  ""
}

///|
pub fn platform_mkdir(path : String) -> Bool {
  ignore(path)
  unavailable()
  false
}

///|
pub fn platform_symlink(target : String, link : String) -> Bool {
  ignore(target)
  ignore(link)
  unavailable()
  false
}

///|
pub fn platform_decode_png(path : String) -> Bytes? {
  ignore(path)
  unavailable()
  None
}

///|
pub fn platform_encode_png(path : String, width : Int, height : Int, channels : Int, data : Bytes) -> Bool {
  ignore(path)
  ignore(width)
  ignore(height)
  ignore(channels)
  ignore(data)
  unavailable()
  false
}

///|
pub fn platform_get_args() -> Array[String] {
  unavailable()
  []
}

///|
pub fn platform_cwd() -> String {
  unavailable()
  ""
}

///|
pub fn platform_print_stdout(text : String) -> Unit {
  ignore(text)
  unavailable()
}

///|
pub fn platform_print_stderr(text : String) -> Unit {
  ignore(text)
  unavailable()
}

///|
pub fn platform_exit(code : Int) -> Unit {
  ignore(code)
  unavailable()
}
