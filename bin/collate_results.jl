using Serialization
using Dates
using Printf
using MCM

function is_result_better(best::Union{Pair{ResultsKey, ResultsMCM}, Nothing}, candidate::Pair{ResultsKey, ResultsMCM})::Bool
    if isnothing(best)
        return true
    end
    best_result_key, best_result = best
    candidate_result_key, candidate_result = candidate
    
    best_obj = best_result.depth_max + best_result.adder_count
    candidate_obj = candidate_result.depth_max + candidate_result.adder_count

    # take better solution
    if best_obj < candidate_obj
        return false
    end
    # take shallower solution
    if best_obj == candidate_obj && best_result.depth_max < candidate_result.depth_max
        return false
    end
    # take shorter solve time (integer seconds resolution)
    if div(best_result_key.elapsed_ns, 1e9) < div(candidate_result_key.elapsed_ns, 1e9)
        return false
    end
    
    return true
end


bench_best_resultpairs = Dict{String, Pair{ResultsKey, ResultsMCM}}()
benchmarks_solvedin = Dict{String, Vector{String}}()
runparam_benchmark_best_results = Dict{Tuple{MCMParam, GurobiParam}, Dict{String, Pair{ResultsKey, ResultsMCM}}}()

for f in readdir("/work/")
    if startswith(f, "results_")
        open("/work/"*f, "r") do fio
            while !eof(fio)
                result_key, results = deserialize(fio)
                benchname = result_key.benchmark_name

                if !haskey(benchmarks_solvedin, benchname)
                    benchmarks_solvedin[benchname] = Vector{String}()
                end
                if length(results) > 0 && !(f in benchmarks_solvedin[benchname])
                    push!(benchmarks_solvedin[benchname], f)
                end

                for (i,r) in enumerate(results)
                    result_pair = (result_key => r)
                    if is_result_better(
                        get(bench_best_resultpairs, benchname, nothing),
                        result_pair
                    )
                        bench_best_resultpairs[benchname] = result_pair
                    end

                    runparam_tuple = (result_key.mcm_parameters, result_key.gurobi_parameters)
                    runparam_bench_dict = get(runparam_benchmark_best_results, runparam_tuple, Dict{String, Pair{ResultsKey, ResultsMCM}}())
                    if is_result_better(
                        get(runparam_bench_dict, benchname, nothing),
                        result_pair
                    )
                        runparam_bench_dict[benchname] = result_pair
                    end
                    runparam_benchmark_best_results[runparam_tuple] = runparam_bench_dict
                end
            end
        end
    end
end

benchmark_names = [bench.name for bench in readBenchmarkDetails("/work/data/benchmarks.csv")]
sort!(benchmark_names)

default_runparam_tuple = (MCMParam(), GurobiParam())
@assert haskey(runparam_benchmark_best_results, default_runparam_tuple)
defaultrunparam_benchmark_results = runparam_benchmark_best_results[default_runparam_tuple]

runparam_keys = [k for k in keys(runparam_benchmark_best_results) if k != default_runparam_tuple]
sort!(runparam_keys, by=rk->mcm_run_parameters_key(rk...))
pushfirst!(runparam_keys, default_runparam_tuple)

open("/work/resultsummary_alternatives.csv", "w") do fio
    @printf(fio, "runparam,score,compcat_tallies,%s\n", join(benchmark_names, ","))
    for runparam_key in runparam_keys
        runparam_key_str = mcm_run_parameters_key(runparam_key...)
        println(runparam_key_str)
        
        line = ""
        
        comparitive_counts = Dict{ComparitiveCategory, Int}(
            c => 0
            for c in MCM.ComparitiveCategoryInstances
        )

        runparam_benchmark_results = runparam_benchmark_best_results[runparam_key]
        for benchname in benchmark_names
            default_summres = haskey(defaultrunparam_benchmark_results, benchname) ? SummarisedResultsMCM(defaultrunparam_benchmark_results[benchname]) : nothing
            run_summres = haskey(runparam_benchmark_results, benchname) ? SummarisedResultsMCM(runparam_benchmark_results[benchname]) : nothing

            comparison = all(isnothing.((default_summres, run_summres))) ? nothing : ComparitiveCategory(default_summres, run_summres)
            println("\t$(benchname) -> $(comparison)")
            line *= @sprintf("%s,", comparison)
            if !isnothing(comparison)
                comparitive_counts[comparison] += 1
            end
        end
        line = line[1:end-1]

        score_rational = score(comparitive_counts)
        score_str = @sprintf("%06d//%034d", numerator(score_rational), denominator(score_rational))
        comparison_tally_str = join(
            [
                @sprintf(
                    "%s%02d",
                    shorthand(c),
                    comparitive_counts[c]
                )
                for c in MCM.ComparitiveCategoryInstancesAscending
            ],
            ":"
        )
        line = join([runparam_key_str, score_str, comparison_tally_str, line], ",")*"\n"
        print(fio, line)
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
        @printf(fio, "%s => (%s) %s\n", benchname, mcm_run_parameters_key(entry.first), entry)
    end
end


reference_results = getBestReferenceResults("/work/data/reference_results.csv")
println("\nResults Comparison\n"*("-"^20))
open("/work/resultsummary_comparison.csv", "w") do fio
    first = true
    for benchname in benchmark_names
        result = haskey(bench_best_resultpairs, benchname) ? SummarisedResultsMCM(
            bench_best_resultpairs[benchname]
        ) : nothing
        refresult = haskey(reference_results, benchname) ? SummarisedResultsMCM(reference_results[benchname]) : nothing

        summary = SummarisedComparitiveResultsMCM(benchname, refresult, result)
        println(summary)
        @printf(fio, "%s\n", to_csv_line(summary; prefix_header=first))
        first = false
    end
end
