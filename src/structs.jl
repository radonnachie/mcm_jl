@kwdef struct GurobiParam    
    TimeLimit::Int = 300
    Presolve::Int = 1
    IntegralityFocus::Int = 1
    MIPFocus::Int = 3
    ConcurrentMIP::Int = 2
end

function Base.show(io::IO, r::GurobiParam)
    @printf(io, 
        "GurobiParam(<%d s, %sPresolve, %sIntegralityFocus, MIPFocus #%d, ConcurrentMIP %d)",
        r.TimeLimit,
        r.Presolve == 1 ? "" : "no ",
        r.IntegralityFocus == 1 ? "" : "no ",
        r.MIPFocus,
        r.ConcurrentMIP
    )
end

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


@enum ObjectiveMCM begin
    MinAdderCount
    MinMaxAdderDepth
    MinAdderCountPlusMaxAdderDepth
    MinNaAdderCountPlusMaxAdderDepth
    MinAdderCountPlusNaMaxAdderDepth
    MinAdderDepthSum
end

@kwdef struct MCMLiftingConstraintsSelection
    adder_msd_complex_sorted_coefficient_lock::Bool
    adder_one_input_noshift::Bool
    unique_sums::Bool
end

@kwdef struct MCMConstraintOptions
    sign_selection_direct_not_inferred::Bool
    use_indicator_constraints_not_big_m::Bool
end

@kwdef struct MCMParam
    min_nof_adders::Int
    max_nof_adders::Int
    nof_adder_inputs::Int
    data_bit_width::Int
    maximum_shift::Int
    lifting_constraints::MCMLiftingConstraintsSelection
    constraint_options::MCMConstraintOptions
    objective::ObjectiveMCM = MinAdderCountPlusMaxAdderDepth
end

function Base.show(io::IO, r::MCMParam)
    @printf(io, 
        "MCMParam(%d <= N_a <= %d (%d inputs), W=%d, << <=%d, %s)",
        r.min_nof_adders,
        r.max_nof_adders,
        r.nof_adder_inputs,
        r.data_bit_width,
        r.maximum_shift,
        r.objective
    )
end

@kwdef struct ResultsMCM
    result_index::UInt
    adder_count::Int
    depth_max::Int
    outputs::Vector{Int}
    output_value_sel::Array{Bool}
    input_shifted::Array{Int}
    input_value::Array{Int}
    input_value_sel::Array{Bool}
    input_shift_sel::Array{Bool}
    inputs::Array{Int}
    results::Array{Int}
    enables::Vector{Bool}
    depth::Vector{Int}
    input_depths::Array{Int}
end

function Base.show(io::IO, r::ResultsMCM)
    @printf(io, 
        "ResultsMCM(#%d, N_A=%d with AD=%d, outputs=%s, adder_depths=%s)",
        r.result_index,
        r.adder_count,
        r.depth_max,
        r.outputs,
        r.depth
    )
end

struct ReferenceResult
    benchmark_name::String
    # file_ag::String
    # method::String
    min_ad::Bool
    time_s::Float64
    solved::Bool
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
        "ReferenceResult(%s in %0.3f s (%sSolved), Min(%s), N_a=%d, AD=%d)",
        r.benchmark_name,
        r.time_s,
        r.solved ? "" : "Not ",
        r.min_ad ? "AD" : "N_a+AD",
        r.nof_adders,
        r.adder_depth
    )
end

@enum ObjectivityCategory begin
    MissingObjectivity
    WorseObjectivity
    EqualObjectivity
    NarrowerObjectivity
    ShallowerObjectivity
    BetterObjectivity
    NovelObjectivity
end
ObjectivityCategoryStringMap::Dict{String, ObjectivityCategory} = Dict(
    String(Symbol(inst)) => inst
    for inst in instances(ObjectivityCategory)
)

@enum FinalityCategory begin
    OpenFinality
    NotClosedFinality
    ClosedFinality
    NewlyClosedFinality
end
FinalityCategoryStringMap::Dict{String, FinalityCategory} = Dict(
    String(Symbol(inst)) => inst
    for inst in instances(FinalityCategory)
)

@kwdef struct SummarisedResultsMCM
    solved::Bool
    nof_adders::Int
    adder_depth::Int
end

function SummarisedResultsMCM(r::ReferenceResult)
    SummarisedResultsMCM(
        solved = r.solved,
        nof_adders = r.nof_adders,
        adder_depth = r.adder_depth,
    )
end

struct ComparitiveCategory
    finality::FinalityCategory
    objectivity::ObjectivityCategory

    function ComparitiveCategory(
        reference::Union{SummarisedResultsMCM, Nothing},
        result::Union{SummarisedResultsMCM, Nothing}
    )
        if isnothing(reference)
            @assert !isnothing(result) "At least one result must be something."
            return new(
                result.solved ? NewlyClosedFinality : OpenFinality,
                NovelObjectivity
            )
        elseif isnothing(result)
            return new(
                reference.solved ? NotClosedFinality : OpenFinality,
                MissingObjectivity
            )
        end

        objectivity = WorseObjectivity
        ref_objective = reference.nof_adders + reference.adder_depth
        res_objective = result.nof_adders + result.adder_depth

        if ref_objective == res_objective
            objectivity = EqualObjectivity
            if reference.nof_adders > result.nof_adders
                objectivity = NarrowerObjectivity
            elseif reference.adder_depth > result.adder_depth
                objectivity = ShallowerObjectivity
            end
        elseif ref_objective > res_objective
            objectivity = BetterObjectivity
        end

        finality = OpenFinality
        if reference.solved
            if result.solved
                finality = ClosedFinality
            else
                finality = NotClosedFinality
            end
        else
            if result.solved
                finality = NewlyClosedFinality
            else
                finality = OpenFinality
            end
        end

        new(finality, objectivity)
    end

    
    function ComparitiveCategory(
        str::AbstractString
    )
        finality, objectivity = split(str; limit=2)
        new(
            FinalityCategoryStringMap[finality],
            ObjectivityCategoryStringMap[objectivity]
        )
    end
end

function Base.show(io::IO, c::ComparitiveCategory)
    @printf(io, 
        "%s %s",
        String(Symbol(c.finality)),
        String(Symbol(c.objectivity))
    )
end

struct SummarisedComparitiveResultsMCM
    benchmark_name::String
    reference_result::Union{SummarisedResultsMCM, Nothing}
    result::Union{SummarisedResultsMCM, Nothing}
    comparison::Union{ComparitiveCategory, Nothing}

    function SummarisedComparitiveResultsMCM(
        benchmark_name::String,
        reference_result::Union{SummarisedResultsMCM, Nothing},
        result::Union{SummarisedResultsMCM, Nothing},
    )
        comparison = nothing
        if !isnothing(reference_result) || !isnothing(result)
            comparison = ComparitiveCategory(
                reference_result,
                result
            )
        end
        
        new(
            benchmark_name,
            reference_result,
            result,
            comparison
        )
    end
end


function to_csv_line(
    r::SummarisedComparitiveResultsMCM;
    prefix_header::Bool = false
)::String
    (prefix_header
        ? "benchmark_name,ref_nof_adders,ref_adder_depth,ref_solved,nof_adders,adder_depth,solved,comparison\n"
        : ""
    ) * @sprintf(
        "%s,%s,%s,%s",
        r.benchmark_name,
        isnothing(r.reference_result) ? ",," : @sprintf(
            "%d,%d,%s",
            r.reference_result.nof_adders,
            r.reference_result.adder_depth,
            r.reference_result.solved,
        ),
        isnothing(r.result) ? ",," : @sprintf(
            "%d,%d,%s",
            r.result.nof_adders,
            r.result.adder_depth,
            r.result.solved,
        ),
        r.comparison
    )
end

function SummarisedComparitiveResultsMCM(
    line::String,
)
    line_data = split(line, ",")

    SummarisedComparitiveResultsMCM(
        line_data[1],
        length(join(line_data[2:4]))== 0 ? nothing : SummarisedResultsMCM(
            solved = parse(Bool, line_data[4]),
            nof_adders = parse(Int, line_data[2]),
            adder_depth = parse(Int, line_data[3]),
        ),
        length(join(line_data[5:7]))== 0 ? nothing :  SummarisedResultsMCM(
            solved = parse(Bool, line_data[7]),
            nof_adders = parse(Int, line_data[5]),
            adder_depth = parse(Int, line_data[6]),
        )
    )
end

@kwdef struct ResultsKey
    timestamp::DateTime
    benchmark_name::String
    gurobi_parameters::GurobiParam
    mcm_parameters::MCMParam
    solved_fully::Bool
    elapsed_ns::UInt64
end

function Base.show(io::IO, r::ResultsKey)
    @printf(io, 
        "ResultsKey(%s @%s, with %s, %s in %0.3f s (%sSolved))",
        r.timestamp,
        r.benchmark_name,
        r.gurobi_parameters,
        r.mcm_parameters,
        r.elapsed_ns/1e9,
        r.solved_fully ? "" : "Not "
    )
end
