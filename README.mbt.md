# MoonAvro API guide

MoonAvro exposes an Avro schema model and dynamic datum model from
`ppyj663/moonavro/src`. The library is written in MoonBit and has no dependency
on Node.js in its core package.

## Parse a schema and encode a value

```moonbit nocheck
///|
import {
  "ppyj663/moonavro/src" @avro,
}

///|
let schema_text =
  #|{"type":"record","name":"Event","namespace":"demo","fields":[
  #|  {"name":"id","type":"long"},
  #|  {"name":"message","type":"string"},
  #|  {"name":"tags","type":{"type":"array","items":"string"}}
  #|]}

///|
let schema = match @avro.parse_schema(schema_text) {
  Ok(document) => document
  Err(error) =>
    abort("invalid Avro schema: " + Debug::to_repr(error).to_string())
}

///|
let event = @avro.RecordValue([
  ("id", @avro.LongValue(7L)),
  ("message", @avro.StringValue("ready")),
  ("tags", @avro.ArrayValue([@avro.StringValue("worker")])),
])

///|
let bytes = match @avro.encode(schema, event) {
  Ok(bytes) => bytes
  Err(error) => abort("invalid datum: " + Debug::to_repr(error).to_string())
}

///|
let decoded = match @avro.decode(schema, bytes) {
  Ok(value) => value
  Err(error) =>
    abort("invalid Avro bytes: " + Debug::to_repr(error).to_string())
}
```

`parse_schema` returns a `SchemaDocument`: the root schema plus a name-indexed
table of named record, enum, and fixed definitions. Recursive types use
`Schema::NamedRef` entries rather than infinitely recursive MoonBit values.
`Value` mirrors the Avro datum model (`RecordValue`, `ArrayValue`, `MapValue`,
`UnionValue`, and the primitive variants).

## JSON data and schema evolution

Avro JSON datum encoding is schema-directed, which is important for unions,
bytes, and fixed values:

```moonbit nocheck
///|
let value = match
  @avro.value_from_json(
    schema, "{\"id\":7,\"message\":\"ready\",\"tags\":[\"worker\"]}",
  ) {
  Ok(value) => value
  Err(error) =>
    abort("invalid JSON datum: " + Debug::to_repr(error).to_string())
}

///|
let json = @avro.value_to_json_string(schema, value, pretty=true)
```

Check a writer schema against a reader schema before resolving data. The
compatibility report contains all discovered issues with Avro paths; resolved
decoding performs both steps for a single datum:

```moonbit nocheck
///|
let report = @avro.check_compatibility(writer_schema, reader_schema)

///|
let value = @avro.decode_resolved(writer_schema, reader_schema, bytes)
```

Resolution supports reader field defaults, field and named-type aliases,
record field order changes, numeric promotions, enum symbol defaults, and
union branches. It returns a typed `ResolutionError` when no valid reader
interpretation exists.

## Fingerprints and container files

`parsing_canonical_form` removes metadata that does not participate in schema
identity; `schema_to_json` instead preserves reader-relevant defaults, aliases,
docs, and field order metadata. `schema_fingerprint64` computes Avro's
CRC-64-AVRO fingerprint. `encode_single_object` and `decode_single_object`
implement the Avro single-object envelope.

`write_container` and `read_container` read and write Avro Object Container
Files with embedded full writer schemas and the `null` codec. Other compression
codecs and logical types are outside the current MVP.

## Typed errors

Library operations return `Result` values. Errors are separated by stage:
`SchemaError`, `EncodeError`, `DecodeError`, `ResolutionError`,
`DatumJsonError`, and `ContainerError`. Paths use `AvroPath`, allowing callers
to present structured diagnostics without parsing error strings.

For a runnable end-to-end example and CLI workflows, see the repository
[README](README.md). The source API is tested on JavaScript and WebAssembly-GC.
