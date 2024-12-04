using Serialization
using Dates
using Printf
using MCM

benchmarks = readBenchmarkDetails("/work/data/benchmarks.csv")

param = GurobiParam(
    TimeLimit=300,
    Presolve=1,
    IntegralityFocus=1,
    MIPFocus=0, # https://www.gurobi.com/documentation/current/refman/mipfocus.html#parameter:MIPFocus
    ConcurrentMIP=4
)

now_str = Dates.format(Dates.now(), "Y-m-d_H-M-S")

for bench in benchmarks
    if bench.number_of_unique_coefficients > 0
        for obj in [MCM.MinAdderCountPlusMaxAdderDepth] #instances(ObjectiveMCM)
            model = getGurobiModelMILP(;
                param=param
            )

            coeff_roots = preprocess_coefficients(bench.coefficients)
            min_adders, max_adders = number_of_adders_minmax(UInt.(coeff_roots); nof_adder_inputs=2)

            bit_width = ceil(Int, log2(maximum(coeff_roots)))
            mcm_param = MCMParam(
                min_nof_adders=min_adders,
                max_nof_adders=max_adders,
                nof_adder_inputs=2,
                data_bit_width=bit_width,
                maximum_shift=bit_width,
                lifting_constraints=MCMLiftingConstraintsSelection(
                    adder_msd_complex_sorted_coefficient_lock=true,
                    adder_one_input_noshift=true,
                    unique_sums=true
                ),
                constraint_options=MCMConstraintOptions(
                    sign_selection_direct_not_inferred=true,
                    use_indicator_constraints_not_big_m=false
                ),
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
                        solved_fully=MCM.is_solved_and_feasible(model),
                        elapsed_ns=ts_end-ts_start,
                    ) => results
                )
            end
            ## cool computer down period
            sleep(div(param.TimeLimit, 60))
        end
    end
end
