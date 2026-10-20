# Reference: transducers

The transducer substrate (ADR-0003): struct-based transducers with no call method, reducing
functions built by `asrf`, the `start`/`next`/`complete` protocol, early termination by
`Reduced`, and the folds `foldxl`, `foldparts`, `foldxt`, `aggregate`. Only `isstateless`
pipelines run per partition. All public, not exported: write `ChuiCore.Map` or
`using ChuiCore: Map`. Tutorial: [transducers](../tutorials/transducers.md).

No item on this page has a contract ID yet (PROVISIONAL in `<root>/contracts/chui-core.md`).

```@autodocs
Modules = [ChuiCore]
Private = false
Pages = ["transducers/transducers.jl", "transducers/folds.jl"]
```
