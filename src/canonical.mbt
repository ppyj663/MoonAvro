///|
fn canonical_quote(value : String) -> String {
  Json::string(value).stringify(escape_slash=false)
}

///|
fn write_canonical_schema(
  output : StringBuilder,
  document : SchemaDocument,
  schema : Schema,
  emitted : Map[String, Bool],
) -> Unit {
  match schema {
    Primitive(kind) => output.write_string(canonical_quote(kind.name()))
    NamedRef(name) => output.write_string(canonical_quote(name))
    Record(named, fields) =>
      if emitted.contains(named.full_name) {
        output.write_string(canonical_quote(named.full_name))
      } else {
        emitted.set(named.full_name, true)
        output.write_string("{\"name\":")
        output.write_string(canonical_quote(named.full_name))
        output.write_string(",\"type\":\"record\",\"fields\":[")
        for index, field in fields {
          if index > 0 {
            output.write_string(",")
          }
          output.write_string("{\"name\":")
          output.write_string(canonical_quote(field.name))
          output.write_string(",\"type\":")
          write_canonical_schema(output, document, field.schema, emitted)
          output.write_string("}")
        }
        output.write_string("]}")
      }
    Enum(named, symbols, _) =>
      if emitted.contains(named.full_name) {
        output.write_string(canonical_quote(named.full_name))
      } else {
        emitted.set(named.full_name, true)
        output.write_string("{\"name\":")
        output.write_string(canonical_quote(named.full_name))
        output.write_string(",\"type\":\"enum\",\"symbols\":[")
        for index, symbol in symbols {
          if index > 0 {
            output.write_string(",")
          }
          output.write_string(canonical_quote(symbol))
        }
        output.write_string("]}")
      }
    Fixed(named, size) =>
      if emitted.contains(named.full_name) {
        output.write_string(canonical_quote(named.full_name))
      } else {
        emitted.set(named.full_name, true)
        output.write_string("{\"name\":")
        output.write_string(canonical_quote(named.full_name))
        output.write_string(",\"type\":\"fixed\",\"size\":")
        output.write_string(size.to_string())
        output.write_string("}")
      }
    ArraySchema(items) => {
      output.write_string("{\"type\":\"array\",\"items\":")
      write_canonical_schema(output, document, items, emitted)
      output.write_string("}")
    }
    MapSchema(values) => {
      output.write_string("{\"type\":\"map\",\"values\":")
      write_canonical_schema(output, document, values, emitted)
      output.write_string("}")
    }
    Union(branches) => {
      output.write_string("[")
      for index, branch in branches {
        if index > 0 {
          output.write_string(",")
        }
        write_canonical_schema(output, document, branch, emitted)
      }
      output.write_string("]")
    }
  }
}

///|
/// Return the Avro parsing canonical form. Non-parsing attributes including
/// docs, aliases, defaults, namespace declarations, and field order are removed.
pub fn parsing_canonical_form(document : SchemaDocument) -> String {
  let output = StringBuilder()
  write_canonical_schema(output, document, document.root, Map([]))
  output.to_string()
}

///|
fn crc64_table() -> FixedArray[UInt64] {
  let table = FixedArray::make(256, 0UL)
  for index = 0; index < 256; index = index + 1 {
    let mut value = index.to_uint64()
    for bit = 0; bit < 8; bit = bit + 1 {
      value = if (value & 1UL) == 1UL {
        (value >> 1) ^ 0xc15d213aa4d7a795UL
      } else {
        value >> 1
      }
    }
    table[index] = value
  }
  table
}

///|
/// Compute the CRC-64-AVRO fingerprint used by Avro single-object encoding and
/// schema registries.
pub fn fingerprint64_bytes(data : BytesView) -> UInt64 {
  let table = crc64_table()
  let mut result = 0xc15d213aa4d7a795UL
  for byte in data {
    let index = ((result ^ byte.to_uint64()) & 0xffUL).to_int()
    result = (result >> 8) ^ table[index]
  }
  result
}

///|
pub fn schema_fingerprint64(document : SchemaDocument) -> UInt64 {
  fingerprint64_bytes(@utf8.encode(parsing_canonical_form(document))[:])
}

///|
pub fn fingerprint64_hex(value : UInt64) -> String {
  let raw = value.to_string(radix=16)
  if raw.length() >= 16 {
    raw
  } else {
    "0".repeat(16 - raw.length()) + raw
  }
}

///|
/// Single-object encoding prefix: C3 01 followed by little-endian fingerprint.
pub fn encode_single_object(
  document : SchemaDocument,
  value : Value,
) -> Result[Bytes, EncodeError] {
  let datum = match encode(document, value) {
    Ok(bytes) => bytes
    Err(error) => return Err(error)
  }
  let output = BinaryWriter::new()
  output.write_raw(b"\xc3\x01"[:])
  let fingerprint = schema_fingerprint64(document)
  for shift = 0; shift < 64; shift = shift + 8 {
    output.write_byte((fingerprint >> shift).to_byte())
  }
  output.write_raw(datum[:])
  Ok(output.finish())
}

///|
pub(all) suberror SingleObjectError {
  InvalidSingleObjectHeader
  FingerprintMismatch(UInt64, UInt64)
  SingleObjectDecode(DecodeError)
} derive(Eq, Debug)

///|
pub fn decode_single_object(
  document : SchemaDocument,
  data : Bytes,
) -> Result[Value, SingleObjectError] {
  if data.length() < 10 || data[0] != b'\xc3' || data[1] != b'\x01' {
    return Err(InvalidSingleObjectHeader)
  }
  let actual = data.unsafe_read_uint64_le(2)
  let expected = schema_fingerprint64(document)
  if actual != expected {
    return Err(FingerprintMismatch(expected, actual))
  }
  match decode(document, data[10:].to_owned()) {
    Ok(value) => Ok(value)
    Err(error) => Err(SingleObjectDecode(error))
  }
}
