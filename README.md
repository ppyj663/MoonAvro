# MoonAvro

MoonAvro is a MoonBit-native Apache Avro schema, binary codec, and schema
evolution library. It is being developed in public for the September 2026
MoonBit Hackathon.

The goal is to make Avro data usable from MoonBit programs on JavaScript and
WebAssembly-GC without requiring a JVM bridge. The library owns schema
validation, wire encoding, compatibility checks, and container framing; it is
not a schema registry, Kafka client, or RPC runtime.

## MVP capabilities

| Area | Supported in the MVP |
| --- | --- |
| Schema JSON | `null`, `boolean`, `int`, `long`, `float`, `double`, `bytes`, `string`, records, enums, fixed, arrays, maps, unions, namespaces, validated aliases, recursive named references, field defaults |
| Avro binary | Primitive and compound datum encoding/decoding; checked lengths, malformed varints, invalid indexes, UTF-8 and trailing-data errors |
| Evolution | Writer-to-reader compatibility diagnostics and datum resolution; record reordering, reader defaults, aliases, enum defaults, unions, and Avro numeric promotions |
| Identity | Parsing Canonical Form, CRC-64-AVRO fingerprint, and single-object encoding |
| Object container | OCF header and configurable multi-record blocks with embedded full writer schema; `null` codec |
| JSON data | Schema-aware conversion between `Value` and Avro JSON datum encoding |
| Targets | Shared library tests on JavaScript and WebAssembly-GC |

This is a deliberately bounded MVP, not a claim of complete Apache Avro
feature parity. OCF compression codecs other than `null` (including `deflate`)
and logical types are not implemented yet. The CLI uses Node.js filesystem
APIs and is JavaScript-only; the reusable `src` package is the cross-target
component.

## Quick start

Add the library to a MoonBit project after it is available through the MoonBit
package registry, then import `ppyj663/moonavro/src` as `@avro`. To work from
this repository before registry publication, run its examples and tests
directly with the MoonBit toolchain.

```moonbit
import { "ppyj663/moonavro/src" @avro }

let schema = match @avro.parse_schema(
  #|{"type":"record","name":"User","fields":[
  #|  {"name":"id","type":"long"},
  #|  {"name":"name","type":"string"}
  #|]}
) {
  Ok(document) => document
  Err(error) => abort("invalid schema: " + Debug::to_repr(error).to_string())
}

let user = @avro.RecordValue([
  ("id", @avro.LongValue(42L)),
  ("name", @avro.StringValue("MoonBit")),
])
let bytes = match @avro.encode(schema, user) {
  Ok(bytes) => bytes
  Err(error) => abort("encode failed: " + Debug::to_repr(error).to_string())
}
let decoded = match @avro.decode(schema, bytes) {
  Ok(value) => value
  Err(error) => abort("decode failed: " + Debug::to_repr(error).to_string())
}
```

The example is also available as a runnable program:

```sh
moon run examples/basic --target js
```

The public API is documented in [README.mbt.md](README.mbt.md). The design and
implementation milestones are tracked in [the design](docs/plans/2026-09-19-moonavro-design.md)
and [the MVP plan](docs/plans/2026-09-19-moonavro-mvp.md).

## CLI

The Node.js CLI accepts Avro schema files (`.avsc`) and Avro JSON datum files.
All paths below are relative to the repository root:

```sh
moon run cmd/moonavro --target js -- inspect fixtures/user.avsc
moon run cmd/moonavro --target js -- canonical fixtures/user.avsc
moon run cmd/moonavro --target js -- compatible fixtures/user.avsc fixtures/user.avsc
moon run cmd/moonavro --target js -- encode fixtures/user.avsc fixtures/user.json _build/user.bin
moon run cmd/moonavro --target js -- decode fixtures/user.avsc _build/user.bin
moon run cmd/moonavro --target js -- decode-resolved fixtures/user.avsc fixtures/user-v2.avsc _build/user.bin
moon run cmd/moonavro --target js -- pack fixtures/user.avsc fixtures/user.json _build/user.avro
moon run cmd/moonavro --target js -- unpack _build/user.avro
```

`compatible` exits with status `0` for compatible schemas, `1` for an
incompatibility, and `2` for invalid command input or file I/O. `encode` writes
the raw Avro datum bytes; `pack` writes a one-record OCF file.
`decode-resolved` decodes with the writer schema, applies the reader schema,
then emits the upgraded datum as JSON.

## Development and verification

Install the MoonBit CLI, resolve the package, and run the checks:

```sh
moon update
moon fmt --check
moon check --target js
moon test --target js
moon check --target wasm-gc
moon test --target wasm-gc
moon info
```

CI runs formatting, type checks, and the full test suite on both targets. Tests
cover Apache wire vectors, malformed input, schema parsing, resolution,
fingerprints, JSON datums, and OCF round trips. For contribution workflow, see
[CONTRIBUTING.md](CONTRIBUTING.md); for vulnerability reports, see
[SECURITY.md](SECURITY.md).

## Public development

MoonAvro is developed in the open. MVP scope and follow-up work are tracked in
the repository's GitHub Issues; behavior changes should include a specification
reference or interoperability vector and a regression test. The project is
organized as a MoonBit library first, with the CLI and examples exercising the
same public APIs.

## License and names

MoonAvro is distributed under the [Apache License 2.0](LICENSE). “Apache Avro”
is a project name of The Apache Software Foundation; MoonAvro is an independent
implementation and is not affiliated with the Foundation.
