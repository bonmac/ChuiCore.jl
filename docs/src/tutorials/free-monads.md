# Free monads and interpreters

```@meta
DocTestSetup = :(using ChuiCore)
```

A free monad lets you write a program as **data**: a sequence of instructions, each a plain
struct, glued by `chain`. Nothing runs when you build it. An **interpreter** then walks the
program and gives each instruction a meaning. Because the description is apart from the running,
one program can be run by several interpreters: one that touches the real world, one that only
records what would have happened (for tests), one that stops at the first failure. ChuiCore ships
the minimal pattern (Swierstra's "data types à la carte" for combining instruction sets, and
Kiselyov and Ishii's freer monad for the programs); the effect runtime itself belongs to
ChuiTypes.

```jldoctest free
julia> using ChuiCore: Coproduct, Inl, Inr, inj, prj, liftF, Pure, Impure, Free, interpret, foldfree, cohandler, MaybeTag
```

## Two instruction sets

Instructions are structs, grouped under an abstract type per instruction set: a key-value store
and a log. They need no Functor instance.

```jldoctest free
julia> abstract type KV end

julia> struct Get <: KV; key::Symbol; end

julia> struct Put <: KV; key::Symbol; val::Int; end

julia> abstract type Log end

julia> struct Tell <: Log; msg::String; end
```

## Combining them: `Coproduct`, `inj`, `prj`

[`ChuiCore.Coproduct`](@ref ChuiCore.Coproduct)`{KV, Log}` is the signature "a `KV` or a `Log`
instruction". A value of it is an [`ChuiCore.Inl`](@ref ChuiCore.Inl) (left component) or an
[`ChuiCore.Inr`](@ref ChuiCore.Inr) (right). [`ChuiCore.inj`](@ref ChuiCore.inj) picks the right
injection from the instruction's type, and [`ChuiCore.prj`](@ref ChuiCore.prj) takes it back out
(`Some(x)` or `nothing`):

```jldoctest free
julia> const Sig = Coproduct{KV, Log};

julia> inj(Sig, Get(:a)) == Inl{KV, Log}(Get(:a)), inj(Sig, Tell("hi")) == Inr{KV, Log}(Tell("hi"))
(true, true)

julia> something(prj(Tell, inj(Sig, Tell("hi")))).msg, prj(Get, inj(Sig, Tell("hi")))
("hi", nothing)
```

For three or more sets, nest to the right: `Coproduct{KV, Coproduct{Log, Err}}`; `inj` and `prj`
find their way through the nesting.

## A program

[`ChuiCore.liftF`](@ref ChuiCore.liftF)`(Sig, op)` is the one-instruction program "perform `op`,
return its answer", with `op` injected into `Sig`. Smart constructors keep programs readable:

```jldoctest free
julia> kvget(k) = liftF(Sig, Get(k));

julia> kvput(k, v) = liftF(Sig, Put(k, v));

julia> tell(msg) = liftF(Sig, Tell(msg));
```

`chain(f, m)` runs `m`, then the program `f(answer)`; a `do` block reads in program order.
[`ChuiCore.Pure`](@ref ChuiCore.Pure)`(x)` ends a program with the result `x`:

```jldoctest free
julia> double(k) = chain(kvget(k)) do a
           chain(tell("$k is $a")) do _
               chain(kvput(k, 2a)) do _
                   Pure(2a)
               end
           end
       end;

julia> prog = chain(double(:a)) do x
           chain(double(:b)) do y
               Pure(x + y)
           end
       end;
```

Nothing has run. `prog` is a value: an [`ChuiCore.Impure`](@ref ChuiCore.Impure) holding its
first instruction and the rest of the program as a continuation (a finished program is a
`Pure`). Its first instruction can be inspected without running anything:

```jldoctest free
julia> prog isa Free, prog isa Impure
(true, true)

julia> prog.op
Inl{KV, Log}(Get(:a))
```

## Interpreter 1: run it

[`ChuiCore.interpret`](@ref ChuiCore.interpret)`(handler, prog)` runs the program: for each
instruction, `handler(op)` performs it and returns its answer. A handler is any callable, usually
one method per instruction type, and may hold state. For a coproduct signature,
[`ChuiCore.cohandler`](@ref ChuiCore.cohandler) combines one handler per component (`Inl`
payloads go to the first, `Inr` to the second):

```jldoctest free
julia> struct Store; d::Dict{Symbol, Int}; end

julia> (s::Store)(op::Get) = get(s.d, op.key, 0)

julia> (s::Store)(op::Put) = (s.d[op.key] = op.val; nothing)

julia> printlog(op::Tell) = println("log: ", op.msg);

julia> store = Store(Dict(:a => 1, :b => 10));

julia> interpret(cohandler(store, printlog), prog)
log: a is 1
log: b is 10
22

julia> store.d[:a], store.d[:b]
(2, 20)
```

## Interpreter 2: a pure test interpreter

The same program, run by a handler that touches no real store and records every instruction it
was asked to perform. A test can then check both the result and the exact trace:

```jldoctest free
julia> struct Recorder; answers::Dict{Symbol, Int}; trace::Vector{Any}; end

julia> (r::Recorder)(op::Get) = (push!(r.trace, op); r.answers[op.key])

julia> (r::Recorder)(op) = (push!(r.trace, op); nothing)

julia> rec = Recorder(Dict(:a => 5, :b => 7), Any[]);

julia> interpret(cohandler(rec, rec), prog)
24

julia> rec.trace
6-element Vector{Any}:
 Get(:a)
 Tell("a is 5")
 Put(:a, 10)
 Get(:b)
 Tell("b is 7")
 Put(:b, 14)
```

## Into another monad: `foldfree`

[`ChuiCore.foldfree`](@ref ChuiCore.foldfree)`(tag, nt, prog)` interprets into a monad: `nt`
maps each instruction to a monadic value of class `tag`, and the program's `chain`s become that
monad's `chain`. With Maybe, a missing key stops the whole program with `nothing`:

```jldoctest free
julia> maybeget(d) = op -> op isa Get ? (haskey(d, op.key) ? Some(d[op.key]) : nothing) : Some(nothing);

julia> foldfree(MaybeTag(), cohandler(maybeget(Dict(:a => 1, :b => 2)), _ -> Some(nothing)), prog)
Some(6)

julia> foldfree(MaybeTag(), cohandler(maybeget(Dict(:a => 1)), _ -> Some(nothing)), prog) === nothing
true
```

`foldfree` recurses through the target monad's `chain`, so with a strict monad (Maybe, Array) a
program of more than roughly 10^4 instructions can overflow the stack. `interpret` is a loop (a
trampoline) and runs 10^6 instructions in constant stack, in either bind association.

## Why describe a program apart from running it

- **Testing**: the program logic runs under a recording interpreter, with no real store, files
  or network, and the test checks the trace (interpreter 2).
- **Several meanings**: the same value runs for real, as a dry run, or into Maybe; choosing the
  interpreter is choosing the meaning.
- **Inspection**: a program is data. Its next instruction is visible before anything runs, so a
  planner can look at a program, rewrite it, or refuse it.
- **Effects stay explicit**: `liftF` and `chain` perform nothing; effects happen only inside the
  handlers, at the point where you call `interpret` or `foldfree`.

## What it costs

A program is data, and every instruction is a heap object plus a node in the continuation tree.
Measured for ChuiCore's implementation in phase 5 (BenchmarkTools medians of building and
`interpret`ing programs of 10^3 and 10^4 instructions with a counting handler, right- and
left-nested binds; Julia 1.13.2 and 1.10.12, one thread, a loaded shared machine): **≈0.16–0.45
µs and ≈130–270 B per interpreted instruction**. The research prototype measured ≈0.5–1.2 µs and
≈0.4–0.5 KB per instruction, 80–200× a plain `Dict` loop of ≈6 ns per step. Binding is O(1) in
both associations, so left-nested `chain`s stay linear (the classic `Free` encoding is
quadratic: 43–47 s against 5–12 ms at 10^4 left binds in the research measurement). Nothing
infers (`Any`). Use free monads to describe programs and plans, not for inner loops.
