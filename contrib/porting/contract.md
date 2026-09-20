## Joolia's indexing contract

- Collection positions start at zero: arrays, tuples, named-tuple positions,
  SimpleVectors, Memory, strings/code units, and iteration indices such as
  enumerate and ntuple callbacks. Read the current implementation for details.
- Dimension arguments start at zero. Preserve column-major storage, strides,
  shape lengths and element counts. Do not subtract one from a size or count.
- Colon ranges remain inclusive. `0:4` has five values; `(10:14)[0] == 10`.
  Range values and range storage indices are different concepts. Inspect empty,
  descending, floating-point and unsigned ranges separately.
- Strings use zero-origin UTF-8 byte positions, not uniform character positions.
  Respect valid code-unit boundaries and search failure conventions.
- Memory references use zero-origin positions from memory and signed relative
  displacements from an existing reference. Counts remain counts.
- Sentinels require individual inspection. A former zero sentinel may collide
  with a valid position; minus one may overflow an unsigned type. Nothing and
  empty ranges are not interchangeable with numeric sentinels.
- Compiler SSA, slot and branch identifiers retain their established internal
  representation. Translate at storage boundaries; never blindly renumber IDs.
- C, LLVM, BLAS and LAPACK boundaries keep their external contracts. Fortran
  pivot values and Julia collection positions need explicit conversion where
  appropriate. Changing a collection origin does not change the foreign ABI.
- A clean merge can still contain semantic off-by-ones. Inspect generated Expr
  arguments, tuple destructuring alternatives, loop limits, masks and slices,
  higher-order callbacks, option enums and short-circuit conditions.
- Regression examples: reversed resolver adjacency condition lost dependencies;
  adding one to malloc_log's enum enabled allocation logging in Pkg.test;
  terminal code confused a prompt column with input indentation.
- Read JOOLIA.md, JOOLIA_BASE_PORT.md, stdlib/VENDORED.md and
  contrib/ci/coverage.json for implementation details and coverage limits.
