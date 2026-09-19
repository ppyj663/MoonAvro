# Changelog

## 0.1.0 - 2026-09-19

- Added Avro JSON schema parsing and validation.
- Added binary encoding and decoding for primitive and compound types.
- Added writer/reader schema compatibility and value resolution.
- Added parsing canonical form and CRC-64-AVRO fingerprints.
- Added single-object encoding and null-codec object container files.
- Added Avro JSON datum conversion, CLI workflows, fixtures, and examples.
- Preserved full writer schema metadata in object container headers.
- Added named-union JSON labels and size-prefixed OCF block interoperability.
- Added CLI decoding with distinct writer and reader schemas.
- Added configurable OCF block sizing for multi-block output.
- Reject malformed or duplicated named-type and record-field aliases.
