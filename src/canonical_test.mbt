///|
fn canonical_schema(text : StringView) -> @moonavro.SchemaDocument {
  match @moonavro.parse_schema(text) {
    Ok(value) => value
    Err(_) => abort("canonical test schema failed")
  }
}

///|
test "canonicalize primitive schemas" {
  assert_eq(
    @moonavro.parsing_canonical_form(canonical_schema("\"string\"")),
    "\"string\"",
  )
  assert_eq(
    @moonavro.parsing_canonical_form(
      canonical_schema("{\"type\":\"array\",\"items\":\"long\"}"),
    ),
    "{\"type\":\"array\",\"items\":\"long\"}",
  )
}

///|
test "strip non parsing attributes from canonical form" {
  let schema = canonical_schema(
    (
      #|{
      #| "type":"record","name":"User","namespace":"demo",
      #| "doc":"ignored","aliases":["Person"],
      #| "fields":[
      #|   {"name":"id","type":"long","doc":"ignored","order":"descending"},
      #|   {"name":"name","type":"string","default":"unknown"}
      #| ]
      #|}
    ),
  )
  assert_eq(
    @moonavro.parsing_canonical_form(schema),
    "{\"name\":\"demo.User\",\"type\":\"record\",\"fields\":[{\"name\":\"id\",\"type\":\"long\"},{\"name\":\"name\",\"type\":\"string\"}]}",
  )
}

///|
test "canonical form emits recursive record name once" {
  let schema = canonical_schema(
    (
      #|{"type":"record","name":"Node","namespace":"tree","fields":[
      #| {"name":"value","type":"string"},
      #| {"name":"children","type":{"type":"array","items":"Node"}}
      #|]}
    ),
  )
  assert_eq(
    @moonavro.parsing_canonical_form(schema),
    "{\"name\":\"tree.Node\",\"type\":\"record\",\"fields\":[{\"name\":\"value\",\"type\":\"string\"},{\"name\":\"children\",\"type\":{\"type\":\"array\",\"items\":\"tree.Node\"}}]}",
  )
}

///|
test "fingerprint is stable across irrelevant schema spelling" {
  let compact = canonical_schema(
    (
      #|{"type":"record","name":"Point","namespace":"geo","fields":[{"name":"x","type":"double"},{"name":"y","type":"double"}]}
    ),
  )
  let documented = canonical_schema(
    (
      #|{"doc":"coordinates","namespace":"geo","name":"Point","type":"record","fields":[{"type":"double","name":"x","doc":"horizontal"},{"default":0,"name":"y","type":"double"}]}
    ),
  )
  assert_eq(
    @moonavro.parsing_canonical_form(compact),
    @moonavro.parsing_canonical_form(documented),
  )
  assert_eq(
    @moonavro.schema_fingerprint64(compact),
    @moonavro.schema_fingerprint64(documented),
  )
  assert_eq(
    @moonavro.fingerprint64_hex(@moonavro.schema_fingerprint64(compact)).length(),
    16,
  )
}

///|
test "single object encoding carries fingerprint and datum" {
  let schema = canonical_schema("\"string\"")
  let encoded = @moonavro.encode_single_object(
    schema,
    @moonavro.StringValue("hello"),
  )
  guard encoded is Ok(bytes) else { fail("single object encode failed") }
  assert_eq(bytes[0:2].to_owned(), b"\xc3\x01")
  assert_eq(
    @moonavro.decode_single_object(schema, bytes),
    Ok(@moonavro.StringValue("hello")),
  )
}

///|
test "single object decoding rejects header and fingerprint mismatch" {
  let string_schema = canonical_schema("\"string\"")
  let long_schema = canonical_schema("\"long\"")
  guard @moonavro.decode_single_object(string_schema, b"bad")
    is Err(@moonavro.InvalidSingleObjectHeader) else {
    fail("invalid single object header accepted")
  }
  let encoded = @moonavro.encode_single_object(
    string_schema,
    @moonavro.StringValue("hello"),
  )
  guard encoded is Ok(bytes) else { fail("encode failed") }
  guard @moonavro.decode_single_object(long_schema, bytes)
    is Err(@moonavro.FingerprintMismatch(_, _)) else {
    fail("wrong fingerprint accepted")
  }
}
