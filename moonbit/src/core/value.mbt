///|
/// Contract violations raised by parsing, schema validation and cross-file
/// checks. This mirrors the behaviour (not the class identity) of the Python
/// `ContractError` oracle.
pub(all) suberror ContractError {
  ContractError(String)
}

///|
/// A minimal JSON value model. Objects keep insertion order so that ordered
/// array comparisons behave like Python lists of dicts. Duplicate keys are
/// rejected during parsing, so an array of pairs is unambiguous.
pub(all) enum Val {
  VNull
  VBool(Bool)
  VInt(Int)
  VNum(Double)
  VStr(String)
  VArr(Array[Val])
  VObj(Array[(String, Val)])
}

///|
pub fn vtype(v : Val) -> String {
  match v {
    VNull => "null"
    VBool(_) => "boolean"
    VInt(_) => "integer"
    VNum(_) => "number"
    VStr(_) => "string"
    VArr(_) => "array"
    VObj(_) => "object"
  }
}

///|
pub fn vshow(v : Val) -> String {
  match v {
    VNull => "null"
    VBool(b) => if b { "true" } else { "false" }
    VInt(i) => i.to_string()
    VNum(d) => d.to_string()
    VStr(s) => "\"" + s + "\""
    VArr(a) => "[" + a.map(fn(x) { vshow(x) }).join(",") + "]"
    VObj(o) => {
      let sb = StringBuilder::new()
      sb.write_string("{")
      for i, entry in o {
        if i > 0 {
          sb.write_string(",")
        }
        sb.write_string(entry.0)
        sb.write_string(":")
        sb.write_string(vshow(entry.1))
      }
      sb.write_string("}")
      sb.to_string()
    }
  }
}

///|
pub fn vobj_get(obj : Array[(String, Val)], key : String) -> Val? {
  let mut found : Val? = None
  for entry in obj {
    if entry.0 == key {
      found = Some(entry.1)
    }
  }
  found
}

///|
pub fn vobj_has(obj : Array[(String, Val)], key : String) -> Bool {
  match vobj_get(obj, key) {
    Some(_) => true
    None => false
  }
}

///|
pub fn vobj_get_required(obj : Array[(String, Val)], key : String) -> Val raise ContractError {
  match vobj_get(obj, key) {
    Some(v) => v
    None => raise ContractError("Missing object field: " + key)
  }
}

///|
pub fn as_obj(v : Val) -> Array[(String, Val)] raise ContractError {
  match v {
    VObj(o) => o
    _ => raise ContractError("Expected object, got " + vtype(v))
  }
}

///|
pub fn as_arr(v : Val) -> Array[Val] raise ContractError {
  match v {
    VArr(a) => a
    _ => raise ContractError("Expected array, got " + vtype(v))
  }
}

///|
pub fn as_str(v : Val) -> String raise ContractError {
  match v {
    VStr(s) => s
    _ => raise ContractError("Expected string, got " + vtype(v))
  }
}

///|
pub fn as_int(v : Val) -> Int raise ContractError {
  match v {
    VInt(i) => i
    _ => raise ContractError("Expected integer, got " + vtype(v))
  }
}

///|
pub fn as_bool(v : Val) -> Bool raise ContractError {
  match v {
    VBool(b) => b
    _ => raise ContractError("Expected boolean, got " + vtype(v))
  }
}

///|
pub fn is_null(v : Val) -> Bool {
  match v {
    VNull => true
    _ => false
  }
}

///|
pub fn is_int(v : Val) -> Bool {
  match v {
    VInt(_) => true
    _ => false
  }
}

///|
/// Deep equality. Object comparison is key-based and order-insensitive, like
/// Python dict equality.
pub fn veq(a : Val, b : Val) -> Bool {
  match (a, b) {
    (VNull, VNull) => true
    (VBool(x), VBool(y)) => x == y
    (VInt(x), VInt(y)) => x == y
    (VInt(x), VNum(y)) => x.to_double() == y
    (VNum(x), VInt(y)) => x == y.to_double()
    (VNum(x), VNum(y)) => x == y
    (VStr(x), VStr(y)) => x == y
    (VArr(x), VArr(y)) => {
      if x.length() != y.length() {
        false
      } else {
        let mut same = true
        for i = 0; i < x.length(); i = i + 1 {
          if not(veq(x[i], y[i])) {
            same = false
          }
        }
        same
      }
    }
    (VObj(x), VObj(y)) => {
      if x.length() != y.length() {
        false
      } else {
        let mut same = true
        for entry in x {
          match vobj_get(y, entry.0) {
            Some(vy) => if not(veq(entry.1, vy)) { same = false }
            None => same = false
          }
        }
        same
      }
    }
    _ => false
  }
}

///|
pub fn vint(i : Int) -> Val {
  VInt(i)
}

///|
pub fn vstr(s : String) -> Val {
  VStr(s)
}

///|
pub fn varr(items : Array[Val]) -> Val {
  VArr(items)
}

///|
pub fn vobj(entries : Array[(String, Val)]) -> Val {
  VObj(entries)
}
