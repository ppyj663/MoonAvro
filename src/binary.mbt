///|
/// Append-only buffer for Avro's binary encoding.
pub(all) struct BinaryWriter {
  buffer : Buffer
}

///|
pub fn BinaryWriter::new() -> BinaryWriter {
  { buffer: Buffer(), }
}

///|
pub fn BinaryWriter::length(self : BinaryWriter) -> Int {
  self.buffer.length()
}

///|
pub fn BinaryWriter::write_byte(self : BinaryWriter, value : Byte) -> Unit {
  self.buffer.write_byte(value)
}

///|
pub fn BinaryWriter::write_raw(self : BinaryWriter, value : BytesView) -> Unit {
  self.buffer.write_bytes(value)
}

///|
pub fn BinaryWriter::write_boolean(self : BinaryWriter, value : Bool) -> Unit {
  self.write_byte(if value { b'\x01' } else { b'\x00' })
}

///|
pub fn BinaryWriter::write_long(self : BinaryWriter, value : Int64) -> Unit {
  let mut encoded = ((value << 1) ^ (value >> 63)).reinterpret_as_uint64()
  while encoded >= 0x80UL {
    self.write_byte(((encoded & 0x7fUL) | 0x80UL).to_byte())
    encoded = encoded >> 7
  }
  self.write_byte(encoded.to_byte())
}

///|
pub fn BinaryWriter::write_int(self : BinaryWriter, value : Int) -> Unit {
  self.write_long(value.to_int64())
}

///|
pub fn BinaryWriter::write_float(self : BinaryWriter, value : Float) -> Unit {
  self.buffer.write_float_le(value)
}

///|
pub fn BinaryWriter::write_double(self : BinaryWriter, value : Double) -> Unit {
  self.buffer.write_double_le(value)
}

///|
pub fn BinaryWriter::write_bytes(self : BinaryWriter, value : Bytes) -> Unit {
  self.write_long(value.length().to_int64())
  self.write_raw(value[:])
}

///|
pub fn BinaryWriter::write_string(self : BinaryWriter, value : String) -> Unit {
  self.write_bytes(@utf8.encode(value))
}

///|
pub fn BinaryWriter::finish(self : BinaryWriter) -> Bytes {
  self.buffer.to_bytes()
}

///|
/// Bounds-checked cursor over Avro binary input.
pub(all) struct BinaryReader {
  data : Bytes
  mut position : Int
}

///|
pub fn BinaryReader::new(data : Bytes) -> BinaryReader {
  { data, position: 0, }
}

///|
pub fn BinaryReader::offset(self : BinaryReader) -> Int {
  self.position
}

///|
pub fn BinaryReader::remaining(self : BinaryReader) -> Int {
  self.data.length() - self.position
}

///|
pub fn BinaryReader::is_finished(self : BinaryReader) -> Bool {
  self.position == self.data.length()
}

///|
pub fn BinaryReader::read_byte(
  self : BinaryReader,
) -> Result[Byte, DecodeError] {
  if self.position >= self.data.length() {
    return Err(UnexpectedEof(self.position, 1))
  }
  let value = self.data[self.position]
  self.position += 1
  Ok(value)
}

///|
pub fn BinaryReader::read_exact(
  self : BinaryReader,
  count : Int,
) -> Result[Bytes, DecodeError] {
  if count < 0 || self.position + count > self.data.length() {
    return Err(UnexpectedEof(self.position, count))
  }
  let result = self.data[self.position:self.position + count].to_owned()
  self.position += count
  Ok(result)
}

///|
pub fn BinaryReader::skip(
  self : BinaryReader,
  count : Int,
) -> Result[Unit, DecodeError] {
  match self.read_exact(count) {
    Ok(_) => Ok(())
    Err(error) => Err(error)
  }
}

///|
pub fn BinaryReader::read_long(
  self : BinaryReader,
) -> Result[Int64, DecodeError] {
  let start = self.position
  let mut raw = 0UL
  let mut shift = 0
  while shift < 70 {
    let byte = match self.read_byte() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let part = byte.to_uint64() & 0x7fUL
    if shift == 63 && part > 1UL {
      return Err(InvalidVarint(start))
    }
    raw = raw | (part << shift)
    if (byte.to_int() & 0x80) == 0 {
      let magnitude = (raw >> 1).reinterpret_as_int64()
      return Ok(if (raw & 1UL) == 0UL { magnitude } else { -magnitude - 1L })
    }
    shift += 7
  }
  Err(InvalidVarint(start))
}

///|
pub fn BinaryReader::read_int(self : BinaryReader) -> Result[Int, DecodeError] {
  match self.read_long() {
    Ok(value) => {
      let converted = value.to_int()
      if converted.to_int64() != value {
        Err(LengthOverflow(AvroPath::root(), value))
      } else {
        Ok(converted)
      }
    }
    Err(error) => Err(error)
  }
}

///|
pub fn BinaryReader::read_boolean(
  self : BinaryReader,
) -> Result[Bool, DecodeError] {
  match self.read_byte() {
    Ok(b'\x00') => Ok(false)
    Ok(b'\x01') => Ok(true)
    Ok(value) => Err(InvalidBoolean(AvroPath::root(), value))
    Err(error) => Err(error)
  }
}

///|
pub fn BinaryReader::read_float(
  self : BinaryReader,
) -> Result[Float, DecodeError] {
  if self.remaining() < 4 {
    return Err(UnexpectedEof(self.position, 4))
  }
  let bits = self.data.unsafe_read_uint32_le(self.position)
  self.position += 4
  Ok(bits.reinterpret_as_float())
}

///|
pub fn BinaryReader::read_double(
  self : BinaryReader,
) -> Result[Double, DecodeError] {
  if self.remaining() < 8 {
    return Err(UnexpectedEof(self.position, 8))
  }
  let bits = self.data.unsafe_read_uint64_le(self.position)
  self.position += 8
  Ok(bits.reinterpret_as_double())
}

///|
pub fn BinaryReader::read_length(
  self : BinaryReader,
  path : AvroPath,
) -> Result[Int, DecodeError] {
  match self.read_long() {
    Ok(value) => {
      if value < 0L {
        return Err(NegativeLength(path, value))
      }
      let length = value.to_int()
      if length.to_int64() != value {
        Err(LengthOverflow(path, value))
      } else {
        Ok(length)
      }
    }
    Err(error) => Err(error)
  }
}

///|
pub fn BinaryReader::read_bytes(
  self : BinaryReader,
  path : AvroPath,
) -> Result[Bytes, DecodeError] {
  match self.read_length(path) {
    Ok(length) => self.read_exact(length)
    Err(error) => Err(error)
  }
}

///|
pub fn BinaryReader::read_string(
  self : BinaryReader,
  path : AvroPath,
) -> Result[String, DecodeError] {
  let bytes = match self.read_bytes(path) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let decoded = @utf8.decode(bytes[:]) catch {
    _ => return Err(InvalidUtf8(path))
  }
  Ok(decoded)
}

///|
pub fn encode_long(value : Int64) -> Bytes {
  let writer = BinaryWriter::new()
  writer.write_long(value)
  writer.finish()
}

///|
pub fn decode_long(data : Bytes) -> Result[Int64, DecodeError] {
  let reader = BinaryReader::new(data)
  match reader.read_long() {
    Ok(value) =>
      if reader.is_finished() {
        Ok(value)
      } else {
        Err(TrailingData(reader.remaining()))
      }
    Err(error) => Err(error)
  }
}
