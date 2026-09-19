///|
fn decode_array_block_count(
  reader : BinaryReader,
  path : AvroPath,
) -> Result[(Int, Int64?), DecodeError] {
  let raw = match reader.read_long() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if raw == 0L {
    return Ok((0, None))
  }
  if raw > 0L {
    let count = raw.to_int()
    if count.to_int64() != raw {
      return Err(LengthOverflow(path, raw))
    }
    return Ok((count, None))
  }
  if raw == -9223372036854775808L {
    return Err(InvalidBlockCount(path, raw))
  }
  let positive = -raw
  let count = positive.to_int()
  if count.to_int64() != positive {
    return Err(LengthOverflow(path, positive))
  }
  let block_size = match reader.read_long() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if block_size < 0L {
    return Err(NegativeLength(path, block_size))
  }
  Ok((count, Some(block_size)))
}

///|
fn decode_schema_value(
  reader : BinaryReader,
  document : SchemaDocument,
  schema : Schema,
  path : AvroPath,
) -> Result[Value, DecodeError] {
  match schema {
    Primitive(Null) => Ok(NullValue)
    Primitive(Boolean) =>
      match reader.read_boolean() {
        Ok(value) => Ok(BooleanValue(value))
        Err(InvalidBoolean(_, byte)) => Err(InvalidBoolean(path, byte))
        Err(error) => Err(error)
      }
    Primitive(Int) =>
      match reader.read_int() {
        Ok(value) => Ok(IntValue(value))
        Err(error) => Err(error)
      }
    Primitive(Long) =>
      match reader.read_long() {
        Ok(value) => Ok(LongValue(value))
        Err(error) => Err(error)
      }
    Primitive(Float) =>
      match reader.read_float() {
        Ok(value) => Ok(FloatValue(value))
        Err(error) => Err(error)
      }
    Primitive(Double) =>
      match reader.read_double() {
        Ok(value) => Ok(DoubleValue(value))
        Err(error) => Err(error)
      }
    Primitive(Bytes) =>
      match reader.read_bytes(path) {
        Ok(value) => Ok(BytesValue(value))
        Err(error) => Err(error)
      }
    Primitive(String) =>
      match reader.read_string(path) {
        Ok(value) => Ok(StringValue(value))
        Err(error) => Err(error)
      }
    Record(_, fields) => {
      let entries : Array[(String, Value)] = []
      for field in fields {
        match
          decode_schema_value(
            reader,
            document,
            field.schema,
            path.field(field.name),
          ) {
          Ok(value) => entries.push((field.name, value))
          Err(error) => return Err(error)
        }
      }
      Ok(RecordValue(entries))
    }
    Enum(_, symbols, _) => {
      let index = match reader.read_int() {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      if index < 0 || index >= symbols.length() {
        Err(InvalidEnumIndex(path, index, symbols.length()))
      } else {
        Ok(EnumValue(symbols[index]))
      }
    }
    ArraySchema(items) => {
      let values : Array[Value] = []
      while true {
        let (count, block_size) = match decode_array_block_count(reader, path) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        if count == 0 {
          break
        }
        let block_start = reader.offset()
        for item_index = 0; item_index < count; item_index = item_index + 1 {
          let index = values.length()
          match
            decode_schema_value(reader, document, items, path.index(index)) {
            Ok(value) => values.push(value)
            Err(error) => return Err(error)
          }
        }
        match block_size {
          Some(expected) => {
            let consumed = reader.offset() - block_start
            if consumed.to_int64() != expected {
              return Err(BlockSizeMismatch(path, expected, consumed))
            }
          }
          None => ()
        }
      }
      Ok(ArrayValue(values))
    }
    MapSchema(values_schema) => {
      let entries : Array[(String, Value)] = []
      while true {
        let (count, block_size) = match decode_array_block_count(reader, path) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        if count == 0 {
          break
        }
        let block_start = reader.offset()
        for entry_index = 0; entry_index < count; entry_index = entry_index + 1 {
          let key = match reader.read_string(path) {
            Ok(value) => value
            Err(error) => return Err(error)
          }
          match
            decode_schema_value(
              reader,
              document,
              values_schema,
              path.field(key),
            ) {
            Ok(value) => entries.push((key, value))
            Err(error) => return Err(error)
          }
        }
        match block_size {
          Some(expected) => {
            let consumed = reader.offset() - block_start
            if consumed.to_int64() != expected {
              return Err(BlockSizeMismatch(path, expected, consumed))
            }
          }
          None => ()
        }
      }
      Ok(MapValue(entries))
    }
    Union(branches) => {
      let index = match reader.read_int() {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      if index < 0 || index >= branches.length() {
        return Err(InvalidUnionIndex(path, index, branches.length()))
      }
      match
        decode_schema_value(
          reader,
          document,
          branches[index],
          path.index(index),
        ) {
        Ok(value) => Ok(UnionValue(index, value))
        Err(error) => Err(error)
      }
    }
    Fixed(_, size) =>
      match reader.read_exact(size) {
        Ok(value) => Ok(FixedValue(value))
        Err(error) => Err(error)
      }
    NamedRef(name) =>
      match document.definition(name) {
        Some(target) => decode_schema_value(reader, document, target, path)
        None => Err(UnresolvedDecodeName(path, name))
      }
  }
}

///|
/// Decode exactly one datum and reject any trailing bytes.
pub fn decode(
  document : SchemaDocument,
  bytes : Bytes,
) -> Result[Value, DecodeError] {
  let reader = BinaryReader::new(bytes)
  let value = match
    decode_schema_value(reader, document, document.root, AvroPath::root()) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if !reader.is_finished() {
    Err(TrailingData(reader.remaining()))
  } else {
    Ok(value)
  }
}

///|
/// Decode one datum from a shared reader, leaving subsequent bytes untouched.
pub fn decode_from(
  reader : BinaryReader,
  document : SchemaDocument,
) -> Result[Value, DecodeError] {
  decode_schema_value(reader, document, document.root, AvroPath::root())
}

///|
pub fn decode_with_schema(
  reader : BinaryReader,
  document : SchemaDocument,
  schema : Schema,
) -> Result[Value, DecodeError] {
  decode_schema_value(reader, document, schema, AvroPath::root())
}
