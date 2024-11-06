using Serialization
using Dates
include("$(@__DIR__)/structs.jl")
include("$(@__DIR__)/mcm.jl")
include("$(@__DIR__)/benchmark_ingest.jl")
include("$(@__DIR__)/reference_results_ingest.jl")

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
    @printf(fio, "benchmark_name,ref_nof_adders,ref_adder_depth,our_nof_adders,our_adder_depth,comparison\n")
    for benchname in benchmark_names
        no_result = !(haskey(bench_best_resultpairs, benchname))
        no_refresult = !(haskey(reference_results, benchname))
        print(benchname, " => ")
        csv_line = @sprintf("%s", benchname)
        
        if no_refresult
            print("Nothing")
            csv_line = csv_line*",,"
        else
            r = reference_results[benchname]
            print(@sprintf("ReferenceResult(N_a=%03d, AD=%03d)", r.nof_adders, r.adder_depth))
            csv_line = @sprintf("%s,%d,%d", csv_line, r.nof_adders, r.adder_depth)
        end
        print("\tVS\t")
        if no_result
            print("Nothing")
            csv_line = csv_line*",,"
        else
            r = bench_best_resultpairs[benchname].second
            print(@sprintf("ResultMCM(N_a=%03d, AD=%03d)", r.adder_count, r.depth_max))
            csv_line = @sprintf("%s,%d,%d", csv_line, r.adder_count, r.depth_max)
        end
        
        if no_result && no_refresult
            print("\texcused")
            csv_line = csv_line*",excused"
        elseif no_result
            print("\tmissing")
            csv_line = csv_line*",missing"
        elseif no_refresult
                print("\tnovel")
                csv_line = csv_line*",novel"
        else
            ref = reference_results[benchname]
            res = bench_best_resultpairs[benchname].second
            ref_obj = ref.nof_adders + ref.adder_depth
            res_obj = res.adder_count + res.depth_max

            if ref_obj < res_obj
                print("\tworse")
                csv_line = csv_line*",worse"
            elseif ref_obj > res_obj
                print("\tbetter")
                csv_line = csv_line*",better"
            elseif ref.adder_depth > res.depth_max
                print("\tshallower")
                csv_line = csv_line*",shallower"
            elseif ref.nof_adders > res.adder_count
                print("\tnarrower")
                csv_line = csv_line*",narrower"
            else
                print("\tequal")
                csv_line = csv_line*",equal"
            end

        end

        println()

        @printf(fio, "%s\n", csv_line)
    end
end
