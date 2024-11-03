using Serialization
using Dates
include("$(@__DIR__)/structs.jl")
include("$(@__DIR__)/mcm.jl")
include("$(@__DIR__)/benchmark_ingest.jl")

bench_best_resultpairs = Dict()

for f in readdir("/work/")
    if startswith(f, "results_")
        open("/work/"*f, "r") do fio
            while !eof(fio)
                kp = deserialize(fio)
                for (i,r) in enumerate(kp.second)
                    if !haskey(bench_best_resultpairs, kp.first.benchmark_name)
                        bench_best_resultpairs[kp.first.benchmark_name] = (kp.first => r)
                    else
                        best_result = bench_best_resultpairs[kp.first.benchmark_name].second
                        best_obj = best_result.depth_max + best_result.adder_count
                        this_obj = r.depth_max + r.adder_count
                        if best_obj > this_obj
                            bench_best_resultpairs[kp.first.benchmark_name] = (kp.first => r)
                        end
                    end
                end
            end
        end
    end
end

for kv in bench_best_resultpairs
    println(kv)
end