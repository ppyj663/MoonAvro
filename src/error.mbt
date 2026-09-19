///|
/// A location inside a schema or datum. Segments are stored independently so
/// callers can render them for a CLI, editor, or structured diagnostic.
pub(all) struct AvroPath {
  segments : Array[String]
} derive(Eq, Debug)

///|
pub fn AvroPath::root() -> AvroPath {
  { segments: [], }
}

///|
pub fn AvroPath::field(self : AvroPath, name : String) -> AvroPath {
  let next = self.segments.copy()
  next.push(name)
  { segments: next, }
}

///|
pub fn AvroPath::index(self : AvroPath, index : Int) -> AvroPath {
  self.field("[" + index.to_string() + "]")
}

///|
pub fn AvroPath::to_string(self : AvroPath) -> String {
  if self.segments.is_empty() {
    "$"
  } else {
    let buffer = StringBuilder::new()
    buffer.write_string("$")
    for segment in self.segments {
      if segment.has_prefix("[") {
        buffer.write_string(segment)
      } else {
        buffer.write_string(".")
        buffer.write_string(segment)
      }
    }
    buffer.to_string()
  }
}

///|
/// Schema parsing and validation failures.
pub(all) suberror SchemaError {
  InvalidJson(String)
  InvalidSchema(AvroPath, String)
  MissingProperty(AvroPath, String)
  InvalidProperty(AvroPath, String, String)
  InvalidName(AvroPath, String)
  DuplicateName(AvroPath, String)
  DuplicateField(AvroPath, String)
  DuplicateSymbol(AvroPath, String)
  DuplicateUnionBranch(AvroPath, String)
  NestedUnion(AvroPath)
  UnknownReference(AvroPath, String)
  InvalidDefault(AvroPath, String)
} derive(Eq, Debug)

///|
/// A value did not match the schema supplied to the encoder.
pub(all) suberror EncodeError {
  ValueMismatch(AvroPath, String, String)
  MissingFieldValue(AvroPath, String)
  UnknownEnumSymbol(AvroPath, String)
  InvalidUnionBranch(AvroPath, Int)
  FixedSizeMismatch(AvroPath, Int, Int)
  UnresolvedName(AvroPath, String)
  SizeOverflow(AvroPath, String)
} derive(Eq, Debug)

///|
/// Malformed or truncated Avro binary input.
pub(all) suberror DecodeError {
  UnexpectedEof(Int, Int)
  InvalidVarint(Int)
  NegativeLength(AvroPath, Int64)
  LengthOverflow(AvroPath, Int64)
  InvalidUtf8(AvroPath)
  InvalidBoolean(AvroPath, Byte)
  InvalidEnumIndex(AvroPath, Int, Int)
  InvalidUnionIndex(AvroPath, Int, Int)
  InvalidBlockCount(AvroPath, Int64)
  BlockSizeMismatch(AvroPath, Int64, Int)
  TrailingData(Int)
  UnresolvedDecodeName(AvroPath, String)
} derive(Eq, Debug)

///|
/// Writer and reader schemas cannot be reconciled under Avro resolution rules.
pub(all) suberror ResolutionError {
  Incompatible(AvroPath, String, String)
  MissingReaderDefault(AvroPath, String)
  AmbiguousAlias(AvroPath, String)
  MissingEnumDefault(AvroPath, String)
  NoMatchingUnionBranch(AvroPath, String)
  InvalidResolvedValue(AvroPath, String)
} derive(Eq, Debug)

///|
/// Object container file framing failures.
pub(all) suberror ContainerError {
  InvalidMagic
  MissingSchemaMetadata
  UnsupportedCodec(String)
  InvalidSyncMarker
  InvalidMetadata(String)
  InvalidContainerBlock(String)
  ContainerSchema(SchemaError)
  ContainerEncode(EncodeError)
  ContainerDecode(DecodeError)
} derive(Eq, Debug)
