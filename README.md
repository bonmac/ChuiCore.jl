# ChuiCore.jl

The functional-programming core of the Chui ecosystem: composition, algebraic structures as
Holy traits with reusable law-test kits, monoids, recursion schemes, laziness and optics.
It depends on no other Chui package.

**Status:** pre-release scaffold (version 0.0.1, unregistered). Nothing is exported yet.

## Development

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
julia scripts/ci.jl --list      # every CI job, runnable locally
```

Agent and process instructions: [`CLAUDE.md`](CLAUDE.md). Current state: [`HANDOFF.md`](HANDOFF.md).

## License

MIT; see [`LICENSE`](LICENSE).
