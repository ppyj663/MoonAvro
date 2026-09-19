# MoonAvro

MoonBit-native Apache Avro binary encoding, decoding, and schema evolution.

> Status: active development for the September 2026 MoonBit Hackathon.

MoonAvro is a reusable protocol library rather than an application-specific
wrapper. It aims to make Avro data exchange available to MoonBit programs on
both JavaScript and WebAssembly-GC targets.

## Planned MVP

- Parse Avro JSON schemas for primitive, record, enum, fixed, array, map, and
  union types.
- Encode and decode the Avro binary data format with strict bounds checking.
- Resolve writer data into a compatible reader schema, including aliases,
  defaults, field reordering, and numeric promotion.
- Generate parsing canonical form and CRC-64-AVRO fingerprints.
- Read and write Avro object container files using the `null` codec.
- Provide a CLI, runnable examples, fixtures, and cross-target tests.

The public API and usage documentation will be expanded as each milestone is
implemented. See [the design](docs/plans/2026-09-19-moonavro-design.md) and
[the implementation plan](docs/plans/2026-09-19-moonavro-mvp.md).

## License

Apache-2.0. Apache Avro is a trademark of The Apache Software Foundation.
