///|
/// The only JSON Schema keywords this validator implements. Anything else is
/// rejected before evaluation so that an unsupported assertion can never be
/// silently accepted ("fail closed").
fn recognized_keyword(k : String) -> Bool {
  match k {
    "$schema"
    | "$id"
    | "title"
    | "description"
    | "$defs"
    | "$ref"
    | "type"
    | "properties"
    | "additionalProperties"
    | "required"
    | "const"
    | "enum"
    | "items"
    | "minItems"
    | "maxItems"
    | "uniqueItems"
    | "minLength"
    | "maxLength"
    | "pattern"
    | "minimum"
    | "maximum"
    | "anyOf" => true
    _ => false
  }
}

///|
fn lint_schema(schema : Val) -> Unit raise ContractError {
  match schema {
    VBool(_) => ()
    VObj(o) => {
      for entry in o {
        let key = entry.0
        if not(recognized_keyword(key)) {
          raise ContractError("Unsupported schema keyword: " + key)
        }
        if key == "properties" || key == "$defs" {
          for sub in as_obj(entry.1) {
            lint_schema(sub.1)
          }
        } else if key == "items" {
          lint_schema(entry.1)
        } else if key == "anyOf" {
          for sub in as_arr(entry.1) {
            lint_schema(sub)
          }
        } else if key == "additionalProperties" {
          match entry.1 {
            VObj(_) => lint_schema(entry.1)
            _ => ()
          }
        }
      }
    }
    _ => raise ContractError("Schema node must be an object or boolean")
  }
}

///|
fn type_matches(t : String, data : Val) -> Bool {
  match t {
    "object" => match data { VObj(_) => true; _ => false }
    "array" => match data { VArr(_) => true; _ => false }
    "string" => match data { VStr(_) => true; _ => false }
    "integer" => match data { VInt(_) => true; _ => false }
    "number" => match data { VInt(_) | VNum(_) => true; _ => false }
    "boolean" => match data { VBool(_) => true; _ => false }
    "null" => match data { VNull => true; _ => false }
    _ => false
  }
}

///|
fn resolve_ref(root : Val, ref : String) -> Val raise ContractError {
  let parts : Array[String] = []
  for part in ref.split("/") {
    parts.push(part.to_string())
  }
  if parts.length() == 0 || parts[0] != "#" {
    raise ContractError("Only local $ref pointers are supported: " + ref)
  }
  let mut current = root
  for i = 1; i < parts.length(); i = i + 1 {
    let key = parts[i]
    if key == "" {
      continue
    }
    current = vobj_get_required(as_obj(current), key)
  }
  current
}

///|
fn is_valid(root : Val, schema : Val, data : Val) -> Bool {
  let mut ok = true
  try {
    validate_at(root, schema, data)
  } catch {
    _ => ok = false
  }
  ok
}

///|
fn check_enum(values : Array[Val], data : Val) -> Bool {
  let mut found = false
  for v in values {
    if veq(v, data) {
      found = true
    }
  }
  found
}

///|
fn all_unique(values : Array[Val]) -> Bool {
  let mut unique = true
  for i = 0; i < values.length(); i = i + 1 {
    for j = i + 1; j < values.length(); j = j + 1 {
      if veq(values[i], values[j]) {
        unique = false
      }
    }
  }
  unique
}

///|
fn numeric_le(a : Val, b : Val) -> Bool raise ContractError {
  match (a, b) {
    (VInt(x), VInt(y)) => x <= y
    (VInt(x), VNum(y)) => x.to_double() <= y
    (VNum(x), VInt(y)) => x <= y.to_double()
    (VNum(x), VNum(y)) => x <= y
    _ => raise ContractError("Numeric bound comparison on non-number")
  }
}

///|
fn numeric_ge(a : Val, b : Val) -> Bool raise ContractError {
  match (a, b) {
    (VInt(x), VInt(y)) => x >= y
    (VInt(x), VNum(y)) => x.to_double() >= y
    (VNum(x), VInt(y)) => x >= y.to_double()
    (VNum(x), VNum(y)) => x >= y
    _ => raise ContractError("Numeric bound comparison on non-number")
  }
}

///|
fn is_number(v : Val) -> Bool {
  match v {
    VInt(_) | VNum(_) => true
    _ => false
  }
}

///|
fn validate_at(root : Val, schema : Val, data : Val) -> Unit raise ContractError {
  match schema {
    VBool(ok) => if ok { () } else { raise ContractError("Schema `false` rejects all values") }
    VObj(o) => {
      match vobj_get(o, "$ref") {
        Some(refv) => {
          let target = resolve_ref(root, as_str(refv))
          validate_at(root, target, data)
        }
        None => ()
      }
      match vobj_get(o, "$defs") {
        Some(_) => ()
        None => ()
      }
      match vobj_get(o, "type") {
        Some(tv) =>
          if not(type_matches(as_str(tv), data)) {
            raise ContractError("Expected type " + as_str(tv) + ", got " + vtype(data))
          }
        None => ()
      }
      match vobj_get(o, "const") {
        Some(cv) =>
          if not(veq(cv, data)) {
            raise ContractError("Value does not match const")
          }
        None => ()
      }
      match vobj_get(o, "enum") {
        Some(ev) =>
          if not(check_enum(as_arr(ev), data)) {
            raise ContractError("Value is not one of the allowed enum values")
          }
        None => ()
      }
      match vobj_get(o, "pattern") {
        Some(pv) =>
          match data {
            VStr(s) =>
              if not(regex_search(as_str(pv), s)) {
                raise ContractError("String does not match pattern " + as_str(pv))
              }
            _ => ()
          }
        None => ()
      }
      match vobj_get(o, "minLength") {
        Some(mv) =>
          match data {
            VStr(s) =>
              if s.char_length() < as_int(mv) {
                raise ContractError("String shorter than minLength")
              }
            _ => ()
          }
        None => ()
      }
      match vobj_get(o, "maxLength") {
        Some(mv) =>
          match data {
            VStr(s) =>
              if s.char_length() > as_int(mv) {
                raise ContractError("String longer than maxLength")
              }
            _ => ()
          }
        None => ()
      }
      match vobj_get(o, "minimum") {
        Some(mv) =>
          if is_number(data) && not(numeric_ge(data, mv)) {
            raise ContractError("Number below minimum")
          }
        None => ()
      }
      match vobj_get(o, "maximum") {
        Some(mv) =>
          if is_number(data) && not(numeric_le(data, mv)) {
            raise ContractError("Number above maximum")
          }
        None => ()
      }
      match vobj_get(o, "minItems") {
        Some(mv) =>
          match data {
            VArr(a) =>
              if a.length() < as_int(mv) {
                raise ContractError("Array shorter than minItems")
              }
            _ => ()
          }
        None => ()
      }
      match vobj_get(o, "maxItems") {
        Some(mv) =>
          match data {
            VArr(a) =>
              if a.length() > as_int(mv) {
                raise ContractError("Array longer than maxItems")
              }
            _ => ()
          }
        None => ()
      }
      match vobj_get(o, "uniqueItems") {
        Some(uv) =>
          match data {
            VArr(a) =>
              if as_bool(uv) && not(all_unique(a)) {
                raise ContractError("Array items are not unique")
              }
            _ => ()
          }
        None => ()
      }
      match vobj_get(o, "items") {
        Some(sv) =>
          match data {
            VArr(a) =>
              for item in a {
                validate_at(root, sv, item)
              }
            _ => ()
          }
        None => ()
      }
      match vobj_get(o, "anyOf") {
        Some(av) => {
          let options = as_arr(av)
          let mut ok = false
          for option in options {
            if is_valid(root, option, data) {
              ok = true
            }
          }
          if not(ok) {
            raise ContractError("Value does not match anyOf")
          }
        }
        None => ()
      }
      match data {
        VObj(dobj) => {
          let properties = match vobj_get(o, "properties") {
            Some(pv) => as_obj(pv)
            None => ([] : Array[(String, Val)])
          }
          match vobj_get(o, "required") {
            Some(rv) =>
              for r in as_arr(rv) {
                let key = as_str(r)
                if not(vobj_has(dobj, key)) {
                  raise ContractError("Missing required property: " + key)
                }
              }
            None => ()
          }
          for entry in dobj {
            match vobj_get(properties, entry.0) {
              Some(ps) => validate_at(root, ps, entry.1)
              None => ()
            }
          }
          match vobj_get(o, "additionalProperties") {
            Some(ap) =>
              match ap {
                VBool(false) =>
                  for entry in dobj {
                    if not(vobj_has(properties, entry.0)) {
                      raise ContractError("Additional property not allowed: " + entry.0)
                    }
                  }
                VBool(true) => ()
                VObj(_) =>
                  for entry in dobj {
                    if not(vobj_has(properties, entry.0)) {
                      validate_at(root, ap, entry.1)
                    }
                  }
                _ => ()
              }
            None => ()
          }
        }
        _ => ()
      }
    }
    _ => raise ContractError("Schema node must be an object or boolean")
  }
}

///|
/// Validate a document against an already-parsed schema value.
pub fn validate_document_schema(schema : Val, data : Val) -> Unit raise ContractError {
  lint_schema(schema)
  validate_at(schema, schema, data)
}
