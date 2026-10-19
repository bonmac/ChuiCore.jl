# Research: trait encoding for ChuiCore's algebraic structures

- **Date:** 2026-10-20
- **Lane:** phase1-research (researcher)
- **Julia:** floor 1.10.12 (`julia +lts`), stable 1.13.2 (`julia +release`)
- **Status:** evidence for the phase-1 trait-encoding ADR. This note recommends; it does not decide.

## Questions

1. Compare these encodings for Semigroup/Monoid and for the higher-kinded classes
   (Functor ... Arrow):
   - (a) plain Holy traits
   - (b) a Bool-returning function plus `Val` dispatch
   - (c) SimpleTraits.jl
   - (d) WhereTraits.jl
   - (e) BinaryTraits.jl
   - (f) TypeClasses.jl / DataTypesBasic.jl
   - (g) abstract supertypes
   - (h) instance values (dictionary passing)

   For each, check whether the trait constant-folds, whether it infers, what it allocates, how an
   instance is declared, how a type with several monoids is handled, how higher-kinded classes are
   expressed, and whether Base functions can serve as the operations.
2. Registry and maintenance facts for the trait and monad packages.
3. Can `combine` serve both arities, and should the signature be `neutral(::Type{T})` or
   `neutral(m)`?
4. What does each encoding imply for the law-test kit?

## Method

- **Prototype scripts** (scratch, not part of the repo):
  `/private/tmp/claude-501/-Users-bonmac-personal-projects-julia-data-analysis/5c1f011c-1151-4765-9a79-8eba6d64f4e6/scratchpad/phase1/traits/`.
  - `core.jl` covers (a), (b), (g), (h), the higher-kinded Functor, `combine` arity, the Base hooks and the law kits. It has no dependencies.
  - `pkgs.jl` covers (c) to (f).
  - `neutral.jl` covers the `neutral` signature options.
- **Commands:**
  `julia +lts --startup-file=no [--project=env-lts] <file>` and
  `julia +release --startup-file=no [--project=env-rel] <file>`.
  The package environments were made by `Pkg.add` of the five packages, which resolved the same
  versions on both Julia versions:
  - BinaryTraits v0.7.0
  - DataTypesBasic v1.0.0
  - SimpleTraits v0.9.6
  - TypeClasses v1.1.0
  - WhereTraits v1.0.0

  WhereTraits and DataTypesBasic were held back by joint resolution, so WhereTraits 1.1.2 is not
  tested.
- **Constant folding:** `code_typed(f, types; optimize=true)`, printing the statements. "Folds"
  means no call to the trait function survives.
- **Inference:** `Test.@inferred`.
- **Allocations:** `@allocated` inside a function specialised on the callee:
  `measure(f, xs) = (f(xs); f(xs); @allocated f(xs))`.
  - A top-level dynamic call reports 16 bytes on 1.10 even for `Base.sum`. That is the boxed
    `Int` result, a measurement artifact; the output below shows both.
- **Registry facts:** from the local General registry (`~/.julia/registries/General.tar.zst`, tree
  `3909358acc0fb535d4cb67fa03ee5836ad28b0f2`), extracted to scratch.
- **Maintenance facts:** read-only `gh api repos/<r>` and `repos/<r>/commits?per_page=1` GETs,
  2026-10-20.
- **Context7:**
  - `/websites/julialang_en_v1` for trait-based dispatch.
  - `/typelevel/cats` for the instance encoding.
  - No Context7 entry was found for SimpleTraits; its resolve returned unrelated Julia packages.
  - The other Julia trait packages were read from their installed sources and READMEs under
    `~/.julia/packages` (read-only).

## Results (commands and pasted output)

### (a) Holy traits, (b) Bool + Val, (g) abstract supertype, (h) instance values: `core.jl`

The key definitions, abridged from `core.jl`:

```julia
# (a) Holy trait: one monoid per type; a second needs a wrapper (Haskell's Product)
MonoidStyle(::Type) = NotMonoid();  MonoidStyle(::Type{<:Integer}) = IsMonoid()
mappend(a::T, b::T) where {T} = _mappend(MonoidStyle(T), a, b)
_mappend(::IsMonoid, a::Integer, b::Integer) = a + b
# (b) Bool + Val
ismonoid(::Type) = false;  ismonoid(::Type{<:Integer}) = true
mappend(a::T, b::T) where {T} = _mappend(Val(ismonoid(T)), a, b)
# (h) instance values; the instance is the first argument
struct Sum <: Monoid end;  struct Prod <: Monoid end;  struct Max <: Monoid end
combine(::Sum, a, b) = a + b;  combine(::Prod, a, b) = a * b
neutral(::Sum, ::Type{T}) where {T} = zero(T)
(m::Monoid)(a, b) = combine(m, a, b)                               # callable: Base reduce accepts it
Base.reduce_empty(m::Monoid, ::Type{T}) where {T} = neutral(m, T)  # own type: not piracy
default_monoid(::Type{<:Number}) = Sum()                           # Holy-style lookup returning a VALUE
combine(a::T, b::T) where {T} = combine(default_monoid(T), a, b)   # 2-arg sugar (arity experiment)
```

Output on `julia +release` (1.13.2):

```
Julia 1.13.2

== (a) Holy traits
IR mappend(1,2):            Base.add_int(_2, _3) ; return %1
IR mappend(Float64) (Not):  $(Expr(:invoke, CodeInstance for MethodInstance for Main.HolyA._mappend(::Main.HolyA.NotMonoid, ::Float64, ::Float64), :(Main.HolyA._mappend), Main.HolyA.NotMonoid(), Core.Argument(2), Core.Argument(3))) ; unreachable
@inferred mconcat(Int[]) => 6
Product via wrapper       => 24
@allocated mconcat        = 0

== (b) Bool + Val
IR mappend(1,2):            Base.add_int(_2, _3) ; return %1
@inferred mconcat         => 6
@allocated mconcat        = 0
IR mappend_dyn (runtime Bool): Core.apply_type(Base.Val, _4) ; %new(%1) ; (isa)(%2, Val{false}) ; ... Core.throw_methoderror(Main.BoolB._mappend, %2, _2, _3) ; unreachable ; φ (%7 => %6, %11 => %10) ; return %14

== (g) abstract supertype
Int <: AbstractMonoid ? false  (retrofitting impossible: `struct` declares its one supertype)
Vector{Int} supertype chain: (Vector{Int64}, DenseVector{Int64}, AbstractVector{Int64}, Any)

== (h) instance values
IR combine(Sum(),1,2):      Base.add_int(_3, _4) ; return %1
IR combine(1,2) via default:Base.add_int(_2, _3) ; return %1
Int under + and *:  9 24
@inferred mconcat(Max) => 9
Base reduce(Sum(), Int[])  => 0
Base reduce(Prod(), Int[]) => 1
Base mapreduce(abs, Max(), [-7,3]) => 7
Base accumulate(Sum(), 1:4) => [1, 3, 6, 10]
@allocated mconcat(Sum)  = 0
@allocated reduce(Sum()) = 0
reduce(Sum(),xs)==sum(xs): true
@inferred reduce(Sum(), Float64[]) => 0.0
Base.ispublic(Base,:reduce_empty) = false
  @allocated alloc_h  = 0   (top-level dynamic call: 0)
  @allocated alloc_r  = 0   (top-level dynamic call: 0)
  @allocated alloc_a  = 0   (top-level dynamic call: 0)
  @allocated alloc_s  = 0   (top-level dynamic call: 0)

== combine arity: one generic function, 2-arg and 3-arg methods
methods(InstH.combine): 5 methods
Test.detect_ambiguities(InstH): Tuple{Method, Method}[]
combine("a","b","c") => MethodError: no method matching combine(::String, ::String, ::String)
The function `combine` exists, but no me
combine(Endo(), sin, cos)(0.0) = 0.8414709848078965
2-arg fallback for a Tuple acc: MethodError

== Functor via Base.map / broadcasting / trait on typename wrapper
map(f, Vector)                  [2, 3]
map(f, Tuple)                   (2, 3)
map(f, Some(1))                 ERROR MethodError: no method matching length(::Some{Int64})
map(f, nothing)                 ERROR MethodError: no method matching length(::Nothing)
map(f, Dict)                    ERROR map is not defined on dictionaries
map!(f, values(d), values(d))   ERROR MethodError: no method matching map!(::var"#55#56", ::Base.ValueIterator{Dict{Symbol, Int6
map(f, Box(1))                  Box{Int64}(2)
f.(Vector)                      [2, 3]
f.(Tuple)                       (2, 3)
f.(Some(1))                     ERROR MethodError: no method matching length(::Some{Int64})
f.(Dict)                        ERROR ArgumentError: broadcasting over dictionaries and `NamedTuple`s is reserved
Iterators.map on Dict values    [2]
IR fmap(f, Some{Int}) (trait on typename wrapper): Base.getfield(_3, :value) ; Base.add_int(%1, 1) ; %new(Some{Int64}, %2) ; return %3
@inferred fmap Vector => [2, 3]
typename(Vector{Int}).wrapper = Array
typename(Some{Int}).wrapper   = Some

== Foldable via Base: foldl(+, (1,2,3)) = 6; mapreduce(abs, max, [-3,2]) = 3; foldl on Box: MethodError
after Base.iterate(::Box): foldl(+, Box(1); init=10) = 11

== law kit: instance-first (h) vs type-keyed (a)
instance kit Sum/Int:        true
instance kit Prod/Int:       true
instance kit Sum/Float64 (isequal; expected to fail assoc): false
instance kit Sum/Float64 (≈): true
typed kit Int:               true
typed kit Float64 (NotMonoid): false
```

On `julia +lts` (1.10.12) every line matched except these. The "Holy" and "Bool + Val" IR
(`Base.add_int(_2, _3) ; return %1`), the instance IR, the Functor table and the law kits were
identical.

```
Julia 1.10.12
IR mappend_dyn (runtime Bool): Core.apply_type(Base.Val, _4) ; %new(%1) ; Main.BoolB._mappend ; (isa)(%2, Val{false}) ; ... Main.BoolB._mappend(%2, _2, _3) ; goto %15 ; φ (...) ; return %15
@allocated mconcat(Sum)  = 16
@allocated reduce(Sum()) = 16
Base.ispublic not defined on this Julia (added in 1.11)
  @allocated alloc_h  = 0   (top-level dynamic call: 16)
  @allocated alloc_r  = 0   (top-level dynamic call: 16)
  @allocated alloc_a  = 0   (top-level dynamic call: 16)
  @allocated alloc_s  = 0   (top-level dynamic call: 16)
combine("a","b","c") => MethodError: no method matching combine(::String, ::String, ::String)
```

The 16 bytes on 1.10 appear only at a top-level dynamic call, and for `Base.sum` too (`alloc_s`).
It is the boxed result, not the encoding. Inside a specialised caller every encoding allocates 0 on
both versions.

### (c) SimpleTraits, (d) WhereTraits, (e) BinaryTraits, (f) TypeClasses: `pkgs.jl`

The key definitions, abridged:

```julia
# (c) SimpleTraits
@traitdef IsMonoid{X};  @traitimpl IsMonoid{Int}
@traitfn mappend(a::X, b::X) where {X; IsMonoid{X}} = a + b
@traitdef IsFunctor{X};  isfunctor(X) = Base.typename(X).wrapper in (Array, Some)
@traitimpl IsFunctor{X} <- isfunctor(X)                        # trait computed by a function
isfunctor2(::Type) = false;  isfunctor2(::Type{<:Array}) = true;  isfunctor2(::Type{<:Some}) = true
@traitimpl IsFunctor2{X} <- isfunctor2(X)                      # dispatch-only predicate
# (d) WhereTraits
@traits mappend(a::T, b::T) where {T, ismonoid(T)} = a + b
# (e) BinaryTraits: trait on a VALUE, so a vector needs a witness element
@trait Monoid;  @implement Is{Monoid} by mappend(_, _);  @assign Int with Is{Monoid}
@traitfn mconcat_t(x::Is{Monoid}, xs) = foldl(mappend, xs; init = zero(x))
mconcat(xs) = mconcat_t(first(xs), xs)
```

Output on `julia +release` (1.13.2). The WhereTraits "Replacing docs" warning is filtered out.

```
Julia 1.13.2
  BinaryTraits v0.7.0
  DataTypesBasic v1.0.0
  SimpleTraits v0.9.6
  TypeClasses v1.1.0
  WhereTraits v1.0.0

== (c) SimpleTraits
istrait(IsMonoid{Int}) = true; IsMonoid{Float64} = false
IR mappend(1,2):            Base.add_int(_2, _3) ; return %1
@inferred mconcat => 6
@allocated mconcat = 0
fmap Some: Some(2)  fmap Vector: [2]
IR fmap(f, Some{Int}) (predicate uses `in` on a tuple of types): Base.getfield(_3, :value) ; Base.add_int(%1, 1) ; %new(Some{Int64}, %2) ; return %3 ...
IR fmap2(f, Some{Int}) (dispatch-only predicate): Base.getfield(_3, :value) ; Base.add_int(%1, 1) ; %new(Some{Int64}, %2) ; return %3

== (d) WhereTraits
IR mappend(1,2):            Base.add_int(_2, _3) ; return %1
@inferred mconcat => 6
@allocated mconcat = 0
mappend(1.0,2.0) => ArgumentError

== (e) BinaryTraits
@check(Int): ✅ Int64 has implemented:
1. BinaryTraits.BinaryTrait{Main.BT.Monoid}: BinaryTraits.Prefix.Positive{Main.BT.Monoid} ⇢ mappend(🔹, 🔹)

IR mconcat(Vector{Int}): (long; trait call present? false)
@inferred mconcat => 6
@allocated mconcat = 0
mconcat([1.0]) => ArgumentError

== (f) TypeClasses / DataTypesBasic
combine("a","b")       = ab
combine("a","b","c")   = abc   (variadic 2-arg semigroup)
neutral(String)        = ""
neutral(Int)           = neutral   (generic singleton: no Int monoid chosen)
combine([1],[2])       = [1, 2]
combine(1,2)           = MethodError
foldl_monoid(["a","b"]) = ab
IR combine(String,String): $(Expr(:invoke, CodeInstance for MethodInstance for Base._string(::String, ::Vararg{String}), :(Base._string), Core.Argument(2), Core.Argument(3))) ; return %1
@inferred foldl_monoid(["a"]) => return type String does not match inferred return type Union{typeof(TypeClasses.neutral), String}
flatmap over Vector    = [1, 1, 2, 2]
map on Identity(1)     = Identity(2)
Option(nothing) map    = Const(nothing)
Base methods defined by TypeClasses: 19
  of which on no TypeClasses/DataTypesBasic-owned argument type (piracy): 14
   Tuple{typeof(map), Any, Distributed.Future}
   Tuple{typeof(map), Any, Task}
   Tuple{typeof(map), Any, TypeClasses.DataTypes.Writers.Writer}
   ...
   Tuple{typeof(foreach), Any, Distributed.Future}
   Tuple{typeof(foreach), Any, Task}
   ...
Monoid law kit exported? false
```

**Correction to the piracy count.** The script's ownership filter over-counts: it does not see
types in nested submodules, such as `TypeClasses.DataTypes.Writers.Writer`. Reading the 14
printed signatures, only **4 are piracy**, because they extend a Base function on a Base or
stdlib type only:
- `map(f, ::Task)`
- `map(f, ::Distributed.Future)`
- `foreach(f, ::Task)`
- `foreach(f, ::Distributed.Future)`

The other 10 have a TypeClasses- or DataTypesBasic-owned argument.

On `julia +lts` (1.10.12) all of the above was identical except one line. SimpleTraits did **not**
fold the `in`-based predicate there:

```
IR fmap(f, Some{Int}) (predicate uses `in` on a tuple of types): goto %27 if not true ; φ (%1 => Array, %26 => %21) ; φ (%1 => 2, %26 => %22) ; $(Expr(:foreigncall, :(:jl_types_equal), Int32, svec(Any, Any), 0, :(:ccall), : ...
IR fmap2(f, Some{Int}) (dispatch-only predicate): Base.getfield(_3, :value) ; Base.add_int(%1, 1) ; %new(Some{Int64}, %2) ; return %3
```

### Load time (`t = @elapsed using P`, fresh process; repeated runs shown as a range)

| Package | 1.10.12 | 1.13.2 |
|---|---|---|
| SimpleTraits 0.9.6 | 0.23 s | 0.24 s |
| BinaryTraits 0.7.0 | 0.06 s | 0.06 s |
| WhereTraits 1.0.0 | 0.61-0.74 s | 2.3-3.6 s |
| TypeClasses 1.1.0 | 0.39-0.64 s | 1.2-2.4 s |

These are single-machine numbers, three runs at most. They are not a benchmark and need an
evidence file before any doc cites them as a budget.

### `neutral` signature options: `neutral.jl`

```julia
struct NoValue end                                 # adjoined identity ("no value yet", CC-004/CC-007)
combine(::Max, a, b) = max(a, b);  combine(::Max, ::NoValue, b) = b;  combine(::Max, a, ::NoValue) = a
neutral_t(::Type{T}) where {T <: Number} = zero(T)                    # option 1: type only
neutral(::Max, ::Type{T}) where {T} = typemin(T)                      # option 2: instance + carrier
neutral(::Sum) = false;  neutral(::Max) = NoValue();  neutral(::Mean) = (0.0, 0)   # option 3
```

The output was identical on 1.10.12 and 1.13.2:

```
neutral_t(Int) = 0  (one answer per type)
Option 2: fold2(Sum) = true  fold2(Max) = true
Option 2 @inferred fold2(Max, Int[]) => -9223372036854775808 (typemin: a fake value, not 'empty')
Option 3: fold3(Sum) == sum: true  fold3(Sum, Int[]) = false (Bool false, not Int 0)
Option 3: fold3(Max) == maximum: true  fold3(Max, Int[]) = NoValue()
Option 3 @inferred fold3(Max, xs): return type Int64 does not match inferred return type Union{NoValue, Int64}
Base.return_types fold3(Max, Vector{Int}) = Any[Union{NoValue, Int64}]
@allocated fold2(Max) = 0   fold3(Max) = 0
Mean carrier: combine(Mean(), (3.0,2), (4.0,1)) = (7.0, 3)
semigroup kit Mean on accumulators: true
semigroup kit Max incl. NoValue: true
```

## Findings with sources

### F1. Every type-keyed encoding constant-folds; only the predicate's inferability matters

- **What folds on both versions.** Holy traits (a), Bool + `Val` (b), SimpleTraits (c), WhereTraits
  (d) and BinaryTraits (e) all reduce `mappend(1, 2)` to `Base.add_int` with no trait call left.
  All are `@inferred` and allocate 0.
- **When folding fails.** It fails when the trait is computed from something inference cannot
  fold:
  - a runtime `Bool` (`mappend_dyn`: an `isa` branch plus a dynamic call, on both versions);
  - a predicate written with `in` over a tuple of types. That folds on 1.13.2 but not on 1.10.12,
    where a `jl_types_equal` loop survives.

  **Rule:** a trait predicate must be dispatch-only (methods on `Type{...}` returning constants).
  Then it folds on the floor version too.
- **Source.** The Julia manual's "Trait-based dispatch" says a Holy trait is "a generic function
  which computes a different singleton value (or type) for each trait-set", and that "if this
  function is pure there is no impact on performance compared to normal dispatch". Fetched via
  Context7 `/websites/julialang_en_v1`, manual/methods, 2026-10-20.
- The packages add nothing at runtime over hand-written Holy traits. SimpleTraits' `@traitfn` and
  WhereTraits' `@traits` generate the same kind of dispatch: `IR` identical to (a).

### F2. Type-keyed encodings (a)-(e) give one monoid per type; instance values (h) give many

- **Type-keyed encodings.** Under (a)-(e), "Int is a monoid" is a property of `Int`. A second monoid
  (`*`, `max`) needs a wrapper type: `Product(x)` in the prototype, as Haskell's `Sum`/`Product`
  newtypes. That means wrapping and unwrapping every element (`HolyA.Product.([2,3,4])`).
- **TypeClasses.jl** takes the type-keyed route. `neutral(Int)` returns its generic `neutral`
  singleton (no Int monoid is chosen), and `combine(1, 2)` is a `MethodError` (output above).
- **Instance values (h).** A monoid is a value: `Sum()`, `Prod()`, `Max()`, or a parameterised
  `ReduceM(op)`. "Int under + and *" is simply `mconcat(Sum(), xs)` vs `mconcat(Prod(), xs)` (9 and
  24 above), with no wrapper.
- **This is exactly the Scala cats encoding**, where an instance is an (implicit) value
  `Monoid[Int]` passed as a parameter. Fetched via Context7 `/typelevel/cats`,
  docs/typeclasses.md and typeclasses/monoid.md, cats 2.13.0. Cats too needs a choice between
  `intAdditionMonoid` and a multiplication monoid; Julia has no implicit resolution, so the
  instance is passed explicitly.
- **ChuiCore's aggregators are already instance values.** In CC-004 (`contracts/chui-core.md`),
  `ChuiCore.combine(agg, a, b)` takes `agg` as the instance, and the prototype's `Sum()`,
  `Max()`, `ReduceM(op)` are instance values too (`reference/prototype/Tidy.jl` lines 93-117).
- **Cost.** The instance is a singleton or small struct argument. `combine(Sum(), 1, 2)` folds to
  `Base.add_int(_3, _4)`, and folds allocate 0 inside a specialised caller on both versions.

### F3. Base can host instance values without piracy

- **Callable instances.** A callable instance (`(m::Monoid)(a, b) = combine(m, a, b)`) plus
  `Base.reduce_empty(m::Monoid, T)` makes all of these work, defined only on ChuiCore-owned
  types:
  - `reduce(Sum(), Int[]) == 0`
  - `reduce(Prod(), Int[]) == 1`
  - `mapreduce(abs, Max(), xs)`
  - `accumulate(Sum(), 1:4)`

  `reduce(Sum(), xs) == sum(xs)` with 0 allocations. Base's `reduce` may reassociate (pairwise),
  so only an associative `combine` may be used this way. That is the semigroup law, which the
  instance must satisfy anyway.
- **Caveat.** `Base.reduce_empty` is internal: `Base.ispublic(Base, :reduce_empty) == false` on
  1.13.2, and `ispublic` does not exist on 1.10. Relying on it is an internal-API dependency, so
  it needs a test on every supported Julia, or an explicit `init`.
- **Mismatched carriers.** Callable instances fit only monoids whose carrier is the element type.
  `Mean`'s carrier is the accumulator `(s, n)`, so `reduce(Mean(), xs)` over raw elements would be
  wrong. Aggregators keep `partial` to lift elements into the carrier (CC-004).

### F4. Higher-kinded classes: key the trait on the type constructor, and use Base where Base already has the operation

- **Expressing "kind * -> *".** `Base.typename(T).wrapper` (`Vector{Int}` → `Array`,
  `Some{Int}` → `Some`) stands in for a kind `* -> *`. A trait on it folds completely:
  `fmap(f, ::Some{Int})` compiles to `getfield; add_int; %new(Some{Int64}, ...)` on both versions.
  Dispatch on `Type{<:Vector}` works equally well when the set is a subtype tree; the trait only
  earns its place for unrelated constructors.
- **What Base `map`/broadcast already cover:** `map` and `f.(x)` work on `Vector` and `Tuple`.
- **What they do not cover:**
  - `Some(1)`: `MethodError` on `length`.
  - `nothing`: `MethodError` on `length`.
  - `Dict`: "map is not defined on dictionaries"; broadcasting over a Dict is "reserved".
  - `map!` on `values(d)`: `MethodError`.

  All of these fail on both versions. Adding `Base.map(f, ::Some)` or `Base.map(f, ::Dict)` would
  be piracy (Base function, Base type).
- **So ChuiCore needs its own `fmap`.**
  - It falls back to `Base.map` for types where Base's `map` is the functor map: Array, Tuple, and
    ChuiCore-owned types such as `Box`.
  - It has explicit methods for `Some`/`Nothing` and Dict values. `Iterators.map` over
    `values(d)` works but returns an iterator, not a Dict.
  - On ChuiCore-owned types, add methods to `Base.map` itself (`map(f, ::Box)` works) so users
    keep the Base name.
- **TypeClasses.jl** made the same split: its Functor is `Base.map`, it declines Dict
  (`TypeInstances/Dict.jl`: "we do NOT support AbstractDict, because there is no general way to
  map over such a type"), and it adds 4 pirate methods on `Task`/`Future`.
- **Foldable** is Base already: `foldl`, `foldr`, `mapreduce` over any iterable. A user type
  becomes Foldable by implementing `Base.iterate` (`foldl(+, Box(1); init=10) == 11` after
  defining it). Haskell's own Foldable laws are stated in terms of `foldMap` and `foldr` (see
  `inspiration-typeclasses.md`), so a Julia Foldable kit can check that
  `foldl(op, x; init) == foldl(op, collect(x); init)`.

### F5. The `combine` arity question

One generic function with a 2-arg semigroup method and the 3-arg CC-004 method is **dispatch-sound**:
`Test.detect_ambiguities` found none, and arity separates the methods. It is **not semantically
sound**, for three demonstrated reasons:

1. **Variadic collision.** A 2-arg semigroup op invites the Base convention `op(a, b, c...)`, as in
   `+`. TypeClasses.jl does exactly that: `combine(a, b, c, more...) = foldl(⊕, more, init=(a⊕b)⊕c)`
   (TypeClasses 1.1.0 source file MonoidAlternative.jl, under its src/TypeClasses directory; output `combine("a","b","c") = abc`). In ChuiCore the
   3-arg slot is already taken by `combine(agg, a, b)` (CC-004). `combine("a","b","c")` is a
   `MethodError` in the prototype today, but it means "fold three elements" to anyone coming from
   TypeClasses or Base.
2. **Ambiguous meaning when elements are callables.** With an Endo monoid (functions under `∘`),
   `combine(Endo(), sin, cos)` and a hypothetical variadic `combine(f, g, h)` cannot be told apart
   by reading.
3. **The 2-arg form needs a default instance.** `combine(a, b)` must look up
   `default_monoid(typeof(a))`. That brings back "one monoid per type", and fails for
   accumulator types shared by several aggregators: `combine((1.0, 2), (3.0, 4))` →
   `MethodError`. A tuple accumulator does not know which aggregator it belongs to.

**The 3-arg instance-first form can serve as the semigroup op.** An instance defines a semigroup on
its carrier, and for aggregators the carrier is the accumulator. The prototype checks associativity
on `Mean`'s `(s, n)` carrier, and on `Max` with the adjoined `NoValue` identity (both `true`).

**Recommendation:**
- `ChuiCore.combine(m, a, b)` is the only `combine` method shape.
- No 2-arg or variadic methods.
- If infix sugar is wanted, give it a different name bound to a default instance, never another
  `combine` method.

  UNVERIFIED design choice: whether to provide sugar at all, and its name.

### F6. The `neutral` signature, given types with several monoids

- **`neutral(::Type{T})`** can only answer for one monoid per type, which is option 1. It is
  incompatible with F2: `Int` has `Sum`, `Prod`, `Max`, `Min`.
- **`neutral(m, ::Type{T})`** (option 2) is concrete and `@inferred`, but for semigroups without a
  real identity it must invent one. `typemin(Int)` for `Max` is a fake value, which is the
  empty-input behaviour CC-007 forbids (`final(Max(), init(Max()))` must throw).
- **`neutral(m)`** (option 3) matches CC-004's `init(agg)` and its "no value yet" state:
  - `Max` gets the adjoined identity `NoValue()`, the Maybe-lifting of a semigroup to a monoid.
  - `fold3(Max(), Int[]) = NoValue()`, which `final` can turn into CC-007's error.
  - Cost: the fold's return type becomes the small union `Union{NoValue, Int64}`. It allocates
    0, but `@inferred` fails, on both versions.
  - For numeric `Sum`, `neutral(Sum()) = false` (Base's strong zero) works but returns `false`,
    not `0`, on empty input.
- **Recommended shape:**
  - `neutral(m)` is required. It is the identity, which may be a "no value yet" sentinel.
  - `neutral(m, ::Type{T})` is an optional refinement, `neutral(m, ::Type) = neutral(m)` by
    default, for instances whose identity is a concrete carrier value (`Sum` → `zero(T)`). Folds
    use it when the element type is known, which keeps them `@inferred` where an identity really
    exists.
  - `init(agg)` (CC-004) can then be defined as `neutral(agg)` for every aggregator that is a
    monoid. That relationship should be written into the ADR (UNVERIFIED until the ADR decides).

### F7. Abstract supertypes (g): rejected, for the recorded reasons

- **No retrofitting.** A `struct` declares its single supertype at definition, so `Int`,
  `String` or `Vector` can never become `<: AbstractMonoid` (`Int <: AbstractMonoid == false`).
- **One supertype per type.** `Vector{Int}`'s chain is fixed at
  `(Vector, DenseVector, AbstractVector, Any)`, so it cannot be both an `AbstractVector` and an
  `AbstractMonoid`.
- **Still one monoid per type**, like (a).
- **Cats makes the same case against subtyping.** With subtyping you can reach `empty` only
  through a value, so an empty list has nothing to call it on; a type class gives `empty` from the
  type alone, and lets `Pair` be a Monoid only when its parameters are. cats `typeclasses.html`,
  2.13.0, via the fetch lane. See `inspiration-typeclasses.md`.
- **An abstract type is fine as a tag on instance values** (`abstract type Monoid end; struct Sum
  <: Monoid end`), because those are ChuiCore's own types. It does no harm to element types.

### F8. Law-test kit implications

| Encoding | Kit signature | Notes |
|---|---|---|
| (a)-(e) type-keyed | `test_monoid_laws(::Type{T}, gen; eq)` | One kit call per type. A second monoid needs a wrapper type and wrapped generators. |
| (h) instance values | `test_monoid_laws(m, gen; eq)` | `gen` yields carrier values (accumulators for aggregators). The same kit covers `Sum()`, `Prod()`, `Mean()` and user aggregators. This is the cats model, where `MonoidTests[A].monoid` takes the instance plus `Arbitrary` and `Eq`. |
| HKT classes (type-keyed) | `test_functor_laws(gen_fa, gen_f; eq)` | The instance is implied by the type of `gen_fa()`. |

- **`eq` is mandatory, not a nicety.** `Sum()` on `Float64` fails associativity under `isequal`
  (`false` above) and passes under `≈`. CC-004 already states its float laws with `≈`.
- **Shape of the kit.** Law functions return `(lhs, rhs)` pairs, which a runner wraps in
  `@test eq(lhs, rhs)`. This mirrors cats' `IsEq` laws bundled into discipline `RuleSet`s. That
  structure is sketched in `inspiration-typeclasses.md` and is not yet prototyped against
  TestItemRunner (UNVERIFIED).

### F9. Package facts

Registry facts come from the local General tree `3909358a...` (2026-10-20), and GitHub facts from
`gh api` GETs on 2026-10-20.

| Package | Latest | Julia compat (latest) | Deps (latest) | Last commit | Stars / open issues |
|---|---|---|---|---|---|
| SimpleTraits | 0.9.6 | `1` | MacroTools 0.5, InteractiveUtils | 2026-05-18 | 167 / 13 |
| WhereTraits | 1.1.2 (1.0.0 tested) | `1.6.0-1` | DataTypesBasic, ExprParsers, Markdown, ProxyInterfaces, Setfield, SimpleMatch, StructEquality, Graphs, IterTools, MetaGraphs, Pipe, Reexport | 2023-07-11 | 93 / 7 |
| BinaryTraits | 0.7.0 | `1.6.0-1` | MacroTools 0.5, ExprTools 0.1 | 2021-11-25 | 54 / 8 |
| TypeClasses | 1.1.0 | `1.6.0-1` | Compat, DataTypesBasic, ExprParsers, Monadic, ProxyInterfaces, Reexport, Requires, **Revise**, StructEquality, Suppressor | 2023-05-07 | 18 / 0 |
| DataTypesBasic | 2.0.3 (1.0.0 resolved with TypeClasses) | `1.6.0-1` | (none at 2.0.3) | 2023-07-01 | 13 / 3 |
| Monadic (JuliaFunctional) | 1.0.0 | `1` | n/a | 2022-07-18 | 8 / 0 |
| Monads (ulysses4ever) | 0.2.5 | `1` | n/a | 2025-11-30 | 34 / 4 |
| HolyMonads | 0.1.0 | `1.10.0-1` | n/a | 2025-05-06 | 1 / 2 |
| MonadFunctions | 0.1.0 | `1` | n/a | 2020-12-14 | 13 / 0 |
| CanonicalTraits | 0.2.4 | `1` | n/a | 2023-12-22 | 66 / 8 |

- **Repositories.** None is archived. They are:
  - mauro3/SimpleTraits.jl
  - jolin-io/WhereTraits.jl
  - tk3369/BinaryTraits.jl
  - JuliaFunctional/TypeClasses.jl
  - JuliaFunctional/DataTypesBasic.jl
  - JuliaFunctional/Monadic.jl
  - ulysses4ever/Monads.jl
  - antimon2/HolyMonads.jl
  - tk3369/MonadFunctions.jl
  - thautwarm/CanonicalTraits.jl
- **"n/a"** means the deps were not extracted.
- **Only SimpleTraits shows recent activity.**
- **TypeClasses' dependency on Revise** (a development tool) and its use of Requires make it
  unsuitable as a dependency of a core package.
- **No exported law kit.** None of these packages exports a law-test kit
  (`names(TypeClasses)` contains no "law"; the others were not checked: UNVERIFIED).
- **TypeClasses' names.** It uses the names `combine` and `neutral`, with the same meaning
  ChuiCore chose, and documents the laws in docstrings:
  - Left identity `⊕(neutral(T), t::T) == t`
  - Right identity
  - Associativity

  Its 2-arg-plus-variadic `combine` is the precedent for the collision in F5.

## Recommended encoding, with trade-offs

**A hybrid, split by whether the instance is unique per type.**

1. **Semigroup and Monoid: instance values (h).** These families have many lawful instances per
   type.
   - `abstract type Semigroup end` and `abstract type Monoid <: Semigroup end` tag ChuiCore-owned
     instance structs (`Sum()`, `Prod()`, `Max()`, `ReduceM(op)`). Aggregators are such instances
     whose carrier is the accumulator.
   - Operations: `combine(m, a, b)` (3-arg only, F5); `neutral(m)` (required), with
     `neutral(m, ::Type{T})` as an optional concrete refinement (F6).
   - A Holy-style `default_monoid(::Type{T})` returns an instance value, for APIs that want a
     default. This is the "Holy trait" part: a dispatch-only function of the type that returns a
     singleton, here an instance rather than an `IsX()` flag.
   - Base integration: callable instances plus `reduce`/`mapreduce`/`accumulate` (F3).
2. **Functor, Foldable, Traversable, Applicative, Monad, Alternative, Contravariant, Bifunctor,
   Profunctor, Category/Arrow: plain Holy traits (a) keyed on the type constructor** (F4).
   - Use `XStyle(::Type{T})` with dispatch-only methods, on `Base.typename(T).wrapper` when
     unrelated constructors share an instance.
   - Operations reuse Base names on ChuiCore-owned types (`Base.map`, `Base.iterate`/`foldl`), and
     ChuiCore-owned names (`fmap`, `flatmap`, ...) that fall back to Base for Base types, so there
     is no piracy.
   - Where a type has more than one lawful instance (Vector's cartesian vs zip Applicative;
     broadcasting is the zip-like one), the trait picks the default and a wrapper or instance
     value selects the other.

     UNVERIFIED: which default for Vector. That needs a design decision.
3. **No dependency on SimpleTraits, WhereTraits, BinaryTraits or TypeClasses.** They add no
   runtime benefit over hand-written Holy traits (F1). They do add a macro-generated method
   surface, load time (WhereTraits 2.3-3.6 s on 1.13.2), and stale maintenance (all but
   SimpleTraits last committed 2021-2023). TypeClasses depends on Revise and commits 4 piracies.

**Trade-offs.**

| | Instance values (Monoid family) | Type-keyed Holy traits (HKT family) |
|---|---|---|
| Multiple instances per type | yes, no wrappers | needs wrappers or a second instance value |
| Runtime cost (measured) | 0 alloc, folds to the primitive op, both versions | 0 alloc, folds, both versions |
| Inference | concrete with `neutral(m, T)`; small union `Union{NoValue,T}` with `neutral(m)` for identity-less semigroups | concrete when predicates are dispatch-only; the `in`-based predicate did not fold on 1.10 |
| Call-site verbosity | instance passed explicitly (no implicits in Julia) | none |
| Matches existing contract | yes: CC-004 `combine(agg, a, b)`, `init(agg)` | n/a |
| Law kit | `test_monoid_laws(m, gen; eq)` | `test_functor_laws(gen_fa, gen_f; eq)` |

**★ For the lead and user.** Does "Holy traits, not inheritance" (brief) admit instance values as
the Monoid encoding?
- They are dispatch on singleton values, the same mechanism as Holy traits, and use no element-type
  inheritance.
- But the user may have meant `MonoidStyle(::Type{T})` literally. Under that reading, Int under
  `+` and `*` needs wrapper types, and CC-004's instance-first `combine(agg, a, b)` would be a
  second, parallel mechanism.

## UNVERIFIED

- WhereTraits 1.1.2 and DataTypesBasic 2.0.3: not tested; joint resolution chose 1.0.0 for both.
- Deps of Monadic, Monads, HolyMonads, MonadFunctions and CanonicalTraits: not extracted. Whether
  they export law kits: not checked.
- BinaryTraits on an empty vector: `first(xs)` throws by construction; not run.
- The claim that a Functor instance is unique per type by parametricity: a known result, not
  fetched or verified here. It is the basis for using type-keyed traits for the HKT family.
- Which Applicative is Vector's default (cartesian vs zip/broadcast): a design choice, not
  researched.
- The law-kit runner shape (law functions returning `(lhs, rhs)` pairs inside `@testitem`): not
  prototyped against TestItemRunner.
- Whether to provide 2-arg infix sugar for `combine`, and its name: not decided.
- `neutral(Sum()) = false` for `-0.0` inputs (`false + -0.0`): not run.
- Load-time numbers: at most three runs on one machine; not an evidence file.
- Whether relying on the internal `Base.reduce_empty` stays stable after 1.13: not checked beyond
  1.10.12 and 1.13.2.

## Also noticed

- On 1.10, `@allocated` at a top-level dynamic call reports 16 bytes for any `Int` result outside
  the small-Int cache, even for `sum`. Benchmarks and allocation tests must measure inside a
  function (the `measure` helper above), or they will report false allocations on the floor
  version.
- WhereTraits prints "Replacing docs for `mappend`" warnings when one function gets several
  `@traits` methods.
