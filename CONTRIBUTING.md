# Contributing

MoonAvro accepts focused issues and pull requests. Before opening a change:

1. Explain the Avro specification behavior or interoperability problem.
2. Add a failing test or an external compatibility vector.
3. Keep public APIs target-independent unless a package is explicitly marked
   for one target.
4. Run `moon fmt --check`, build and check the `src` package on JS and Wasm-GC,
   run both test suites, run `./scripts/coverage.ps1 -MinimumPercent 65`, and
   build the JS CLI.
5. Update README/API documentation for user-visible changes.

Generated build output must not be committed. Compatibility fixes should name
the producer or consumer implementation used for verification when applicable.
