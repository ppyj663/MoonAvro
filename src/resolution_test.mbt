///|
fn resolution_schema(text : StringView) -> @moonavro.SchemaDocument {
  match @moonavro.parse_schema(text) {
    Ok(document) => document
    Err(_) => abort("resolution test schema failed")
  }
}

///|
test "promote numeric primitive values" {
  let int_schema = resolution_schema("\"int\"")
  let long_schema = resolution_schema("\"long\"")
  let float_schema = resolution_schema("\"float\"")
  let double_schema = resolution_schema("\"double\"")
  assert_eq(
    @moonavro.resolve_value(int_schema, long_schema, @moonavro.IntValue(42)),
    Ok(@moonavro.LongValue(42L)),
  )
  assert_eq(
    @moonavro.resolve_value(int_schema, double_schema, @moonavro.IntValue(42)),
    Ok(@moonavro.DoubleValue(42.0)),
  )
  assert_eq(
    @moonavro.resolve_value(
      float_schema,
      double_schema,
      @moonavro.FloatValue(1.5F),
    ),
    Ok(@moonavro.DoubleValue(1.5)),
  )
}

///|
test "reject numeric demotion" {
  let writer = resolution_schema("\"double\"")
  let reader = resolution_schema("\"int\"")
  let report = @moonavro.check_compatibility(writer, reader)
  assert_false(report.compatible)
  assert_eq(report.issues.length(), 1)
}

///|
test "resolve record field aliases reordering and defaults" {
  let writer = resolution_schema(
    (
      #|{"type":"record","name":"UserV1","namespace":"demo","fields":[
      #| {"name":"user_id","type":"int"},
      #| {"name":"name","type":"string"},
      #| {"name":"obsolete","type":"boolean"}
      #|]}
    ),
  )
  let reader = resolution_schema(
    (
      #|{"type":"record","name":"UserV2","namespace":"demo","aliases":["UserV1"],"fields":[
      #| {"name":"display_name","aliases":["name"],"type":"string"},
      #| {"name":"id","aliases":["user_id"],"type":"long"},
      #| {"name":"enabled","type":"boolean","default":true}
      #|]}
    ),
  )
  let value = @moonavro.RecordValue([
    ("user_id", @moonavro.IntValue(9)),
    ("name", @moonavro.StringValue("Ada")),
    ("obsolete", @moonavro.BooleanValue(false)),
  ])
  assert_true(@moonavro.check_compatibility(writer, reader).compatible)
  assert_eq(
    @moonavro.resolve_value(writer, reader, value),
    Ok(
      @moonavro.RecordValue([
        ("display_name", @moonavro.StringValue("Ada")),
        ("id", @moonavro.LongValue(9L)),
        ("enabled", @moonavro.BooleanValue(true)),
      ]),
    ),
  )
}

///|
test "report every reader field without a default" {
  let writer = resolution_schema(
    (
      #|{"type":"record","name":"R","fields":[{"name":"a","type":"int"}]}
    ),
  )
  let reader = resolution_schema(
    (
      #|{"type":"record","name":"R","fields":[
      #| {"name":"a","type":"int"},
      #| {"name":"b","type":"string"},
      #| {"name":"c","type":"long"}
      #|]}
    ),
  )
  let report = @moonavro.check_compatibility(writer, reader)
  assert_false(report.compatible)
  assert_eq(report.issues.length(), 2)
  assert_eq(report.issues[0].path.to_string(), "$.b")
  assert_eq(report.issues[1].path.to_string(), "$.c")
}

///|
test "use reader enum default for removed writer symbol" {
  let writer = resolution_schema(
    (
      #|{"type":"enum","name":"State","symbols":["NEW","RUNNING","DONE"]}
    ),
  )
  let reader = resolution_schema(
    (
      #|{"type":"enum","name":"State","symbols":["NEW","DONE","UNKNOWN"],"default":"UNKNOWN"}
    ),
  )
  assert_true(@moonavro.check_compatibility(writer, reader).compatible)
  assert_eq(
    @moonavro.resolve_value(writer, reader, @moonavro.EnumValue("RUNNING")),
    Ok(@moonavro.EnumValue("UNKNOWN")),
  )
}

///|
test "reject removed enum symbol without default" {
  let writer = resolution_schema(
    (
      #|{"type":"enum","name":"State","symbols":["NEW","OLD"]}
    ),
  )
  let reader = resolution_schema(
    (
      #|{"type":"enum","name":"State","symbols":["NEW"]}
    ),
  )
  assert_false(@moonavro.check_compatibility(writer, reader).compatible)
  guard @moonavro.resolve_value(writer, reader, @moonavro.EnumValue("OLD"))
    is Err(@moonavro.MissingEnumDefault(_, "OLD")) else {
    fail("missing enum default was ignored")
  }
}

///|
test "resolve writer union into reader union" {
  let writer = resolution_schema("[\"null\",\"int\",\"string\"]")
  let reader = resolution_schema("[\"null\",\"long\",\"bytes\"]")
  let int_value = @moonavro.UnionValue(1, @moonavro.IntValue(7))
  assert_eq(
    @moonavro.resolve_value(writer, reader, int_value),
    Ok(@moonavro.UnionValue(1, @moonavro.LongValue(7L))),
  )
  let string_value = @moonavro.UnionValue(2, @moonavro.StringValue("hi"))
  assert_eq(
    @moonavro.resolve_value(writer, reader, string_value),
    Ok(@moonavro.UnionValue(2, @moonavro.BytesValue(b"hi"))),
  )
}

///|
test "resolve arrays and maps recursively" {
  let writer_array = resolution_schema("{\"type\":\"array\",\"items\":\"int\"}")
  let reader_array = resolution_schema(
    "{\"type\":\"array\",\"items\":\"long\"}",
  )
  assert_eq(
    @moonavro.resolve_value(
      writer_array,
      reader_array,
      @moonavro.ArrayValue([@moonavro.IntValue(1), @moonavro.IntValue(2)]),
    ),
    Ok(@moonavro.ArrayValue([@moonavro.LongValue(1L), @moonavro.LongValue(2L)])),
  )
  let writer_map = resolution_schema("{\"type\":\"map\",\"values\":\"float\"}")
  let reader_map = resolution_schema("{\"type\":\"map\",\"values\":\"double\"}")
  assert_eq(
    @moonavro.resolve_value(
      writer_map,
      reader_map,
      @moonavro.MapValue([("x", @moonavro.FloatValue(2.5F))]),
    ),
    Ok(@moonavro.MapValue([("x", @moonavro.DoubleValue(2.5))])),
  )
}

///|
test "decode with writer schema and resolve to reader" {
  let writer = resolution_schema(
    (
      #|{"type":"record","name":"Metric","fields":[{"name":"value","type":"int"}]}
    ),
  )
  let reader = resolution_schema(
    (
      #|{"type":"record","name":"Metric","fields":[
      #| {"name":"value","type":"long"},
      #| {"name":"unit","type":"string","default":"count"}
      #|]}
    ),
  )
  let encoded = @moonavro.encode(
    writer,
    @moonavro.RecordValue([("value", @moonavro.IntValue(3))]),
  )
  guard encoded is Ok(bytes) else { fail("writer encode failed") }
  assert_eq(
    @moonavro.decode_resolved(writer, reader, bytes),
    Ok(
      @moonavro.RecordValue([
        ("value", @moonavro.LongValue(3L)),
        ("unit", @moonavro.StringValue("count")),
      ]),
    ),
  )
}

///|
test "fixed types require matching name and size" {
  let writer = resolution_schema(
    "{\"type\":\"fixed\",\"name\":\"Hash\",\"size\":16}",
  )
  let wrong_size = resolution_schema(
    "{\"type\":\"fixed\",\"name\":\"Hash\",\"size\":32}",
  )
  let alias_reader = resolution_schema(
    (
      #|{"type":"fixed","name":"Digest","aliases":["Hash"],"size":16}
    ),
  )
  assert_false(@moonavro.check_compatibility(writer, wrong_size).compatible)
  assert_true(@moonavro.check_compatibility(writer, alias_reader).compatible)
}
