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