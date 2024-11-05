using Serialization
using Dates
include("$(@__DIR__)/structs.jl")
include("$(@__DIR__)/mcm.jl")
include("$(@__DIR__)/csd.jl")
include("$(@__DIR__)/benchmark_ingest.jl")

function get_odd_factor(v::Int)::Int
    while v != 0 && mod(v, 2) == 0
        v = div(v, 2)
    end
    v
end

function get_coefficient_roots(coeffs::Vector{Int})::Vector{Int}
    filter!(
        x -> x > 1,
        unique!(
            get_odd_factor.(abs.(coeffs))
        )
    )
end

benchmarks = readBenchmarkDetails("/work/data/benchmarks.csv")

param = GurobiParam(
    TimeLimit=300,
    Presolve=0,
    IntegralityFocus=1,
    MIPFocus=1, # https://www.gurobi.com/documentation/current/refman/mipfocus.html#parameter:MIPFocus
    ConcurrentMIP=4
)

now_str = Dates.format(Dates.now(), "Y-m-d_H-M-S")

for bench in benchmarks
    if bench.number_of_unique_coefficients > 0
        for obj in [MinAdderCountPlusMaxAdderDepth] #instances(ObjectiveMCM)
            model = getGurobiModelMILP(;
                param=param
            )

            coeff_roots = get_coefficient_roots(bench.coefficients)
            min_adders, max_adders = number_of_adders_minmax(UInt.(coeff_roots))

            bit_width = ceil(Int, log2(maximum(coeff_roots)))
            mcm_param = MCMParam(
                min_nof_adders=min_adders,
                max_nof_adders=max_adders,
                nof_adder_inputs=2,
                data_bit_width=bit_width,
                maximum_shift=bit_width,
                objective=obj,
            )

            println("\n$(bench.name): $(mcm_param): $(coeff_roots)")

            ts_start = time_ns()
            results = mcm!(
                model,
                coeff_roots,
                mcm_param
            )
            ts_end = time_ns()
            @show results
            
            open("/work/results_$(now_str).jls", "a") do fio
                serialize(fio,
                    ResultsKey(
                        timestamp=Dates.now(),
                        benchmark_name=bench.name,
                        gurobi_parameters=param,
                        mcm_parameters=mcm_param,
                        elapsed_ns=ts_end-ts_start,
                    ) => results
                )
            end
        end
    end
end
