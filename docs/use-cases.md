# MoonAvro use cases

The examples below are runnable programs, not pseudocode. They exercise the
same public library API used by the CLI and test suite.

## 1. Encode application events

Use `examples/basic` to encode and decode a typed record for a service boundary
or event producer. The schema is explicit, and the resulting bytes are standard
Avro binary data.

```sh
moon run examples/basic --target js
```

## 2. Read historical events with a newer schema

Use `examples/evolution` when a consumer has a newer reader schema than the
writer schema used to persist an event. The example exercises a record alias,
field reordering, `long` to `double` promotion, and a reader default.

```sh
moon run examples/evolution --target js
```

## 3. Archive batches in an Avro object container

Use `examples/container` to group measurements into an OCF file with its full
writer schema embedded in the header. The example requests blocks of two
records, writes three records, reads both blocks back, and renders each datum.

```sh
moon run examples/container --target js
```

The current OCF implementation supports the `null` codec. Compressed codecs,
logical types, Kafka transport, and schema registry operations are explicitly
outside the MVP.
