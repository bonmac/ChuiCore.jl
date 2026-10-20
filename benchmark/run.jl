#!/usr/bin/env julia
# run.jl: run benchmark/benchmarks.jl once on this checkout and print a table (median time,
# minimum time, allocations, memory) for docs/ and HANDOFF.md (ADR-0009). The regression gate is
# AirspeedVelocity in CI and `julia scripts/ci.jl bench` locally; this script only reports.
#
#   julia +release benchmark/run.jl [--out FILE] [--check]
#   julia +lts     benchmark/run.jl [--out FILE] [--check]
#
# `--check` compares each median with benchmark/budgets.toml [time] (ADR-0009 §2), exits 1 when
# one is over budget or a SUITE entry and the budget rows do not match one to one.
#
# Like scripts/ci.jl, it develops the checkout into a scratch copy of benchmark/Project.toml, so
# no tracked file is rewritten.
const ROOT = normpath(joinpath(@__DIR__, ".."))

if get(ENV, "CHUI_BENCH_CHILD", "") != "1"
    env = mktempdir()
    cp(joinpath(ROOT, "benchmark", "Project.toml"), joinpath(env, "Project.toml"))
    jl = `$(Base.julia_cmd().exec[1]) --startup-file=no --project=$env`
    run(pipeline(`$jl -e 'using Pkg; Pkg.develop(path = ARGS[1]); Pkg.instantiate()' $ROOT`; stdout = devnull, stderr = devnull))
    p = run(ignorestatus(addenv(`$jl $(@__FILE__) $ARGS`, "CHUI_BENCH_CHILD" => "1")))
    exit(p.exitcode)
end

using TOML: TOML
include(joinpath(ROOT, "benchmark", "benchmarks.jl"))
tune!(SUITE)
res = run(SUITE; verbose = false)
med, mn = median(res), minimum(res)
rows = Tuple{String, Float64, Float64, Int, Int}[]
walk(g, p, m) = g isa BenchmarkGroup ?
    foreach(k -> walk(g[k], isempty(p) ? string(k) : p * "/" * string(k), m[k]), collect(keys(g))) :
    push!(rows, (p, time(g), time(m), allocs(g), memory(g)))
for k in keys(med)
    walk(med[k], string(k), mn[k])
end
sort!(rows; by = first)
io = IOBuffer()
println(
    io, "julia ", VERSION, " | ", Sys.cpu_info()[1].model, " | threads ", Threads.nthreads(),
    " | load average ", round.(Sys.loadavg(); digits = 2)
)
println(io, "| benchmark | median | minimum | allocs | memory |")
println(io, "|---|---:|---:|---:|---:|")
ns(t) = t < 1.0e3 ? string(round(t; digits = 1), " ns") : t < 1.0e6 ? string(round(t / 1.0e3; digits = 2), " μs") :
    string(round(t / 1.0e6; digits = 2), " ms")
for (name, t, tmin, a, m) in rows
    println(io, "| ", name, " | ", ns(t), " | ", ns(tmin), " | ", a, " | ", m, " B |")
end
ok = true
if "--check" in ARGS
    # ADR-0009 §2: every SUITE entry has a budget row, and every row names a SUITE entry.
    tables = TOML.parsefile(joinpath(ROOT, "benchmark", "budgets.toml"))["time"]
    budget = get(tables, "$(VERSION.major).$(VERSION.minor)", tables["1.10"])
    suite_keys = Set(first.(rows))
    println(io, "\n| benchmark | median | budget | |\n|---|---:|---:|---|")
    for (name, t) in rows
        b = get(budget, name, nothing)
        verdict = b === nothing ? "NO BUDGET ROW" : t <= b ? "OK" : "OVER BUDGET"
        global ok &= verdict == "OK"
        println(io, "| ", name, " | ", ns(t), " | ", b === nothing ? "—" : ns(b), " | ", verdict, " |")
    end
    for name in sort!(collect(setdiff(keys(budget), suite_keys)))
        global ok = false
        println(io, "| ", name, " | — | ", ns(budget[name]), " | NOT IN SUITE |")
    end
    println(io, ok ? "\nrun.jl --check: OK ($(length(rows)) benchmarks within budget)" : "\nrun.jl --check: FAILED")
end
s = String(take!(io))
print(s)
i = findfirst(==("--out"), ARGS)
i === nothing || write(ARGS[i + 1], s)
exit(ok ? 0 : 1)
