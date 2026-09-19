///|
fn parse_test_schema(text : StringView) -> @moonavro.SchemaDocument {
  match @moonavro.parse_schema(text) {
    Ok(document) => document
    Err(_) => abort("test schema failed to parse")
  }
}

///|
test "round trip all primitive values" {
  let cases : Array[(@moonavro.SchemaDocument, @moonavro.Value)] = [
    (parse_test_schema("\"null\""), @moonavro.NullValue),
    (parse_test_schema("\"boolean\""), @moonavro.BooleanValue(true)),
    (parse_test_schema("\"int\""), @moonavro.IntValue(-42)),
    (parse_test_schema("\"long\""), @moonavro.LongValue(9876543210L)),
    (parse_test_schema("\"float\""), @moonavro.FloatValue(3.5F)),
    (parse_test_schema("\"double\""), @moonavro.DoubleValue(-0.125)),
    (parse_test_schema("\"bytes\""), @moonavro.BytesValue(b"\x00\x01\xff")),
    (parse_test_schema("\"string\""), @moonavro.StringValue("hello 月兔")),
  ]
  for (schema, value) in cases {
    let encoded = @moonavro.encode(schema, value)
    guard encoded is Ok(bytes) else { fail("primitive encode failed") }
    assert_eq(@moonavro.decode(schema, bytes), Ok(value))
  }
}

///|
test "round trip compound record" {
  let schema = parse_test_schema(
    (
      #|{"type":"record","name":"Event","namespace":"demo","fields":[
      #| {"name":"id","type":"long"},
      #| {"name":"tags","type":{"type":"array","items":"string"}},
      #| {"name":"metrics","type":{"type":"map","values":"double"}},
      #| {"name":"state","type":{"type":"enum","name":"State","symbols":["NEW","DONE"]}},
      #| {"name":"trace","type":{"type":"fixed","name":"Trace","size":4}},
      #| {"name":"note","type":["null","string"]}
      #|]}
    ),
  )
  let value = @moonavro.RecordValue([
    ("id", @moonavro.LongValue(7L)),
    (
      "tags",
      @moonavro.ArrayValue([
        @moonavro.StringValue("moonbit"),
        @moonavro.StringValue("avro"),
      ]),
    ),
    (
      "metrics",
      @moonavro.MapValue([
        ("latency", @moonavro.DoubleValue(12.5)),
        ("load", @moonavro.DoubleValue(0.75)),
      ]),
    ),
    ("state", @moonavro.EnumValue("NEW")),
    ("trace", @moonavro.FixedValue(b"ABCD")),
    ("note", @moonavro.UnionValue(1, @moonavro.StringValue("ready"))),
  ])
  let encoded = @moonavro.encode(schema, value)
  guard encoded is Ok(bytes) else { fail("compound encode failed") }
  assert_eq(@moonavro.decode(schema, bytes), Ok(value))
}

///|
test "record encoding follows schema field order" {
  let schema = parse_test_schema(
    (
      #|{"type":"record","name":"Pair","fields":[
      #| {"name":"left","type":"int"},
      #| {"name":"right","type":"int"}
      #|]}
    ),
  )
  let value = @moonavro.RecordValue([
    ("right", @moonavro.IntValue(2)),
    ("left", @moonavro.IntValue(1)),
  ])
  assert_eq(@moonavro.encode(schema, value), Ok(b"\x02\x04"))
}

///|
test "diagnose missing record fields" {
  let schema = parse_test_schema(
    (
      #|{"type":"record","name":"User","fields":[{"name":"id","type":"long"}]}
    ),
  )
  let result = @moonavro.encode(schema, @moonavro.RecordValue([]))
  guard result is Err(@moonavro.MissingFieldValue(_, "id")) else {
    fail("missing field was accepted")
  }
}

///|
test "diagnose value type mismatch" {
  let schema = parse_test_schema("\"long\"")
  let result = @moonavro.encode(schema, @moonavro.StringValue("not a long"))
  guard result is Err(@moonavro.ValueMismatch(_, "long", "string")) else {
    fail("wrong value type was accepted")
  }
}

///|
test "diagnose enum union and fixed errors" {
  let enum_schema = parse_test_schema(
    (
      #|{"type":"enum","name":"Color","symbols":["RED","GREEN"]}
    ),
  )
  guard @moonavro.encode(enum_schema, @moonavro.EnumValue("BLUE"))
    is Err(@moonavro.UnknownEnumSymbol(_, "BLUE")) else {
    fail("unknown symbol accepted")
  }
  let union_schema = parse_test_schema("[\"null\",\"string\"]")
  guard @moonavro.encode(
      union_schema,
      @moonavro.UnionValue(3, @moonavro.StringValue("x")),
    )
    is Err(@moonavro.InvalidUnionBranch(_, 3)) else {
    fail("invalid union branch accepted")
  }
  let fixed_schema = parse_test_schema(
    (
      #|{"type":"fixed","name":"Hash","size":4}
    ),
  )
  guard @moonavro.encode(fixed_schema, @moonavro.FixedValue(b"abc"))
    is Err(@moonavro.FixedSizeMismatch(_, 4, 3)) else {
    fail("wrong fixed size accepted")
  }
}

///|
test "decode negative-count array block" {
  let schema = parse_test_schema("{\"type\":\"array\",\"items\":\"int\"}")
  // count=-2, block byte-size=2, values 1 and 2, terminator=0
  let bytes = b"\x03\x04\x02\x04\x00"
  assert_eq(
    @moonavro.decode(schema, bytes),
    Ok(@moonavro.ArrayValue([@moonavro.IntValue(1), @moonavro.IntValue(2)])),
  )
}

///|
test "reject trailing data and invalid collection block size" {
  let int_schema = parse_test_schema("\"int\"")
  guard @moonavro.decode(int_schema, b"\x02\x00")
    is Err(@moonavro.TrailingData(1)) else {
    fail("trailing bytes accepted")
  }
  let array_schema = parse_test_schema("{\"type\":\"array\",\"items\":\"int\"}")
  guard @moonavro.decode(array_schema, b"\x03\x02\x02\x04\x00")
    is Err(@moonavro.BlockSizeMismatch(_, 1L, 2)) else {
    fail("invalid block size accepted")
  }
}
