using Serialization
using Dates
using Statistics
using Printf
using MCM

reference_results = getBestReferenceResults("/work/data/reference_results.csv")

upperbound_methods = Dict(
    "uniqueterms" => number_of_adders_max_uniqueterms,
    "nonzeropairs" => number_of_adders_max_nonzeropairs
)
method_names = sort(collect(keys(upperbound_methods)))

open("/work/analyses/nof_adder_range.csv", "w") do fio
    @printf(fio, "%s\n", join(vcat([
        "benchmark_name",
        "NA",
        "NA_solved",
        "lower_bound",
        "upper_bound_ktree"
    ],
    [
        "upper_bound_$(method_name),range_status_$(method_name),range_ratio_$(method_name)"
        for method_name in method_names
    ]
    ), ",", ","))
end

struct UpperBoundDetails
    bound::Int
    ktree_range_ratio::Float32
    status::String

    function UpperBoundDetails(upper_bound::Int, lower_bound::Int, ktree_range::Int, known_nof_adders::Int, solved::Bool)
        status = "???"
        if known_nof_adders < 0
        elseif known_nof_adders < upper_bound
            status = "OK"
        elseif known_nof_adders == upper_bound
            status = solved ? "TIGHT" : "OK"
        elseif known_nof_adders > upper_bound
            status = solved ? "BAD" : "WARNING"
        end

        new(
            upper_bound,
            (upper_bound - lower_bound)/(ktree_range == 0 ? 1 : ktree_range),
            status
        )
    end
end

upperbounds_map = Dict{String, Vector{UpperBoundDetails}}(
    method => []
    for method in method_names
)

benchnames = []
    
for bench in readBenchmarkDetails("/work/data/benchmarks.csv")
    push!(benchnames, bench.name)
    coeff_roots = UInt.(preprocess_coefficients(bench.coefficients))

    nof_adder_inputs = 2

    min_adders = number_of_adders_min(coeff_roots; nof_adder_inputs=nof_adder_inputs)
    max_ktree = number_of_adders_max_ktree(coeff_roots; nof_adder_inputs=nof_adder_inputs)
    ktree_range = max_ktree-min_adders

    n_a = -1
    solved = false
    if haskey(reference_results, bench.name)
        ref = reference_results[bench.name]
        n_a = ref.nof_adders
        solved = ref.solved
    end
    
    for (method_name, method) in upperbound_methods
        upperbound = method(coeff_roots; nof_adder_inputs=nof_adder_inputs)
        push!(
            upperbounds_map[method_name],
            UpperBoundDetails(
                upperbound,
                min_adders,
                ktree_range,
                n_a,
                solved
            )    
        )
    end

    @printf("%s (N_A = %d, %sSolved): [%d, {%d,%s}]", 
        bench.name,
        n_a,
        solved ? "" : "Not ",
        min_adders,
        max_ktree,
        join([
            upperbounds_map[method_name][end].bound
            for method_name in method_names
        ], ",", ",")
    )

    for method_name in method_names
        @printf("\n\t%s: delta=%d, range ratio %03.2f%%\t%s",
            method_name,
            max_ktree - upperbounds_map[method_name][end].bound,
            100*upperbounds_map[method_name][end].ktree_range_ratio,
            upperbounds_map[method_name][end].status,
        )
    end
    println()

    open("/work/analyses/nof_adder_range.csv", "a") do fio
        @printf(fio, "%s,%d,%s,%d,%d,%s\n",
            bench.name,
            n_a,
            solved,
            min_adders,
            max_ktree,
            join([
                @sprintf("%d,%s,%0.6f",
                    upperbounds_map[method_name][end].bound,
                    upperbounds_map[method_name][end].status,
                    upperbounds_map[method_name][end].ktree_range_ratio,
                )
                for method_name in method_names
            ], ",", ",")
        )
    end
end

println()
for method_name in method_names
    rangeratios = [d.ktree_range_ratio for d in upperbounds_map[method_name]]
    println("$(method_name): min=$(minimum(filter(x->x>0, rangeratios))), mean=$(sum(rangeratios)/length(rangeratios)), max=$(maximum(rangeratios)), stdev=$(std(rangeratios))")
end
flush(stdout)