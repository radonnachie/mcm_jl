using Printf

struct BenchmarkDetails
    name::String
    wordlength::UInt
    number_of_coefficients::UInt
    number_of_unique_coefficients::UInt
    coefficients::Vector{Int}
    unique_coefficients::Vector{Int}
end

function Base.show(io::IO, bd::BenchmarkDetails)
    Printf.@printf(io,
        "BenchmarkDetails(%s, W=%d, Nc=%d>=%d, %s, %s)",
        bd.name,
        bd.wordlength,
        bd.number_of_coefficients,
        bd.number_of_unique_coefficients,
        bd.coefficients,
        bd.unique_coefficients
    )
end

function readBenchmarkDetails(filepath::String)::Vector{BenchmarkDetails}
    benchmarks = Vector{BenchmarkDetails}()
    open(filepath) do file
        lines = readlines(file)
        for line in lines[2:end]
            line_data = split(line, ",")
            push!(benchmarks,
            BenchmarkDetails(
                line_data[1], # name
                # line_data[2], # filter_type
                parse(Int, line_data[3]), # wordlength
                parse(Int, line_data[4]), # number_of_coefficients
                parse(Int, line_data[5]), # number_of_unique_coefficients
                parse.(Int, split(line_data[6])), # coefficients
                parse.(Int, split(line_data[7]))) # unique_coefficients
            )
        end
    end
    benchmarks
end

if abspath(PROGRAM_FILE) == @__FILE__
    println(readBenchmarkDetails("$(@__DIR__)/benchmarks.csv"))
end
