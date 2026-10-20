# Reference: recursion schemes and free monads

Recursion schemes over any value whose type has a Functor instance (`cata`, `ana`, `hylo`,
`para`, `apo`, `histo`, `futu` and the monadic `cataM`, `anaM`, `hyloM`); `Fix` for generic
code; data types à la carte (`Coproduct`, `inj`, `prj`) and a freer monad with a loop
interpreter. All public, not exported.

```@autodocs
Modules = [ChuiCore]
Private = false
Pages = ["schemes/schemes.jl", "schemes/free.jl"]
```
