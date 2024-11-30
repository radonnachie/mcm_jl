using Printf
include("$(@__DIR__)/structs.jl")

function readReferenceResults(filepath::String)::Vector{ReferenceResult}
    refs = Vector{ReferenceResult}()
    open(filepath) do file
        lines = readlines(file)
        for line in lines[2:end]
            line_data = split(line, ",")
            if strip(line_data[3]) != "mcm"
                continue
            end

            solved = true
            time_str = strip(line_data[5])
            while time_str[end] == '*'
                time_str = time_str[1:end-1]
                solved = false
            end

            push!(refs,
                ReferenceResult(
                    line_data[1], # benchmark_name
                    strip(line_data[4]) == "true", # min_ad
                    parse(Float64, time_str), # time_s
                    solved, # solved
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
