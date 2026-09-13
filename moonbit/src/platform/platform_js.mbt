///|
/// JavaScript/Node platform boundary. Each declaration delegates to the
/// adapter registered on `globalThis.__astrafact` by `js/adapter.cjs`. Only
/// filesystem, realpath/containment, SHA-256, YAML loading and PNG codec work
/// happens here; no contract judgement is delegated.
pub extern "js" fn platform_read_text(path : String) -> String? =
  #| function(p) { return globalThis.__astrafact.readText(p); }

///|
pub extern "js" fn platform_read_bytes(path : String) -> Bytes? =
  #| function(p) { return globalThis.__astrafact.readBytes(p); }

///|
pub extern "js" fn platform_sha256_hex(data : Bytes) -> String =
  #| function(d) { return globalThis.__astrafact.sha256Hex(d); }

///|
pub extern "js" fn platform_is_file(path : String) -> Bool =
  #| function(p) { return globalThis.__astrafact.isFile(p); }

///|
pub extern "js" fn platform_realpath(path : String) -> String =
  #| function(p) { return globalThis.__astrafact.realpath(p); }

///|
pub extern "js" fn platform_is_within(child : String, root : String) -> Bool =
  #| function(c, r) { return globalThis.__astrafact.isWithin(c, r); }

///|
pub extern "js" fn platform_join(a : String, b : String) -> String =
  #| function(a, b) { return globalThis.__astrafact.join(a, b); }

///|
pub extern "js" fn platform_parse_yaml(text : String) -> String? =
  #| function(t) { return globalThis.__astrafact.parseYaml(t); }

///|
pub extern "js" fn platform_write_text(path : String, text : String) -> Bool =
  #| function(p, t) { return globalThis.__astrafact.writeText(p, t); }

///|
pub extern "js" fn platform_tmpdir() -> String =
  #| function() { return globalThis.__astrafact.tmpdir(); }

///|
pub extern "js" fn platform_mkdir(path : String) -> Bool =
  #| function(p) { return globalThis.__astrafact.mkdir(p); }

///|
pub extern "js" fn platform_symlink(target : String, link : String) -> Bool =
  #| function(t, l) { return globalThis.__astrafact.symlink(t, l); }

///|
pub extern "js" fn platform_decode_png(path : String) -> Bytes? =
  #| function(p) { return globalThis.__astrafact.decodePng(p); }

///|
pub extern "js" fn platform_encode_png(path : String, width : Int, height : Int, channels : Int, data : Bytes) -> Bool =
  #| function(p, w, h, c, d) { return globalThis.__astrafact.encodePng(p, w, h, c, d); }

///|
pub extern "js" fn platform_get_args() -> Array[String] =
  #| function() { return globalThis.__astrafact.getArgs(); }

///|
pub extern "js" fn platform_cwd() -> String =
  #| function() { return globalThis.__astrafact.cwd(); }

///|
pub extern "js" fn platform_print_stdout(text : String) -> Unit =
  #| function(t) { globalThis.__astrafact.printStdout(t); }

///|
pub extern "js" fn platform_print_stderr(text : String) -> Unit =
  #| function(t) { globalThis.__astrafact.printStderr(t); }

///|
pub extern "js" fn platform_exit(code : Int) -> Unit =
  #| function(c) { globalThis.__astrafact.exit(c); }
