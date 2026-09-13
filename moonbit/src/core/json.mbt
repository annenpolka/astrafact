///|
struct JsonParser {
  chars : Array[Char]
  mut pos : Int
}

///|
fn JsonParser::peek(self : JsonParser) -> Char? {
  if self.pos < self.chars.length() {
    Some(self.chars[self.pos])
  } else {
    None
  }
}

///|
fn JsonParser::peek_at(self : JsonParser, offset : Int) -> Char? {
  let i = self.pos + offset
  if i >= 0 && i < self.chars.length() {
    Some(self.chars[i])
  } else {
    None
  }
}

///|
fn JsonParser::skip_ws(self : JsonParser) -> Unit {
  let mut go = true
  while go {
    match self.peek() {
      Some(c) =>
        if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
          self.pos = self.pos + 1
        } else {
          go = false
        }
      None => go = false
    }
  }
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn hex_value(c : Char) -> Int {
  if c >= '0' && c <= '9' {
    c.to_int() - '0'.to_int()
  } else if c >= 'a' && c <= 'f' {
    c.to_int() - 'a'.to_int() + 10
  } else {
    c.to_int() - 'A'.to_int() + 10
  }
}

///|
fn JsonParser::parse_hex4(self : JsonParser) -> Int raise ContractError {
  let mut value = 0
  for i = 0; i < 4; i = i + 1 {
    ignore(i)
    match self.peek() {
      Some(c) =>
        if c.is_ascii_hexdigit() {
          value = value * 16 + hex_value(c)
          self.pos = self.pos + 1
        } else {
          raise ContractError("Invalid \\u escape in JSON string")
        }
      None => raise ContractError("Unexpected end of JSON string escape")
    }
  }
  value
}

///|
fn JsonParser::parse_string(self : JsonParser) -> String raise ContractError {
  self.pos = self.pos + 1
  let out : Array[Char] = []
  let mut go = true
  while go {
    match self.peek() {
      None => raise ContractError("Unterminated JSON string")
      Some(c) =>
        if c == '"' {
          self.pos = self.pos + 1
          go = false
        } else if c == '\\' {
          self.pos = self.pos + 1
          match self.peek() {
            None => raise ContractError("Unterminated JSON escape")
            Some(e) => {
              self.pos = self.pos + 1
              if e == '"' {
                out.push('"')
              } else if e == '\\' {
                out.push('\\')
              } else if e == '/' {
                out.push('/')
              } else if e == 'b' {
                out.push('\u{0008}')
              } else if e == 'f' {
                out.push('\u{000C}')
              } else if e == 'n' {
                out.push('\n')
              } else if e == 'r' {
                out.push('\r')
              } else if e == 't' {
                out.push('\t')
              } else if e == 'u' {
                let hi = self.parse_hex4()
                if hi >= 0xD800 && hi <= 0xDBFF {
                  match (self.peek(), self.peek_at(1)) {
                    (Some('\\'), Some('u')) => {
                      self.pos = self.pos + 2
                      let lo = self.parse_hex4()
                      let combined = 0x10000 + (hi - 0xD800) * 0x400 + (lo - 0xDC00)
                      out.push(Char::from_int(combined))
                    }
                    _ => out.push(Char::from_int(hi))
                  }
                } else {
                  out.push(Char::from_int(hi))
                }
              } else {
                raise ContractError("Invalid JSON escape: \\" + e.to_string())
              }
            }
          }
        } else {
          out.push(c)
          self.pos = self.pos + 1
        }
    }
  }
  String::from_array(out)
}

///|
fn JsonParser::parse_number(self : JsonParser) -> Val raise ContractError {
  let start = self.pos
  if self.peek() == Some('-') {
    self.pos = self.pos + 1
  }
  match self.peek() {
    Some('0') => self.pos = self.pos + 1
    Some(c) =>
      if is_digit(c) {
        while is_digit(self.peek().unwrap_or('x')) {
          self.pos = self.pos + 1
        }
      } else {
        raise ContractError("Invalid JSON number")
      }
    None => raise ContractError("Unexpected end of JSON number")
  }
  let mut is_float = false
  if self.peek() == Some('.') {
    is_float = true
    self.pos = self.pos + 1
    if not(is_digit(self.peek().unwrap_or('x'))) {
      raise ContractError("Invalid JSON number fraction")
    }
    while is_digit(self.peek().unwrap_or('x')) {
      self.pos = self.pos + 1
    }
  }
  match self.peek() {
    Some('e') | Some('E') => {
      is_float = true
      self.pos = self.pos + 1
      match self.peek() {
        Some('+') | Some('-') => self.pos = self.pos + 1
        _ => ()
      }
      if not(is_digit(self.peek().unwrap_or('x'))) {
        raise ContractError("Invalid JSON number exponent")
      }
      while is_digit(self.peek().unwrap_or('x')) {
        self.pos = self.pos + 1
      }
    }
    _ => ()
  }
  let text = String::from_array(self.chars[start:self.pos])
  if is_float {
    try {
      VNum(@strconv.parse_double(text))
    } catch {
      _ => raise ContractError("Invalid JSON number: " + text)
    }
  } else {
    try {
      VInt(@strconv.parse_int(text))
    } catch {
      _ => raise ContractError("Invalid JSON integer: " + text)
    }
  }
}

///|
fn JsonParser::parse_array(self : JsonParser) -> Val raise ContractError {
  self.pos = self.pos + 1
  let items : Array[Val] = []
  self.skip_ws()
  if self.peek() == Some(']') {
    self.pos = self.pos + 1
    return VArr(items)
  }
  let mut go = true
  while go {
    let value = self.parse_value()
    items.push(value)
    self.skip_ws()
    match self.peek() {
      Some(',') => {
        self.pos = self.pos + 1
        self.skip_ws()
      }
      Some(']') => {
        self.pos = self.pos + 1
        go = false
      }
      _ => raise ContractError("Expected ',' or ']' in JSON array")
    }
  }
  VArr(items)
}

///|
fn JsonParser::parse_object(self : JsonParser) -> Val raise ContractError {
  self.pos = self.pos + 1
  let entries : Array[(String, Val)] = []
  self.skip_ws()
  if self.peek() == Some('}') {
    self.pos = self.pos + 1
    return VObj(entries)
  }
  let mut go = true
  while go {
    self.skip_ws()
    if self.peek() != Some('"') {
      raise ContractError("JSON object keys must be strings")
    }
    let key = self.parse_string()
    for entry in entries {
      if entry.0 == key {
        raise ContractError("Duplicate JSON key: " + key)
      }
    }
    self.skip_ws()
    if self.peek() != Some(':') {
      raise ContractError("Expected ':' after JSON object key")
    }
    self.pos = self.pos + 1
    let value = self.parse_value()
    entries.push((key, value))
    self.skip_ws()
    match self.peek() {
      Some(',') => {
        self.pos = self.pos + 1
      }
      Some('}') => {
        self.pos = self.pos + 1
        go = false
      }
      _ => raise ContractError("Expected ',' or '}' in JSON object")
    }
  }
  VObj(entries)
}

///|
fn JsonParser::parse_value(self : JsonParser) -> Val raise ContractError {
  self.skip_ws()
  match self.peek() {
    None => raise ContractError("Unexpected end of JSON input")
    Some(c) =>
      if c == '"' {
        VStr(self.parse_string())
      } else if c == '{' {
        self.parse_object()
      } else if c == '[' {
        self.parse_array()
      } else if c == 't' {
        self.expect_literal("true")
        VBool(true)
      } else if c == 'f' {
        self.expect_literal("false")
        VBool(false)
      } else if c == 'n' {
        self.expect_literal("null")
        VNull
      } else if c == 'N' {
        raise ContractError("Non-finite JSON constant: NaN")
      } else if c == 'I' {
        raise ContractError("Non-finite JSON constant: Infinity")
      } else if c == '-' {
        if self.peek_at(1) == Some('I') {
          raise ContractError("Non-finite JSON constant: -Infinity")
        }
        self.parse_number()
      } else if is_digit(c) {
        self.parse_number()
      } else {
        raise ContractError("Unexpected character in JSON: " + c.to_string())
      }
  }
}

///|
fn JsonParser::expect_literal(self : JsonParser, word : String) -> Unit raise ContractError {
  for c in word {
    if self.peek() != Some(c) {
      raise ContractError("Invalid JSON literal, expected " + word)
    }
    self.pos = self.pos + 1
  }
}

///|
/// Parse strict JSON. Rejects duplicate object keys and the non-finite
/// constants `NaN`, `Infinity` and `-Infinity`.
pub fn parse_json(text : String) -> Val raise ContractError {
  let parser : JsonParser = { chars: text.to_array(), pos: 0 }
  let value = parser.parse_value()
  parser.skip_ws()
  if parser.pos != parser.chars.length() {
    raise ContractError("Trailing content after JSON document")
  }
  value
}
