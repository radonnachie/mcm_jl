using Serialization
using Dates
include("$(@__DIR__)/structs.jl")
include("$(@__DIR__)/mcm.jl")
include("$(@__DIR__)/benchmark_ingest.jl")

bench_best_resultpairs = Dict()
benchmarks_solvedin = Dict()

for f in readdir("/work/")
    if startswith(f, "results_")
        open("/work/"*f, "r") do fio
            while !eof(fio)
                kp = deserialize(fio)
                benchname = kp.first.benchmark_name

                if !haskey(benchmarks_solvedin, benchname)
                    benchmarks_solvedin[benchname] = Vector{String}()
                end
                if length(kp.second) > 0 && !(f in benchmarks_solvedin[benchname])
                    push!(benchmarks_solvedin[benchname], f)
                end

                for (i,r) in enumerate(kp.second)
                    if !haskey(bench_best_resultpairs, benchname)
                        bench_best_resultpairs[benchname] = ((f, kp.first) => r)
                    else
                        best_result = bench_best_resultpairs[benchname].second
                        best_obj = best_result.depth_max + best_result.adder_count
                        this_obj = r.depth_max + r.adder_count
                        if best_obj < this_obj
                            continue
                        end
                        if best_obj == this_obj && best_result.depth_max <= r.depth_max
                            continue
                        end
                        
                        bench_best_resultpairs[benchname] = ((f, kp.first) => r)
                    end
                end
            end
        end
    end
end

benchmark_names = [bench.name for bench in readBenchmarkDetails("/work/data/benchmarks.csv")]
sort!(benchmark_names)

println()
println("Benchmarks Solved In:\n"*("-"^20))
open("/work/resultsummary_benchsolutions.txt", "w") do fio
    for benchname in benchmark_names
        if !(haskey(benchmarks_solvedin, benchname))
            @printf(fio, "%s => %s\n", benchname, nothing)
            continue
        end
        entry = benchmarks_solvedin[benchname]
        println(benchname => entry)
        @printf(fio, "%s => %s\n", benchname, entry)
    end
end

println("Best Results\n"*("-"^20))
open("/work/resultsummary_bestresults.txt", "w") do fio
    for benchname in benchmark_names
        if !(haskey(bench_best_resultpairs, benchname))
            @printf(fio, "%s => %s\n", benchname, nothing)
            continue
        end
        entry = bench_best_resultpairs[benchname]
        println(benchname => entry)
        @printf(fio, "%s => %s\n", benchname, entry)
    end
end
