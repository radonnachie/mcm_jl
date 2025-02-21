using ArgParse
using Serialization
using Dates
using Printf
using MCM

helpstring_category_selection = "Hyphenate each category selection as a finality-objectivity pair. Use an asterisk to indicate all of either."
argconf = ArgParseSettings()
@add_arg_table argconf begin
	"--category-selection", "-c"
		help = @sprintf("Selectively run benchmarks with these result comparison categories. %s", helpstring_category_selection)
		arg_type = String
		nargs = '*'
        default = ["*-*"]
	"--no-presolve"
		help = "Disable the presolve."
        action = "store_false"
	"--no-integrality-focus"
		help = "Disable IntegralityFocus. Not recommended."
        action = "store_false"
	"--no-coefficient-lock"
		help = "Disable lifting constraint which locks the coefficients."
        action = "store_false"
	"--no-unique-sums"
		help = "Disable lifting constraint which requires unique sums."
        action = "store_false"
	"--no-big-m"
		help = "Use indicator constraints instead of big-M constraints."
        action = "store_true"
end
@show args = parse_args(ARGS, argconf)

category_selection_set = []
for category_str in args["category-selection"]
    if cmp(category_str, "nothing") == 0
        continue
    end
    @assert occursin("-", category_str) helpstring_category_selection
    finality_str, objectivity_str = split(category_str, "-")
    finality_list = cmp(finality_str, "*") == 0 ? instances(FinalityCategory) : [MCM.FinalityCategoryStringMap[finality_str]]
    objectivity_list = cmp(objectivity_str, "*") == 0 ? instances(ObjectivityCategory) : [MCM.ObjectivityCategoryStringMap[objectivity_str]]
    for finality in finality_list
        for objectivity in objectivity_list
            push!(
                category_selection_set,
                ComparitiveCategory(finality, objectivity)
            )
        end
    end
end

benchmarks_to_process = []

open("/work/resultsummary_comparison.csv") do file
    lines = readlines(file)
    for line in lines[2:end]
        result = SummarisedComparitiveResultsMCM(line)
        if length(category_selection_set) == 0
        elseif !(result.comparison in category_selection_set)
            continue
        end
        push!(benchmarks_to_process, result.benchmark_name)
    end
end

benchmarks = readBenchmarkDetails("/work/data/benchmarks.csv")

param = GurobiParam(
    Presolve=args["no-presolve"],
    IntegralityFocus=args["no-integrality-focus"],
)
mcm_param = MCMParam(
    lifting_constraints=MCMLiftingConstraintsSelection(
        adder_msd_complex_sorted_coefficient_lock=args["no-coefficient-lock"],
        unique_sums=args["no-unique-sums"],
    ),
    constraint_options=MCMConstraintOptions(
        use_indicator_constraints_not_big_m=args["no-big-m"]
    )
)

now_str = Dates.format(Dates.now(), "Y-m-d_H-M-S")

for bench in benchmarks
    if bench.number_of_unique_coefficients > 0
        if !(bench.name in benchmarks_to_process)
            continue
        end

        coeff_roots = preprocess_coefficients(bench.coefficients)
        println("\n$(bench.name): $(coeff_roots)")
        model = mcm_model(
            coeff_roots,
            mcm_param
        )
        ts_end = time_ns()
        results = MCM.optimize!(model;
            # gurobi=param
            optimizer_factory=HiGHS.Optimizer
        )
        ts_start = time_ns()
        @show results

        open("/work/results_$(now_str).jls", "a") do fio
            serialize(fio,
                ResultsKey(
                    timestamp=Dates.now(),
                    benchmark_name=bench.name,
                    gurobi_parameters=param,
                    mcm_parameters=mcm_param,
                    solved_fully=MCM.is_solved_and_feasible(model),
                    feasible=!(MCM.termination_status(model) in [MCM.INFEASIBLE, MCM.INFEASIBLE_OR_UNBOUNDED, MCM.INFEASIBLE_POINT]),
                    elapsed_ns=ts_end-ts_start,
                ) => results
            )
        end
        ## cool computer down period
        sleep(div(param.TimeLimit, 60))
    end
end
