using Serialization
using Dates
include("$(@__DIR__)/structs.jl")
include("$(@__DIR__)/mcm.jl")
include("$(@__DIR__)/csd.jl")
include("$(@__DIR__)/benchmark_ingest.jl")

benchmarks = readBenchmarkDetails("/work/data/benchmarks.csv")

param = GurobiParam(
    TimeLimit=600,
    Presolve=1,
    IntegralityFocus=1,
    MIPFocus=1, # https://www.gurobi.com/documentation/current/refman/mipfocus.html#parameter:MIPFocus
    ConcurrentMIP=6
)

now_str = Dates.format(Dates.now(), "Y-m-d_H-M-S")

for bench in benchmarks
    if bench.number_of_unique_coefficients > 0
        for obj in [MinAdderCountPlusMaxAdderDepth, MinAdderDepthSum] #instances(ObjectiveMCM)
            model = getGurobiModelMILP(;
                param=param
            )

            max_nof_adders = sum(count_components.(
                csd.(UInt.(abs.(bench.unique_coefficients)))
            ))

            ts_start = time_ns()
            results = mcm(
                model,
                bench.unique_coefficients;
                nof_adders=max_nof_adders,
                data_bit_width=Int(bench.wordlength),
                objective=obj
            )
            ts_end = time_ns()
            @show results
            
            open("/work/results_$(now_str).jls", "a") do fio
                serialize(fio,
                    ResultsKey(
                        timestamp=Dates.now(),
                        benchmark_name=bench.name,
                        gurobi_parameters=param,
                        objective=obj,
                        elapsed_ns=ts_end-ts_start,
                    ) => results
                )
            end
        end
    end
end
