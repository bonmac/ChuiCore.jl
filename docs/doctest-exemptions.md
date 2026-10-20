# Doctest exemptions (ecosystem ADR-0008 §3)

Every exported and public ChuiCore name has a `jldoctest` in its docstring, checked by the
`:quality` item "ADR-0008 every exported and public name has a doctest and a cost" in
`test/doctest_tests.jl`. An API whose output is nondeterministic (scheduling, concurrency, timing,
task ids) may use a plain `julia` block instead; it is listed here with the `@testitem` that covers
it. The test reads the first column of this table.

| Name | Why exempt | Covered by |
|---|---|---|
