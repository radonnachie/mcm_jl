using Serialization
using Dates
include("$(@__DIR__)/structs.jl")
include("$(@__DIR__)/mcm.jl")
include("$(@__DIR__)/benchmark_ingest.jl")


for f in readdir("/work/", join=true)
    if startswith(f, "/work/results_")
        println(f)
        open(f, "r") do fio
            while !eof(fio)
                kp = deserialize(fio)
                println(kp.first)
                for (i,r) in enumerate(kp.second)
                    @printf("\t#%d: %s\n", i, r)
                end
            end
        end
        println()
    end
end