using Serialization
using Dates
include("$(@__DIR__)/structs.jl")
include("$(@__DIR__)/mcm.jl")
include("$(@__DIR__)/csd.jl")
include("$(@__DIR__)/benchmark_ingest.jl")
include("$(@__DIR__)/reference_results_ingest.jl")

reference_results = getBestReferenceResults("/work/data/reference_results.csv")

open("/work/analyses/nof_adder_range.csv", "w") do fio
    @printf(fio, "%s\n", join([
        "benchmark_name",
        "NA",
        "NA_solved",
        "lower_bound",
        "upper_bound_bintree",
        "upper_bound_uniqueterms",
        "status_uniqueterms"
    ]))
end

for bench in readBenchmarkDetails("/work/data/benchmarks.csv")
    coeff_roots = UInt.(preprocess_coefficients(bench.coefficients))

    nof_adder_inputs = 2

    min_adders = number_of_adders_min(coeff_roots; nof_adder_inputs=nof_adder_inputs)
    max_ktree = number_of_adders_max_ktree(coeff_roots; nof_adder_inputs=nof_adder_inputs)
    max_uniqueterms = number_of_adders_max_uniqueterms(coeff_roots; nof_adder_inputs=nof_adder_inputs)

    ktree_range = max_ktree-min_adders
    uniqueterms_range = max_uniqueterms-min_adders

    range_status_uniqueterms = "????"
    n_a = 0
    solved = false
    if haskey(reference_results, bench.name)
        ref = reference_results[bench.name]
        n_a = ref.nof_adders
        solved = ref.solved
        if n_a < max_uniqueterms
            range_status_uniqueterms = "OK"
        elseif n_a == max_uniqueterms
            range_status_uniqueterms = solved ? "just OK" : "OK"
        elseif n_a > max_uniqueterms
            range_status_uniqueterms = solved ? "BAD" : "WARNING"
        end
    end
    @printf("%s (N_A = %d, %sSolved): [%d, {%d,%d}]\tdelta=%d, range change %03.2f%%\t%s\n", 
        bench.name,
        n_a,
        solved ? "" : "Not ",
        min_adders,
        max_ktree,
        max_uniqueterms,
        max_ktree - max_uniqueterms,
        ktree_range == 0 ? 0.0 : 100*uniqueterms_range/ktree_range,
        range_status_uniqueterms
    )

    open("/work/analyses/nof_adder_range.csv", "a") do fio
        @printf(fio, "%s,%d,%s,%d,%d,%d,%s\n",
            bench.name,
            n_a,
            solved,
            min_adders,
            max_ktree,
            max_uniqueterms,
            range_status_uniqueterms,
        )
    end
end
