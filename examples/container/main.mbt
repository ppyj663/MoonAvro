///|
fn main {
  let schema = match
    @avro.parse_schema(
      (
        #|{"type":"record","name":"Measurement","namespace":"demo.archive","fields":[
        #|  {"name":"sequence","type":"long"},
        #|  {"name":"sensor","type":"string"},
        #|  {"name":"reading","type":"double"},
        #|  {"name":"tags","type":{"type":"map","values":"string"}}
        #|]}
      ),
    ) {
    Ok(document) => document
    Err(_) => abort("measurement schema must be valid")
  }
  let records = [
    @avro.RecordValue([
      ("sequence", @avro.LongValue(1L)),
      ("sensor", @avro.StringValue("north")),
      ("reading", @avro.DoubleValue(21.5)),
      ("tags", @avro.MapValue([("unit", @avro.StringValue("C"))])),
    ]),
    @avro.RecordValue([
      ("sequence", @avro.LongValue(2L)),
      ("sensor", @avro.StringValue("south")),
      ("reading", @avro.DoubleValue(19.75)),
      ("tags", @avro.MapValue([("unit", @avro.StringValue("C"))])),
    ]),
    @avro.RecordValue([
      ("sequence", @avro.LongValue(3L)),
      ("sensor", @avro.StringValue("east")),
      ("reading", @avro.DoubleValue(22.0)),
      ("tags", @avro.MapValue([("unit", @avro.StringValue("C"))])),
    ]),
  ]
  let file = match @avro.write_container(schema, records, block_records=2) {
    Ok(value) => value
    Err(_) => abort("measurements must write as an OCF file")
  }
  let container = match @avro.read_container(file) {
    Ok(value) => value
    Err(_) => abort("OCF file must read back")
  }
  println("OCF bytes: " + file.length().to_string())
  println("records: " + container.values.length().to_string())
  for value in container.values {
    match @avro.value_to_json_string(schema, value) {
      Ok(json) => println(json)
      Err(_) => abort("measurement must render as JSON")
    }
  }
}
