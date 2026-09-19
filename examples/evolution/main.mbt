///|
fn main {
  let writer_schema_text =
    #|{"type":"record","name":"Event","namespace":"demo.events","fields":[
    #|  {"name":"event_id","type":"long"},
    #|  {"name":"message","type":"string"}
    #|]}
  let reader_schema_text =
    #|{"type":"record","name":"EventV2","namespace":"demo.events","aliases":["Event"],"fields":[
    #|  {"name":"message","type":"string"},
    #|  {"name":"event_id","type":"double"},
    #|  {"name":"source","type":"string","default":"legacy-import"}
    #|]}
  let writer = match @avro.parse_schema(writer_schema_text) {
    Ok(document) => document
    Err(_) => abort("writer schema must be valid")
  }
  let reader = match @avro.parse_schema(reader_schema_text) {
    Ok(document) => document
    Err(_) => abort("reader schema must be valid")
  }
  let old_event = @avro.RecordValue([
    ("event_id", @avro.LongValue(1042L)),
    ("message", @avro.StringValue("worker started")),
  ])
  let bytes = match @avro.encode(writer, old_event) {
    Ok(value) => value
    Err(_) => abort("writer event must encode")
  }
  let upgraded = match @avro.decode_resolved(writer, reader, bytes) {
    Ok(value) => value
    Err(_) => abort("reader schema must resolve writer event")
  }
  let json = match @avro.value_to_json_string(reader, upgraded, pretty=true) {
    Ok(value) => value
    Err(_) => abort("resolved event must render")
  }
  println("resolved event:")
  println(json)
}
