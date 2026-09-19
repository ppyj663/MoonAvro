///|
fn main {
  let schema_text =
    #|{"type":"record","name":"Greeting","namespace":"demo","fields":[
    #| {"name":"message","type":"string"},
    #| {"name":"language","type":"string","default":"en"},
    #| {"name":"priority","type":"int"}
    #|]}
  let schema = match @avro.parse_schema(schema_text) {
    Ok(value) => value
    Err(_) => abort("example schema must be valid")
  }
  let original = @avro.RecordValue([
    ("message", @avro.StringValue("Hello from MoonAvro")),
    ("language", @avro.StringValue("en")),
    ("priority", @avro.IntValue(1)),
  ])
  let bytes = match @avro.encode(schema, original) {
    Ok(value) => value
    Err(_) => abort("example value must encode")
  }
  let decoded = match @avro.decode(schema, bytes) {
    Ok(value) => value
    Err(_) => abort("example bytes must decode")
  }
  let json = match @avro.value_to_json_string(schema, decoded, pretty=true) {
    Ok(value) => value
    Err(_) => abort("example value must render")
  }
  println("canonical schema:")
  println(@avro.parsing_canonical_form(schema))
  println(
    "fingerprint: " +
    @avro.fingerprint64_hex(@avro.schema_fingerprint64(schema)),
  )
  println("encoded bytes: " + bytes.length().to_string())
  println("decoded value:")
  println(json)
}
