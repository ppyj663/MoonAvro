///|
test "primitive names round trip" {
  let cases = [
    ("null", @moonavro.Null),
    ("boolean", @moonavro.Boolean),
    ("int", @moonavro.Int),
    ("long", @moonavro.Long),
    ("float", @moonavro.Float),
    ("double", @moonavro.Double),
    ("bytes", @moonavro.Bytes),
    ("string", @moonavro.String),
  ]
  for (name, kind) in cases {
    assert_eq(@moonavro.primitive_from_name(name), Some(kind))
    assert_eq(kind.name(), name)
  }
  assert_eq(@moonavro.primitive_from_name("record"), None)
}

///|
test "qualified names retain namespace" {
  let named = @moonavro.NamedType::new(
    "User",
    "example.accounts",
    ["Member"],
    Some("An account holder"),
  )
  assert_eq(named.full_name, "example.accounts.User")
  assert_eq(@moonavro.fullname("User", "example.accounts"), named.full_name)
  assert_eq(@moonavro.shortname(named.full_name), "User")
  assert_eq(@moonavro.namespace_of(named.full_name), "example.accounts")
}

///|
test "schema document resolves named references" {
  let named = @moonavro.NamedType::new("Point", "geometry", [], None)
  let schema = @moonavro.Record(named, [])
  let definitions = Map([])
  definitions.set("geometry.Point", schema)
  let document = @moonavro.SchemaDocument::new(
    @moonavro.NamedRef("geometry.Point"),
    definitions,
  )
  assert_eq(document.definition_count(), 1)
  assert_eq(document.resolve(document.root), Some(schema))
}

///|
test "value record lookup preserves first matching field" {
  let value = @moonavro.Value::record([
    ("name", @moonavro.StringValue("Ada")),
    ("age", @moonavro.IntValue(36)),
  ])
  assert_eq(value.get_field("name"), Some(@moonavro.StringValue("Ada")))
  assert_eq(value.get_field("missing"), None)
  assert_eq(value.kind(), "record")
}

///|
test "validate avro names" {
  assert_true(@moonavro.valid_name("User_2"))
  assert_true(@moonavro.valid_fullname("org.example.User_2"))
  assert_false(@moonavro.valid_name("2User"))
  assert_false(@moonavro.valid_name("user-name"))
  assert_false(@moonavro.valid_fullname("org..User"))
}
