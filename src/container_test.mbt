///|
fn container_schema() -> @moonavro.SchemaDocument {
  match
    @moonavro.parse_schema(
      (
        #|{"type":"record","name":"LogEntry","namespace":"demo","fields":[
        #| {"name":"sequence","type":"long"},
        #| {"name":"message","type":"string"},
        #| {"name":"level","type":{"type":"enum","name":"Level","symbols":["INFO","WARN","ERROR"]}}
        #|]}
      ),
    ) {
    Ok(value) => value
    Err(_) => abort("container schema failed")
  }
}

///|
fn log_entry(
  sequence : Int64,
  message : String,
  level : String,
) -> @moonavro.Value {
  @moonavro.RecordValue([
    ("sequence", @moonavro.LongValue(sequence)),
    ("message", @moonavro.StringValue(message)),
    ("level", @moonavro.EnumValue(level)),
  ])
}

///|
fn byte_occurrences(data : Bytes, needle : Bytes) -> Int {
  if needle.is_empty() || needle.length() > data.length() {
    return 0
  }
  let mut count = 0
  let mut position = 0
  while position <= data.length() - needle.length() {
    let mut matched = true
    for offset = 0; offset < needle.length(); offset = offset + 1 {
      if data[position + offset] != needle[offset] {
        matched = false
        break
      }
    }
    if matched {
      count = count + 1
      position = position + needle.length()
    } else {
      position = position + 1
    }
  }
  count
}

///|
test "write and read object container file" {
  let schema = container_schema()
  let values = [
    log_entry(1L, "service started", "INFO"),
    log_entry(2L, "queue is filling", "WARN"),
    log_entry(3L, "worker failed", "ERROR"),
  ]
  let encoded = @moonavro.write_container(
    schema,
    values,
    metadata=[("producer", b"MoonAvro tests")],
    sync_marker=b"0123456789abcdef",
  )
  guard encoded is Ok(bytes) else { fail("container encode failed") }
  assert_eq(bytes[0:4].to_owned(), b"Obj\x01")
  let decoded = @moonavro.read_container(bytes)
  guard decoded is Ok(container) else { fail("container decode failed") }
  assert_eq(container.values, values)
  assert_eq(container.sync_marker, b"0123456789abcdef")
  assert_eq(container.metadata.length(), 3)
  assert_eq(
    @moonavro.parsing_canonical_form(container.schema),
    @moonavro.parsing_canonical_form(schema),
  )
}

///|
test "container writer splits records into bounded blocks" {
  let marker = b"0123456789abcdef"
  let values = [
    log_entry(1L, "one", "INFO"),
    log_entry(2L, "two", "WARN"),
    log_entry(3L, "three", "ERROR"),
  ]
  let encoded = @moonavro.write_container(
    container_schema(),
    values,
    sync_marker=marker,
    block_records=2,
  )
  guard encoded is Ok(bytes) else { fail("container encode failed") }
  assert_eq(byte_occurrences(bytes, marker), 3)
  let decoded = @moonavro.read_container(bytes)
  guard decoded is Ok(container) else { fail("container decode failed") }
  assert_eq(container.values, values)
}

///|
test "round trip empty container" {
  let schema = container_schema()
  let encoded = @moonavro.write_container(schema, [])
  guard encoded is Ok(bytes) else { fail("empty container encode failed") }
  let decoded = @moonavro.read_container(bytes)
  guard decoded is Ok(container) else { fail("empty container decode failed") }
  assert_eq(container.values, [])
}

///|
test "container rejects invalid magic" {
  guard @moonavro.read_container(b"NOPE") is Err(@moonavro.InvalidMagic) else {
    fail("invalid magic accepted")
  }
}

///|
test "container requires sixteen byte sync marker" {
  guard @moonavro.write_container(container_schema(), [], sync_marker=b"short")
    is Err(@moonavro.InvalidSyncMarker) else {
    fail("invalid sync marker accepted")
  }
}

///|
test "container rejects a non-positive block record limit" {
  guard @moonavro.write_container(
      container_schema(),
      [log_entry(1L, "hello", "INFO")],
      block_records=0,
    )
    is Err(@moonavro.InvalidBlockRecordLimit(0)) else {
    fail("invalid block record limit accepted")
  }
}

///|
test "container detects changed block sync marker" {
  let encoded = @moonavro.write_container(
    container_schema(),
    [log_entry(1L, "hello", "INFO")],
    sync_marker=b"0123456789abcdef",
  )
  guard encoded is Ok(bytes) else { fail("container encode failed") }
  let damaged = bytes.to_array()
  damaged[damaged.length() - 1] = b'X'
  guard @moonavro.read_container(Bytes::from_array(damaged))
    is Err(@moonavro.InvalidSyncMarker) else {
    fail("damaged sync marker accepted")
  }
}

///|
test "container reads negative-count size-prefixed blocks" {
  let encoded = @moonavro.write_container(
    container_schema(),
    [log_entry(8L, "negative block count", "INFO")],
    sync_marker=b"0123456789abcdef",
  )
  guard encoded is Ok(bytes) else { fail("container encode failed") }
  let reader = @moonavro.BinaryReader::new(bytes)
  guard reader.read_exact(4) is Ok(_) else { fail("container magic missing") }
  let mut metadata_finished = false
  while !metadata_finished {
    let metadata_count = match reader.read_long() {
      Ok(value) => value
      Err(_) => fail("container metadata count missing")
    }
    if metadata_count == 0L {
      metadata_finished = true
    } else {
      let entry_count = if metadata_count < 0L {
        let _declared_size = match reader.read_long() {
          Ok(value) => value
          Err(_) => fail("container metadata block size missing")
        }
        -metadata_count
      } else {
        metadata_count
      }
      let entry_count_int = entry_count.to_int()
      for entry_index = 0
          entry_index < entry_count_int
          entry_index = entry_index + 1 {
        guard reader.read_string(@moonavro.AvroPath::root()) is Ok(_) else {
          fail("container metadata key missing")
        }
        guard reader.read_bytes(@moonavro.AvroPath::root()) is Ok(_) else {
          fail("container metadata value missing")
        }
      }
    }
  }
  guard reader.read_exact(16) is Ok(_) else { fail("container sync missing") }
  let negative_count = @moonavro.encode_long(-1L)
  assert_eq(negative_count.length(), 1)
  let changed = bytes.to_array()
  changed[reader.offset()] = negative_count[0]
  let decoded = @moonavro.read_container(Bytes::from_array(changed))
  guard decoded is Ok(container) else { fail("negative block count rejected") }
  assert_eq(container.values, [log_entry(8L, "negative block count", "INFO")])
}

///|
test "container reports datum encoding errors" {
  let invalid = @moonavro.RecordValue([
    ("sequence", @moonavro.LongValue(1L)),
    ("message", @moonavro.StringValue("missing level")),
  ])
  guard @moonavro.write_container(container_schema(), [invalid])
    is Err(@moonavro.ContainerEncode(@moonavro.MissingFieldValue(_, "level"))) else {
    fail("invalid record was accepted")
  }
}

///|
test "container preserves complete writer schema JSON" {
  let schema = match
    @moonavro.parse_schema(
      (
        #|{"type":"record","name":"Envelope","namespace":"demo","aliases":["OldEnvelope"],"doc":"event envelope","fields":[
        #| {"name":"message","type":["string","null"],"default":"unset","aliases":["text"],"doc":"payload","order":"descending"},
        #| {"name":"state","type":{"type":"enum","name":"State","aliases":["OldState"],"symbols":["NEW","DONE"],"default":"NEW"},"default":"NEW"}
        #|]}
      ),
    ) {
    Ok(value) => value
    Err(_) => abort("metadata schema failed")
  }
  let encoded = @moonavro.write_container(schema, [])
  guard encoded is Ok(bytes) else { fail("container encode failed") }
  let decoded = @moonavro.read_container(bytes)
  guard decoded is Ok(container) else { fail("container decode failed") }
  assert_eq(container.schema, schema)
  guard @moonavro.schema_to_json(container.schema) is Ok(json) else {
    fail("schema JSON render failed")
  }
  assert_true(json.contains("\"default\":\"unset\""))
  assert_true(json.contains("\"demo.OldEnvelope\""))
  assert_true(json.contains("\"descending\""))
}
