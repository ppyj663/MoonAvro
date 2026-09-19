///|
let user_schema =
  #|{
  #|  "type": "record",
  #|  "name": "User",
  #|  "namespace": "example.accounts",
  #|  "aliases": ["AccountHolder"],
  #|  "doc": "A user record",
  #|  "fields": [
  #|    {"name": "id", "type": "long"},
  #|    {"name": "name", "type": "string", "default": "anonymous"},
  #|    {"name": "emails", "type": {"type": "array", "items": "string"}},
  #|    {"name": "labels", "type": {"type": "map", "values": "string"}},
  #|    {"name": "status", "type": {"type": "enum", "name": "Status", "symbols": ["ACTIVE", "DISABLED"], "default": "ACTIVE"}},
  #|    {"name": "digest", "type": {"type": "fixed", "name": "Digest", "size": 16}},
  #|    {"name": "manager", "type": ["null", "User"], "default": null}
  #|  ]
  #|}

///|
test "parse a complete record schema" {
  let parsed = @moonavro.parse_schema(user_schema)
  guard parsed is Ok(document) else { fail("valid record was rejected") }
  assert_eq(document.root.kind(), "record")
  assert_eq(document.definition_count(), 3)
  guard document.root is @moonavro.Record(named, fields) else {
    fail("root is not a record")
  }
  assert_eq(named.full_name, "example.accounts.User")
  assert_eq(named.aliases, ["example.accounts.AccountHolder"])
  assert_eq(fields.length(), 7)
  assert_eq(fields[0].name, "id")
  assert_eq(fields[1].default, Some(@moonavro.StringValue("anonymous")))
  assert_eq(
    fields[6].default,
    Some(@moonavro.UnionValue(0, @moonavro.NullValue)),
  )
}

///|
test "parse primitive and union schemas" {
  let primitive = @moonavro.parse_schema("\"long\"")
  guard primitive is Ok(document) else { fail("primitive failed") }
  assert_eq(document.root, @moonavro.Primitive(@moonavro.Long))
  let union = @moonavro.parse_schema("[\"null\",\"string\",\"long\"]")
  guard union is Ok(document) else { fail("union failed") }
  guard document.root is @moonavro.Union(branches) else {
    fail("union expected")
  }
  assert_eq(branches.length(), 3)
}

///|
test "support recursive named references" {
  let text =
    #|{"type":"record","name":"Node","fields":[
    #| {"name":"value","type":"string"},
    #| {"name":"next","type":["null","Node"],"default":null}
    #|]}
  let parsed = @moonavro.parse_schema(text)
  guard parsed is Ok(document) else { fail("recursive schema failed") }
  guard document.root is @moonavro.Record(_, fields) else {
    fail("record expected")
  }
  guard fields[1].schema is @moonavro.Union(branches) else {
    fail("union expected")
  }
  assert_eq(branches[1], @moonavro.NamedRef("Node"))
}

///|
test "reject duplicate fields" {
  let text =
    #|{"type":"record","name":"Bad","fields":[
    #| {"name":"x","type":"int"},
    #| {"name":"x","type":"long"}
    #|]}
  let parsed = @moonavro.parse_schema(text)
  guard parsed is Err(@moonavro.DuplicateField(_, "x")) else {
    fail("duplicate field was accepted")
  }
}

///|
test "reject duplicate union branches" {
  let parsed = @moonavro.parse_schema("[\"null\",\"string\",\"string\"]")
  guard parsed is Err(@moonavro.DuplicateUnionBranch(_, "string")) else {
    fail("duplicate union branch was accepted")
  }
}

///|
test "reject nested unions" {
  let parsed = @moonavro.parse_schema("[\"null\",[\"string\",\"long\"]]")
  guard parsed is Err(@moonavro.NestedUnion(_)) else {
    fail("nested union was accepted")
  }
}

///|
test "reject unknown named references" {
  let text =
    #|{"type":"record","name":"Broken","fields":[
    #| {"name":"child","type":"Missing"}
    #|]}
  let parsed = @moonavro.parse_schema(text)
  guard parsed is Err(@moonavro.UnknownReference(_, "Missing")) else {
    fail("unknown reference was accepted")
  }
}

///|
test "validate enum symbols and defaults" {
  let duplicate = @moonavro.parse_schema(
    (
      #|{"type":"enum","name":"Color","symbols":["RED","RED"]}
    ),
  )
  guard duplicate is Err(@moonavro.DuplicateSymbol(_, "RED")) else {
    fail("duplicate enum symbol was accepted")
  }
  let invalid_default = @moonavro.parse_schema(
    (
      #|{"type":"enum","name":"Color","symbols":["RED"],"default":"BLUE"}
    ),
  )
  guard invalid_default is Err(@moonavro.InvalidDefault(_, _)) else {
    fail("invalid enum default was accepted")
  }
}

///|
test "validate fixed sizes and names" {
  let invalid_size = @moonavro.parse_schema(
    (
      #|{"type":"fixed","name":"Hash","size":0}
    ),
  )
  guard invalid_size is Err(@moonavro.InvalidProperty(_, "size", _)) else {
    fail("zero fixed size was accepted")
  }
  let invalid_name = @moonavro.parse_schema(
    (
      #|{"type":"record","name":"2User","fields":[]}
    ),
  )
  guard invalid_name is Err(@moonavro.InvalidName(_, "2User")) else {
    fail("invalid name was accepted")
  }
}

///|
test "parse compound defaults" {
  let text =
    #|{"type":"record","name":"Config","fields":[
    #| {"name":"flags","type":{"type":"array","items":"boolean"},"default":[true,false]},
    #| {"name":"labels","type":{"type":"map","values":"string"},"default":{"env":"test"}}
    #|]}
  let parsed = @moonavro.parse_schema(text)
  guard parsed is Ok(document) else { fail("compound defaults failed") }
  guard document.root is @moonavro.Record(_, fields) else {
    fail("record expected")
  }
  assert_eq(
    fields[0].default,
    Some(
      @moonavro.ArrayValue([
        @moonavro.BooleanValue(true),
        @moonavro.BooleanValue(false),
      ]),
    ),
  )
}

///|
test "reject invalid and duplicated aliases" {
  guard @moonavro.parse_schema(
      (
        #|{"type":"record","name":"User","aliases":["old name"],"fields":[]}
      ),
    )
    is Err(@moonavro.InvalidName(_, "old name")) else {
    fail("invalid named alias accepted")
  }
  guard @moonavro.parse_schema(
      (
        #|{"type":"record","name":"User","aliases":["Old","Old"],"fields":[]}
      ),
    )
    is Err(@moonavro.DuplicateAlias(_, "Old")) else {
    fail("duplicate named alias accepted")
  }
  guard @moonavro.parse_schema(
      (
        #|{"type":"record","name":"User","fields":[{"name":"id","type":"long","aliases":["old id"]}]}
      ),
    )
    is Err(@moonavro.InvalidName(_, "old id")) else {
    fail("invalid field alias accepted")
  }
  guard @moonavro.parse_schema(
      (
        #|{"type":"record","name":"User","fields":[{"name":"id","type":"long","aliases":["old_id","old_id"]}]}
      ),
    )
    is Err(@moonavro.DuplicateAlias(_, "old_id")) else {
    fail("duplicate field alias accepted")
  }
}
