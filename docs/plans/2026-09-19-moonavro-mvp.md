# MoonAvro MVP Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a production-oriented MoonBit Apache Avro codec and schema evolution MVP with more than 4,000 lines of effective code, tests, and examples.

**Architecture:** A single reusable library package models schemas and values, then composes parser, binary codec, resolution, canonicalization, fingerprinting, and object-container modules. A thin CLI and fixture-driven examples exercise the same public APIs on JS and Wasm-GC.

**Tech Stack:** MoonBit, MoonBit core JSON/encoding libraries, GitHub Actions, Apache Avro 1.12 specification test vectors.

---

### Task 1: Repository and public data model

**Files:** Create `moon.mod`, `src/moon.pkg`, `src/schema.mbt`, `src/value.mbt`, tests, docs, and CI.

1. Add failing construction and validation tests for primitive and named schemas.
2. Implement typed schema/value models, names, fields, defaults, aliases, and errors.
3. Run `moon fmt`, `moon check`, and tests on JS and Wasm-GC.
4. Commit and push the milestone.

### Task 2: JSON schema parser

**Files:** Create `src/schema_parser.mbt` and `src/schema_parser_test.mbt`.

1. Add tests for every supported Avro schema form and invalid definitions.
2. Implement namespace-aware parsing, named references, recursive records, and defaults.
3. Verify parsing fixtures and both compilation targets.
4. Commit and push the milestone.

### Task 3: Binary codec

**Files:** Create `src/binary.mbt`, `src/encode.mbt`, `src/decode.mbt`, and tests.

1. Add Apache-compatible vectors for zig-zag varints, floats, strings, bytes, arrays, maps, unions, enums, fixed, and records.
2. Implement checked byte writer/cursor primitives and schema-directed codec logic.
3. Add malformed input and value mismatch tests.
4. Run all tests, commit, and push.

### Task 4: Schema evolution

**Files:** Create `src/resolution.mbt`, `src/compatibility.mbt`, and tests.

1. Add tests for field order, defaults, aliases, promotions, enum symbols, fixed sizes, and unions.
2. Implement compatibility diagnostics and reusable resolution plans.
3. Implement resolved decoding and validate incompatible cases.
4. Run all tests, commit, and push.

### Task 5: Canonical form and containers

**Files:** Create `src/canonical.mbt`, `src/fingerprint.mbt`, `src/container.mbt`, and tests.

1. Add canonical-form and CRC-64-AVRO vectors.
2. Implement parsing canonical form and fingerprinting.
3. Implement null-codec object container header/block read and write.
4. Verify round trips and corruption handling, commit, and push.

### Task 6: CLI, examples, documentation, and release quality

**Files:** Create `cmd/moonavro/*`, `examples/*`, `fixtures/*`, `.github/workflows/ci.yml`, and update README/API docs.

1. Add CLI commands for schema inspection, encode/decode, compatibility, and container round trips.
2. Add runnable examples and realistic fixtures.
3. Add CI, changelog, contribution guide, security policy, and third-party notices.
4. Run format, check, JS/Wasm-GC tests, docs, end-to-end smoke test, and line-count audit.
5. Commit, push through a reviewable PR, and confirm GitHub Actions.
