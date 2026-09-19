///|
fn datum_schema(text : StringView) -> @moonavro.SchemaDocument {
  match @moonavro.parse_schema(text) {
    Ok(value) => value
    Err(_) => abort("datum schema failed")
  }
}

///|
test "convert primitive JSON datums" {
  let cases = [
    ("\"null\"", "null", @moonavro.NullValue),
    ("\"boolean\"", "true", @moonavro.BooleanValue(true)),
    ("\"int\"", "-7", @moonavro.IntValue(-7)),
    ("\"long\"", "9001", @moonavro.LongValue(9001L)),
    ("\"string\"", "\"MoonBit\"", @moonavro.StringValue("MoonBit")),
  ]
  for (schema_text, json_text, expected) in cases {
    let schema = datum_schema(schema_text)
    assert_eq(@moonavro.value_from_json(schema, json_text), Ok(expected))
    guard @moonavro.value_to_json_string(schema, expected) is Ok(rendered) else {
      fail("value json render failed")
    }
    assert_eq(@moonavro.value_from_json(schema, rendered), Ok(expected))
  }
}

///|
test "convert record arrays maps enums and unions" {
  let schema = datum_schema(
    (
      #|{"type":"record","name":"Message","fields":[
      #| {"name":"id","type":"long"},
      #| {"name":"tags","type":{"type":"array","items":"string"}},
      #| {"name":"headers","type":{"type":"map","values":"string"}},
      #| {"name":"status","type":{"type":"enum","name":"Status","symbols":["NEW","SENT"]}},
      #| {"name":"note","type":["null","string"]}
      #|]}
    ),
  )
  let json =
    #|{"id":5,"tags":["avro","moonbit"],"headers":{"source":"test"},"status":"NEW","note":{"string":"hello"}}
  let parsed = @moonavro.value_from_json(schema, json)
  guard parsed is Ok(value) else { fail("compound datum parse failed") }
  guard value is @moonavro.RecordValue(fields) else { fail("record expected") }
  assert_eq(fields.length(), 5)
  assert_eq(fields[0], ("id", @moonavro.LongValue(5L)))
  assert_eq(
    fields[4],
    ("note", @moonavro.UnionValue(1, @moonavro.StringValue("hello"))),
  )
  let rendered = @moonavro.value_to_json_string(schema, value, pretty=true)
  guard rendered is Ok(text) else { fail("compound datum render failed") }
  assert_eq(@moonavro.value_from_json(schema, text), Ok(value))
}

///|
test "null union uses bare json null" {
  let schema = datum_schema("[\"null\",\"string\"]")
  assert_eq(
    @moonavro.value_from_json(schema, "null"),
    Ok(@moonavro.UnionValue(0, @moonavro.NullValue)),
  )
  assert_eq(
    @moonavro.value_to_json_string(
      schema,
      @moonavro.UnionValue(0, @moonavro.NullValue),
    ),
    Ok("null"),
  )
}

///|
test "record JSON applies schema default" {
  let schema = datum_schema(
    (
      #|{"type":"record","name":"Config","fields":[
      #| {"name":"name","type":"string"},
      #| {"name":"enabled","type":"boolean","default":true}
      #|]}
    ),
  )
  assert_eq(
    @moonavro.value_from_json(schema, "{\"name\":\"demo\"}"),
    Ok(
      @moonavro.RecordValue([
        ("name", @moonavro.StringValue("demo")),
        ("enabled", @moonavro.BooleanValue(true)),
      ]),
    ),
  )
}

///|
test "reject missing record field" {
  let schema = datum_schema(
    (
      #|{"type":"record","name":"User","fields":[{"name":"id","type":"long"}]}
    ),
  )
  guard @moonavro.value_from_json(schema, "{}")
    is Err(@moonavro.DatumMissingField(_, "id")) else {
    fail("missing datum field accepted")
  }
}

///|
test "reject invalid enum symbol and union wrapper" {
  let enum_schema = datum_schema(
    (
      #|{"type":"enum","name":"Color","symbols":["RED","BLUE"]}
    ),
  )
  guard @moonavro.value_from_json(enum_schema, "\"GREEN\"")
    is Err(@moonavro.DatumUnknownEnumSymbol(_, "GREEN")) else {
    fail("unknown enum symbol accepted")
  }
  let union_schema = datum_schema("[\"null\",\"string\"]")
  guard @moonavro.value_from_json(union_schema, "\"unwrapped\"")
    is Err(@moonavro.DatumInvalidUnion(_, _)) else {
    fail("unwrapped non-null union accepted")
  }
}

///|
test "round trip bytes and fixed JSON strings" {
  let bytes_schema = datum_schema("\"bytes\"")
  let bytes_value = @moonavro.BytesValue(b"\x00\x7f\x80\xff")
  let rendered = @moonavro.value_to_json_string(bytes_schema, bytes_value)
  guard rendered is Ok(text) else { fail("bytes render failed") }
  assert_eq(@moonavro.value_from_json(bytes_schema, text), Ok(bytes_value))
  let fixed_schema = datum_schema(
    "{\"type\":\"fixed\",\"name\":\"Four\",\"size\":4}",
  )
  let fixed_value = @moonavro.FixedValue(b"ABCD")
  let rendered = @moonavro.value_to_json_string(fixed_schema, fixed_value)
  guard rendered is Ok(text) else { fail("fixed render failed") }
  assert_eq(@moonavro.value_from_json(fixed_schema, text), Ok(fixed_value))
}

///|
test "reject non integral integer JSON" {
  let schema = datum_schema("\"int\"")
  guard @moonavro.value_from_json(schema, "1.5")
    is Err(@moonavro.DatumTypeMismatch(_, _, _)) else {
    fail("fractional int accepted")
  }
}

///|
test "named union JSON uses the declared short name" {
  let schema = datum_schema(
    (
      #|["null",{"type":"record","name":"Payload","namespace":"demo","fields":[{"name":"id","type":"long"}]}]
    ),
  )
  let value = @moonavro.UnionValue(
    1,
    @moonavro.RecordValue([("id", @moonavro.LongValue(7L))]),
  )
  assert_eq(
    @moonavro.value_to_json_string(schema, value),
    Ok("{\"Payload\":{\"id\":7}}"),
  )
  assert_eq(
    @moonavro.value_from_json(schema, "{\"Payload\":{\"id\":7}}"),
    Ok(value),
  )

  let enum_schema = datum_schema(
    (
      #|["null",{"type":"enum","name":"State","namespace":"demo","symbols":["READY"]}]
    ),
  )
  let enum_value = @moonavro.UnionValue(1, @moonavro.EnumValue("READY"))
  assert_eq(
    @moonavro.value_to_json_string(enum_schema, enum_value),
    Ok("{\"State\":\"READY\"}"),
  )
  assert_eq(
    @moonavro.value_from_json(enum_schema, "{\"State\":\"READY\"}"),
    Ok(enum_value),
  )

  let fixed_schema = datum_schema(
    (
      #|["null",{"type":"fixed","name":"Token","namespace":"demo","size":2}]
    ),
  )
  let fixed_value = @moonavro.UnionValue(1, @moonavro.FixedValue(b"AB"))
  assert_eq(
    @moonavro.value_to_json_string(fixed_schema, fixed_value),
    Ok("{\"Token\":\"AB\"}"),
  )
  assert_eq(
    @moonavro.value_from_json(fixed_schema, "{\"Token\":\"AB\"}"),
    Ok(fixed_value),
  )
}
