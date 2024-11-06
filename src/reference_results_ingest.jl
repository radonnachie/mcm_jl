using Printf

struct ReferenceResult
    benchmark_name::String
    # file_ag::String
    # method::String
    min_ad::Bool
    time_s::Float64
    nof_adders::Int
    adder_depth::Int
    # wl_in
    # onebit
    # epsilon_max
    # wl_out_full
    # wl_out
    # epsilon_frac
    # luts
    # delay
    # power
end

function Base.show(io::IO, r::ReferenceResult)
    Printf.@printf(io,
        "ReferenceResult(%s in %0.3f s, Min(%s), N_a=%d, AD=%d)",
        r.benchmark_name,
        r.time_s,
        r.min_ad ? "AD" : "N_a+AD",
        r.nof_adders,
        r.adder_depth
    )
end

function readReferenceResults(filepath::String)::Vector{ReferenceResult}
    refs = Vector{ReferenceResult}()
    open(filepath) do file
        lines = readlines(file)
        for line in lines[2:end]
            line_data = split(line, ",")
            if strip(line_data[3]) != "mcm"
                continue
            end

            time_str = strip(line_data[5])
            while time_str[end] == '*'
                time_str = time_str[1:end-1]
            end

            push!(refs,
                ReferenceResult(
                    line_data[1], # benchmark_name
                    strip(line_data[4]) == "true", # min_ad
                    parse(Float64, time_str), # time_s
                    parse(Int, strip(line_data[6])), # nof_adders
                    parse(Int, strip(line_data[7])), # adder_depth
                )
            )
        end
    end
    refs
end

function getBestReferenceResults(filepath::String)
    best = Dict()
    for ref in readReferenceResults(filepath)
        if !haskey(best, ref.benchmark_name)
            best[ref.benchmark_name] = ref
        else
            best_naplusad = best[ref.benchmark_name].nof_adders + best[ref.benchmark_name].adder_depth
            ref_naplusad = ref.nof_adders + ref.adder_depth
            if best_naplusad < ref_naplusad
                continue
            end
            if best_naplusad == ref_naplusad && best[ref.benchmark_name].adder_depth < ref.adder_depth
                continue
            end
            best[ref.benchmark_name] = ref
        end
    end
    return best
end

if abspath(PROGRAM_FILE) == @__FILE__
    println(getBestReferenceResults("$(@__DIR__)/../reference_results.csv"))
end
