///|
test "encode apache avro zig-zag examples" {
  let cases = [
    (0L, b"\x00"),
    (-1L, b"\x01"),
    (1L, b"\x02"),
    (-2L, b"\x03"),
    (2L, b"\x04"),
    (64L, b"\x80\x01"),
    (-64L, b"\x7f"),
    (-65L, b"\x81\x01"),
    (8192L, b"\x80\x80\x01"),
  ]
  for (value, expected) in cases {
    assert_eq(@moonavro.encode_long(value), expected)
    assert_eq(@moonavro.decode_long(expected), Ok(value))
  }
}

///|
test "round trip full signed long range" {
  let values = [
    -9223372036854775808L, -9223372036854775807L, -2147483648L, -1L, 0L, 1L, 2147483647L,
    9223372036854775807L,
  ]
  for value in values {
    assert_eq(@moonavro.decode_long(@moonavro.encode_long(value)), Ok(value))
  }
}

///|
test "reject truncated and overlong varints" {
  guard @moonavro.decode_long(b"\x80") is Err(@moonavro.UnexpectedEof(_, _)) else {
    fail("truncated varint accepted")
  }
  guard @moonavro.decode_long(b"\x80\x80\x80\x80\x80\x80\x80\x80\x80\x02")
    is Err(@moonavro.InvalidVarint(_)) else {
    fail("overflowing varint accepted")
  }
}

///|
test "binary primitive writer and reader" {
  let writer = @moonavro.BinaryWriter::new()
  writer.write_boolean(true)
  writer.write_boolean(false)
  writer.write_int(-12)
  writer.write_long(9001L)
  writer.write_float(1.5F)
  writer.write_double(-3.25)
  writer.write_bytes(b"\x00\xff")
  writer.write_string("MoonBit 月兔")
  let reader = @moonavro.BinaryReader::new(writer.finish())
  assert_eq(reader.read_boolean(), Ok(true))
  assert_eq(reader.read_boolean(), Ok(false))
  assert_eq(reader.read_int(), Ok(-12))
  assert_eq(reader.read_long(), Ok(9001L))
  assert_eq(reader.read_float(), Ok(1.5F))
  assert_eq(reader.read_double(), Ok(-3.25))
  assert_eq(reader.read_bytes(@moonavro.AvroPath::root()), Ok(b"\x00\xff"))
  assert_eq(
    reader.read_string(@moonavro.AvroPath::root()),
    Ok("MoonBit 月兔"),
  )
  assert_true(reader.is_finished())
}

///|
test "reject invalid boolean and utf8" {
  let boolean_reader = @moonavro.BinaryReader::new(b"\x02")
  guard boolean_reader.read_boolean()
    is Err(@moonavro.InvalidBoolean(_, b'\x02')) else {
    fail("invalid boolean accepted")
  }
  let string_reader = @moonavro.BinaryReader::new(b"\x02\xff")
  guard string_reader.read_string(@moonavro.AvroPath::root())
    is Err(@moonavro.InvalidUtf8(_)) else {
    fail("invalid utf8 accepted")
  }
}

///|
test "reject negative byte length" {
  let reader = @moonavro.BinaryReader::new(b"\x01")
  guard reader.read_bytes(@moonavro.AvroPath::root())
    is Err(@moonavro.NegativeLength(_, -1L)) else {
    fail("negative length accepted")
  }
}
