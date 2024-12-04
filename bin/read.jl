using Serialization
using Dates
using MCM


for f in readdir("/work/")
    println(f)
    if startswith(f, "results_2024-11-1")
        println("!!!!"*f)
        open("/work/"*f, "r") do fio
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