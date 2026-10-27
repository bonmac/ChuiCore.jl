- Test: the `code_typed` constant-fold check in `test/classes_unit_tests.jl` now passes under
  code coverage (coordinator ADR-0011). With coverage on it drops exactly the `Expr(:code_coverage_effect)`
  counter statements, asserts that at least one was there, and then makes the same
  single-`return IsFunctor()` assertion. The run without coverage is unchanged.
