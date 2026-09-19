# MoonAvro MVP Design

## Product boundary

MoonAvro is a native MoonBit library for Apache Avro. It owns schema parsing,
binary data encoding and decoding, schema compatibility and resolution,
fingerprinting, and uncompressed object container files. It does not implement
Kafka, a schema registry server, RPC transport, or compression codecs in the
MVP. Those are downstream integrations and future milestones.

This boundary makes the project useful to multiple consumers: event pipelines,
data import/export tools, browser or Wasm applications, and future MoonBit
Kafka or registry clients can all depend on the same codec package.

## Architecture

The `src` package exposes an algebraic `Schema` model and a matching dynamic
`Value` model. A schema parser converts Avro JSON into validated named types,
tracking namespaces, aliases, duplicate definitions, and recursive references.
The encoder and decoder walk schema and value together over small byte writer
and cursor abstractions. Every failure returns a typed error with a logical
path; malformed input never relies on unchecked indexing.

Schema evolution is a separate resolution layer. It builds a reusable plan
from writer and reader schemas, then applies that plan while decoding. Plans
cover record field reordering, reader defaults, aliases, primitive promotion,
enum symbol checks, fixed-size compatibility, and union branch selection.
Separating plan construction from execution makes compatibility errors visible
before consuming a data stream and allows repeated records to reuse work.

Object container file support composes existing pieces: a header with embedded
schema and metadata, deterministic sync marker support for tests, and blocks of
binary records. The MVP supports the required `null` codec; compression remains
an extension point. Canonical form and CRC-64-AVRO fingerprinting operate on
the parsed schema model so spelling differences do not change identity.

## Data flow and errors

Library calls follow `schema text -> parsed Schema -> Value <-> bytes`. For
evolution the path is `writer schema + reader schema -> ResolutionPlan`, then
`writer bytes -> decoded/resolved reader Value`. Container files add a thin
block framing layer around the same binary codec.

Errors are grouped by stage: schema syntax/validation, value/schema mismatch,
binary truncation or invalid block lengths, incompatible schema evolution, and
container corruption. Each error carries enough context to display a useful
CLI message without string matching.

## Validation strategy

Unit tests cover primitive boundary vectors, compound values, malformed bytes,
named-schema parsing, every supported resolution rule, canonical form, known
fingerprints, and container round trips. Integration fixtures use JSON schema
and datum files. The same suite runs on JavaScript and Wasm-GC. CI additionally
runs formatting, static checks, documentation generation, and an end-to-end CLI
round trip. Effective MoonBit source, tests, and examples will exceed 4,000
lines without counting build output or generated metadata.
