using Serialization
using Dates
using Printf
using MCM

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
                        if best_obj == this_obj && best_result.depth_max < r.depth_max
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

println("\nBest Results\n"*("-"^20))
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


reference_results = getBestReferenceResults("/work/data/reference_results.csv")
println("\nResults Comparison\n"*("-"^20))
open("/work/resultsummary_comparison.csv", "w") do fio
    first = true
    for benchname in benchmark_names
        result = haskey(bench_best_resultpairs, benchname) ? SummarisedResultsMCM(
            solved = bench_best_resultpairs[benchname].first[2].solved_fully,
            nof_adders = bench_best_resultpairs[benchname].second.adder_count,
            adder_depth = bench_best_resultpairs[benchname].second.depth_max,
        ) : nothing
        refresult = haskey(reference_results, benchname) ? SummarisedResultsMCM(reference_results[benchname]) : nothing

        summary = SummarisedComparitiveResultsMCM(benchname, refresult, result)
        println(summary)
        @printf(fio, "%s\n", to_csv_line(summary; prefix_header=first))
        first = false
    end
end
