///|
fn rgba(w : Int, h : Int) -> Array[Int] {
  let a : Array[Int] = []
  for i = 0; i < w * h * 4; i = i + 1 {
    a.push(0)
  }
  a
}

///|
fn mk_image(w : Int, h : Int, channels : Int, vals : Array[Int]) -> ImageData {
  {
    width: w,
    height: h,
    channels,
    data: Bytes::from_array(vals.map(fn(v) { v.to_byte() })),
  }
}

///|
fn set_px(vals : Array[Int], w : Int, x : Int, y : Int, r : Int, g : Int, b : Int, a : Int) -> Unit {
  let i = (y * w + x) * 4
  vals[i] = r
  vals[i + 1] = g
  vals[i + 2] = b
  vals[i + 3] = a
}

// ---- JSON ------------------------------------------------------------------

///|
test "json parses objects and arrays" {
  let v = parse_json("{\"a\": 1, \"b\": [true, null, \"x\"]}")
  let o = as_obj(v)
  inspect(f_int(o, "a"), content="1")
  inspect(as_arr(vobj_get_required(o, "b")).length(), content="3")
}

///|
test "json rejects duplicate keys" {
  let mut raised = false
  try {
    let _ = parse_json("{\"a\": 1, \"a\": 2}")
  } catch {
    _ => raised = true
  }
  assert_true(raised)
}

///|
test "json rejects non-finite constants" {
  for text in ["NaN", "Infinity", "-Infinity"] {
    let mut raised = false
    try {
      let _ = parse_json(text)
    } catch {
      _ => raised = true
    }
    assert_true(raised)
  }
}

///|
test "json round trips unicode" {
  let v = parse_json("\"\\u9244\\u6b4c\"")
  inspect(as_str(v), content="鉄歌")
}

// ---- regex -----------------------------------------------------------------

///|
test "regex anchors and classes" {
  assert_true(regex_search("^[a-z][a-z0-9_.-]*$", "knight_001"))
  assert_false(regex_search("^[a-z][a-z0-9_.-]*$", "Knight"))
  assert_true(regex_search("^#[0-9A-F]{6}$", "#171923"))
  assert_false(regex_search("^#[0-9A-F]{6}$", "#17192g"))
  assert_true(regex_search("^[0-9a-f]{64}$", "0".repeat(64)))
  assert_true(regex_search("^/", "/scope/frames"))
  assert_false(regex_search("^/", "scope"))
}

// ---- schema ----------------------------------------------------------------

///|
test "schema type and bounds" {
  let schema = parse_json("{\"type\": \"integer\", \"minimum\": 1, \"maximum\": 10}")
  validate_document_schema(schema, VInt(5))
  let mut raised = false
  try {
    validate_document_schema(schema, VInt(0))
  } catch {
    _ => raised = true
  }
  assert_true(raised)
}

///|
test "schema additionalProperties false" {
  let schema = parse_json("{\"type\":\"object\",\"additionalProperties\":false,\"properties\":{\"a\":{\"type\":\"integer\"}}}")
  validate_document_schema(schema, parse_json("{\"a\":1}"))
  let mut raised = false
  try {
    validate_document_schema(schema, parse_json("{\"a\":1,\"b\":2}"))
  } catch {
    _ => raised = true
  }
  assert_true(raised)
}

///|
test "schema anyOf with null" {
  let schema = parse_json("{\"anyOf\":[{\"type\":\"integer\"},{\"type\":\"null\"}]}")
  validate_document_schema(schema, VInt(3))
  validate_document_schema(schema, VNull)
}

///|
test "schema ref resolution" {
  let schema = parse_json("{\"$defs\":{\"id\":{\"type\":\"string\",\"pattern\":\"^[a-z]+$\"}},\"$ref\":\"#/$defs/id\"}")
  validate_document_schema(schema, VStr("abc"))
  let mut raised = false
  try {
    validate_document_schema(schema, VStr("ABC"))
  } catch {
    _ => raised = true
  }
  assert_true(raised)
}

///|
test "unknown schema keyword fails closed" {
  let mut raised = false
  try {
    validate_document_schema(parse_json("{\"allOf\":[]}"), VInt(1))
  } catch {
    _ => raised = true
  }
  assert_true(raised)
}

// ---- pixel -----------------------------------------------------------------

///|
test "pixel no changes" {
  let before = mk_image(4, 4, 4, rgba(4, 4))
  let after = mk_image(4, 4, 4, rgba(4, 4))
  let mask = mk_image(4, 4, 1, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
  let d = inspect_patch(before, after, mask)
  inspect(d.changed_pixels, content="0")
  assert_true(pixel_diff_allowed(d))
}

///|
test "pixel authorized change" {
  let before = mk_image(4, 4, 4, rgba(4, 4))
  let av = rgba(4, 4)
  set_px(av, 4, 1, 1, 255, 255, 255, 255)
  let after = mk_image(4, 4, 4, av)
  let mv = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  mv[1 * 4 + 1] = 255
  let mask = mk_image(4, 4, 1, mv)
  assert_true(pixel_diff_allowed(inspect_patch(before, after, mask)))
}

///|
test "pixel unauthorized change" {
  let before = mk_image(4, 4, 4, rgba(4, 4))
  let av = rgba(4, 4)
  set_px(av, 4, 1, 1, 255, 255, 255, 255)
  let after = mk_image(4, 4, 4, av)
  let mask = mk_image(4, 4, 1, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
  let d = inspect_patch(before, after, mask)
  assert_false(pixel_diff_allowed(d))
  inspect(d.unauthorized_pixels, content="1")
}

///|
test "pixel transparent rgb normalized" {
  let before = mk_image(4, 4, 4, rgba(4, 4))
  let av = rgba(4, 4)
  set_px(av, 4, 1, 1, 255, 100, 100, 0)
  let after = mk_image(4, 4, 4, av)
  let mask = mk_image(4, 4, 1, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
  inspect(inspect_patch(before, after, mask).changed_pixels, content="0")
}

///|
test "pixel soft mask rejected" {
  let before = mk_image(4, 4, 4, rgba(4, 4))
  let after = mk_image(4, 4, 4, rgba(4, 4))
  let mv = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  mv[5] = 128
  let mask = mk_image(4, 4, 1, mv)
  let mut raised = false
  try {
    let _ = inspect_patch(before, after, mask)
  } catch {
    _ => raised = true
  }
  assert_true(raised)
}

///|
test "pixel size mismatch rejected" {
  let before = mk_image(4, 4, 4, rgba(4, 4))
  let after = mk_image(8, 8, 4, rgba(8, 8))
  let mask = mk_image(4, 4, 1, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
  let mut raised = false
  try {
    let _ = inspect_patch(before, after, mask)
  } catch {
    _ => raised = true
  }
  assert_true(raised)
}

///|
test "pixel rgb mask rejected" {
  let before = mk_image(4, 4, 4, rgba(4, 4))
  let after = mk_image(4, 4, 4, rgba(4, 4))
  let mask = mk_image(4, 4, 3, rgba(4, 4))
  let mut raised = false
  try {
    let _ = inspect_patch(before, after, mask)
  } catch {
    _ => raised = true
  }
  assert_true(raised)
}
