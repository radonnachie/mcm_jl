using ArgParse
using Serialization
using Dates
using Printf
using MCM

benchmarks = readBenchmarkDetails("/work/data/benchmarks.csv")
benchmark_names = [bench.name for bench in benchmarks]
sort!(benchmark_names)

open("/work/model_weights.csv", "w") do fio
    @printf(fio, "mcmparam,%s\n", join(benchmark_names, ","))
end

default_param_key = nothing
param_key_map_weights = Dict{String, Vector{ModelWeight}}()

for mcm_param_tuple in Iterators.product(
    # MCMLiftingConstraintsSelection
    [false, true], # adder_msd_complex_sorted_coefficient_lock
    [false, true], # adder_one_input_noshift
    [false, true], # unique_sums
    # MCMConstraintOptions
    [false, true], # sign_selection_direct_not_inferred
    [false, true], # use_indicator_constraints_not_big_m
)
    lifting_constraints=MCMLiftingConstraintsSelection(
        adder_msd_complex_sorted_coefficient_lock=mcm_param_tuple[1],
        adder_one_input_noshift=mcm_param_tuple[2],
        unique_sums=mcm_param_tuple[3],
    )
    constraint_options=MCMConstraintOptions(
        sign_selection_direct_not_inferred=mcm_param_tuple[4],
        use_indicator_constraints_not_big_m=mcm_param_tuple[5]
    )
    mcm_param = MCMParam(
        lifting_constraints=lifting_constraints,
        constraint_options=constraint_options
    )
    param_key = mcm_run_parameters_key(mcm_param)
    if lifting_constraints == MCMLiftingConstraintsSelection() && constraint_options == MCMConstraintOptions()
        global default_param_key = param_key
    end

    weights = []
    for bench in benchmarks
        if bench.number_of_unique_coefficients > 0
            coeff_roots = preprocess_coefficients(bench.coefficients)
            model = mcm_model(
                coeff_roots,
                mcm_param
            )
            
            num_linear_constraints = 0
            for (F, S) in MCM.list_of_constraint_types(model)
                n = MCM.num_constraints(model, F, S)
                num_linear_constraints += n
                # println(sprint(MCM.MOI.Utilities.print_with_acronym, "$F in $S: $n"))
            end
            push!(
                weights,
                ModelWeight(
                    nof_linear_constraints=num_linear_constraints,
                    nof_nonlinear_constraints=MCM.num_nonlinear_constraints(model),
                )
            )
        end
    end
    param_key_map_weights[param_key] = weights
end

param_keys = [default_param_key]
non_default_keys = [k for k in keys(param_key_map_weights) if k != default_param_key]
sort!(non_default_keys)
append!(param_keys, non_default_keys)

open("/work/model_weights.csv", "a") do fio
    for param_key in param_keys
        @printf(fio, "%s,%s\n", param_key, join(to_csv_elem.(param_key_map_weights[param_key]), ","))
    
    end
end
