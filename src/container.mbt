///|
let object_container_magic : Bytes = b"Obj\x01"

///|
let default_sync_marker : Bytes = b"MoonAvroSyncMVP!"

///|
pub(all) struct ContainerFile {
  schema : SchemaDocument
  metadata : Array[(String, Bytes)]
  sync_marker : Bytes
  values : Array[Value]
} derive(Eq, Debug)

///|
fn metadata_value(metadata : Array[(String, Bytes)], key : String) -> Bytes? {
  for (entry_key, value) in metadata {
    if entry_key == key {
      return Some(value)
    }
  }
  None
}

///|
fn write_metadata_map(
  writer : BinaryWriter,
  metadata : Array[(String, Bytes)],
) -> Unit {
  if !metadata.is_empty() {
    writer.write_long(metadata.length().to_int64())
    for (key, value) in metadata {
      writer.write_string(key)
      writer.write_bytes(value)
    }
  }
  writer.write_long(0L)
}

///|
fn read_metadata_map(
  reader : BinaryReader,
) -> Result[Array[(String, Bytes)], ContainerError] {
  let metadata : Array[(String, Bytes)] = []
  while true {
    let raw_count = match reader.read_long() {
      Ok(value) => value
      Err(error) =>
        return Err(InvalidMetadata(Debug::to_repr(error).to_string()))
    }
    if raw_count == 0L {
      break
    }
    let mut count = raw_count
    let mut declared_size : Int64? = None
    if count < 0L {
      if count == -9223372036854775808L {
        return Err(InvalidMetadata("invalid metadata block count"))
      }
      count = -count
      declared_size = match reader.read_long() {
        Ok(value) => Some(value)
        Err(error) =>
          return Err(InvalidMetadata(Debug::to_repr(error).to_string()))
      }
    }
    let count_int = count.to_int()
    if count_int < 0 || count_int.to_int64() != count {
      return Err(InvalidMetadata("metadata count exceeds platform size"))
    }
    let start = reader.offset()
    for entry_index = 0; entry_index < count_int; entry_index = entry_index + 1 {
      let key = match reader.read_string(AvroPath::root().field("metadata")) {
        Ok(value) => value
        Err(error) =>
          return Err(InvalidMetadata(Debug::to_repr(error).to_string()))
      }
      let value = match reader.read_bytes(AvroPath::root().field(key)) {
        Ok(value) => value
        Err(error) =>
          return Err(InvalidMetadata(Debug::to_repr(error).to_string()))
      }
      metadata.push((key, value))
    }
    match declared_size {
      Some(expected) => {
        let actual = reader.offset() - start
        if expected != actual.to_int64() {
          return Err(InvalidMetadata("metadata block size mismatch"))
        }
      }
      None => ()
    }
  }
  Ok(metadata)
}

///|
/// Write an Avro object container file using the required `null` codec.
pub fn write_container(
  schema : SchemaDocument,
  values : Array[Value],
  metadata? : Array[(String, Bytes)] = [],
  sync_marker? : Bytes = default_sync_marker,
) -> Result[Bytes, ContainerError] {
  if sync_marker.length() != 16 {
    return Err(InvalidSyncMarker)
  }
  let schema_json = match schema_to_json(schema) {
    Ok(value) => value
    Err(error) => return Err(ContainerSchema(error))
  }
  let header_metadata : Array[(String, Bytes)] = [
    ("avro.schema", @utf8.encode(schema_json)),
    ("avro.codec", b"null"),
  ]
  for (key, value) in metadata {
    if key != "avro.schema" && key != "avro.codec" {
      header_metadata.push((key, value))
    }
  }
  let output = BinaryWriter::new()
  output.write_raw(object_container_magic[:])
  write_metadata_map(output, header_metadata)
  output.write_raw(sync_marker[:])
  if !values.is_empty() {
    let block = BinaryWriter::new()
    for value in values {
      match encode_into(block, schema, value) {
        Ok(_) => ()
        Err(error) => return Err(ContainerEncode(error))
      }
    }
    let block_bytes = block.finish()
    output.write_long(values.length().to_int64())
    output.write_long(block_bytes.length().to_int64())
    output.write_raw(block_bytes[:])
    output.write_raw(sync_marker[:])
  }
  Ok(output.finish())
}

///|
fn read_container_header(
  reader : BinaryReader,
) -> Result[(SchemaDocument, Array[(String, Bytes)], Bytes), ContainerError] {
  let magic = match reader.read_exact(4) {
    Ok(value) => value
    Err(_) => return Err(InvalidMagic)
  }
  if magic != object_container_magic {
    return Err(InvalidMagic)
  }
  let metadata = match read_metadata_map(reader) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let schema_bytes = match metadata_value(metadata, "avro.schema") {
    Some(value) => value
    None => return Err(MissingSchemaMetadata)
  }
  let schema_text = @utf8.decode(schema_bytes[:]) catch {
    _ => return Err(InvalidMetadata("avro.schema is not UTF-8"))
  }
  let schema = match parse_schema(schema_text) {
    Ok(value) => value
    Err(error) => return Err(ContainerSchema(error))
  }
  let codec = match metadata_value(metadata, "avro.codec") {
    None => "null"
    Some(bytes) =>
      @utf8.decode(bytes[:]) catch {
        _ => return Err(InvalidMetadata("avro.codec is not UTF-8"))
      }
  }
  if codec != "null" {
    return Err(UnsupportedCodec(codec))
  }
  let sync_marker = match reader.read_exact(16) {
    Ok(value) => value
    Err(_) => return Err(InvalidSyncMarker)
  }
  Ok((schema, metadata, sync_marker))
}

///|
/// Read every block from a null-codec Avro object container file.
pub fn read_container(data : Bytes) -> Result[ContainerFile, ContainerError] {
  let reader = BinaryReader::new(data)
  let (schema, metadata, sync_marker) = match read_container_header(reader) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let values : Array[Value] = []
  while !reader.is_finished() {
    let count = match reader.read_long() {
      Ok(value) => value
      Err(error) =>
        return Err(InvalidContainerBlock(Debug::to_repr(error).to_string()))
    }
    if count == 0L || count == -9223372036854775808L {
      return Err(InvalidContainerBlock("record count must be positive"))
    }
    // A negative count is the OCF size-prefixed block form. Its absolute value
    // is the number of records; the following long remains the block byte size.
    let record_count = if count < 0L { -count } else { count }
    let block_size = match reader.read_long() {
      Ok(value) => value
      Err(error) =>
        return Err(InvalidContainerBlock(Debug::to_repr(error).to_string()))
    }
    if block_size < 0L {
      return Err(InvalidContainerBlock("block size must not be negative"))
    }
    let size_int = block_size.to_int()
    if size_int.to_int64() != block_size {
      return Err(InvalidContainerBlock("block exceeds platform size"))
    }
    let block_bytes = match reader.read_exact(size_int) {
      Ok(value) => value
      Err(error) =>
        return Err(InvalidContainerBlock(Debug::to_repr(error).to_string()))
    }
    let block_reader = BinaryReader::new(block_bytes)
    let count_int = record_count.to_int()
    if count_int.to_int64() != record_count {
      return Err(InvalidContainerBlock("record count exceeds platform size"))
    }
    for record_index = 0
        record_index < count_int
        record_index = record_index + 1 {
      match decode_from(block_reader, schema) {
        Ok(value) => values.push(value)
        Err(error) => return Err(ContainerDecode(error))
      }
    }
    if !block_reader.is_finished() {
      return Err(InvalidContainerBlock("block contains trailing data"))
    }
    let block_sync = match reader.read_exact(16) {
      Ok(value) => value
      Err(_) => return Err(InvalidSyncMarker)
    }
    if block_sync != sync_marker {
      return Err(InvalidSyncMarker)
    }
  }
  Ok({ schema, metadata, sync_marker, values, })
}
