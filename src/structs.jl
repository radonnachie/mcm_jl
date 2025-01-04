@kwdef struct GurobiParam    
    TimeLimit::Int = 600
    Presolve::Int = 1
    IntegralityFocus::Int = 1
    MIPFocus::Int = 0
    ConcurrentMIP::Int = 4 # https://www.gurobi.com/documentation/current/refman/mipfocus.html#parameter:MIPFocus
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
    InfeasibleObjectivity
    MissingObjectivity
    WorseObjectivity
    EqualObjectivity
    NarrowerObjectivity
    ShallowerObjectivity
    BetterObjectivity
    NovelObjectivity
end
ObjectivityCategoryStringMap::Dict{String, ObjectivityCategory} = Dict(
    long ? String(Symbol(inst)) => inst : String(Symbol(inst))[1:end-length("Objectivity")] => inst
    for inst in instances(ObjectivityCategory)
    for long in [false, true]
)

function shorthand(objective::ObjectivityCategory)::Char
    if objective == InfeasibleObjectivity
        return '!'
    elseif objective == MissingObjectivity
        return '?'
    elseif objective == WorseObjectivity
        return '-'
    elseif objective == EqualObjectivity
        return '='
    elseif objective == NarrowerObjectivity
        return '|'
    elseif objective == ShallowerObjectivity
        return '_'
    elseif objective == BetterObjectivity
        return '+'
    elseif objective == NovelObjectivity
        return '*'
    end
    @assert(false, @sprintf("Unhandled ObjectivityCategory: %s", objective))
end

@enum FinalityCategory begin
    OpenFinality
    NotClosedFinality
    ClosedFinality
    NewlyClosedFinality
end
FinalityCategoryStringMap::Dict{String, FinalityCategory} = Dict(
    long ? String(Symbol(inst)) => inst : String(Symbol(inst))[1:end-length("Finality")] => inst
    for inst in instances(FinalityCategory)
    for long in [false, true]
)

function shorthand(finality::FinalityCategory)::Char
    if finality == OpenFinality
        return 'O'
    elseif finality == NotClosedFinality
        return 'U'
    elseif finality == ClosedFinality
        return 'C'
    elseif finality == NewlyClosedFinality
        return 'N'
    end
    @assert(false, @sprintf("Unhandled FinalityCategory: %s", finality))
end

@kwdef struct SummarisedResultsMCM
    solved::Bool
    nof_adders::Int
    adder_depth::Int
    solve_time_s::Float32
end

function SummarisedResultsMCM(r::ReferenceResult)
    SummarisedResultsMCM(
        solved = r.solved,
        nof_adders = r.nof_adders,
        adder_depth = r.adder_depth,
        solve_time_s = r.time_s,
    )
end

struct ComparitiveCategory
    finality::FinalityCategory
    objectivity::ObjectivityCategory
end

function ComparitiveCategory(
    reference::Union{SummarisedResultsMCM, Nothing},
    result::Union{SummarisedResultsMCM, Nothing}
)
    if isnothing(reference)
        @assert !isnothing(result) "At least one result must be something."
        return ComparitiveCategory(
            result.solved ? NewlyClosedFinality : OpenFinality,
            NovelObjectivity
        )
    elseif isnothing(result)
        return ComparitiveCategory(
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

    ComparitiveCategory(finality, objectivity)
end

function ComparitiveCategory(
    str::AbstractString;
    delimiter=isspace
)
    finality, objectivity = split(str, delimiter; limit=2)
    ComparitiveCategory(
        FinalityCategoryStringMap[finality],
        ObjectivityCategoryStringMap[objectivity]
    )
end

function Base.show(io::IO, c::ComparitiveCategory)
    @printf(io, 
        "%s %s",
        String(Symbol(c.finality)),
        String(Symbol(c.objectivity))
    )
end

function shorthand(comparison::ComparitiveCategory)::String
    return shorthand(comparison.finality)*shorthand(comparison.objectivity)
end

function score(finality::FinalityCategory, objective::ObjectivityCategory; enable_warning=true)::Int
    if objective == InfeasibleObjectivity
        if finality == OpenFinality
            # Infeasible when not closed elsewhere is the second worst
            return -19
        elseif finality == NotClosedFinality
            # Infeasible when closed elsewhere is the worst
            return -23
        end

    elseif objective == MissingObjectivity
        if finality == OpenFinality
            # Could not find a solution when it has not been closed
            return -7
        elseif finality == NotClosedFinality
            # Could not find a solution when it has been closed
            return -11
        end

    elseif objective == WorseObjectivity
        if finality == OpenFinality
            # Maybe given more time an equal objectivity could be reached
            return -3
        elseif finality == NotClosedFinality
            # Maybe given more time an equal objectivity could be reached
            # but it has been closed elsewhere
            return -5
        elseif finality == ClosedFinality
            # This indicates that the model has constraints that exclude a feasible better result
            ## should warn
            return -13
        elseif finality == NewlyClosedFinality
            # This indicates that the model has constraints that exclude a feasible better result
            # when the other was not even closed
            ## should warn
            return -17
        end

    elseif objective in [
        EqualObjectivity,
        NarrowerObjectivity,
        ShallowerObjectivity,
    ]
        if finality == OpenFinality
            # Practically equivalent, a non-result
            return 1
        elseif finality == NotClosedFinality
            # Minor negative result
            return -2
        elseif finality == ClosedFinality
            # Practically equivalent, a non-result
            return 1
        elseif finality == NewlyClosedFinality
            # Minor positive result
            return 2
        end

    elseif objective == BetterObjectivity
        if finality == OpenFinality
            # Improved without closing
            return 3
        elseif finality == NotClosedFinality
            # This indicates that the two models disagree on search space
            # but this found a better result without closing
            ## should warn
            return 17
        elseif finality == ClosedFinality
            # This indicates that the two models disagree on search space
            # but this found a better result
            ## should warn
            return 13
        elseif finality == NewlyClosedFinality
            # Improved and newly closed
            return 5
        end

    elseif objective == NovelObjectivity
        if finality == OpenFinality
            # Provides a novel non-final solution
            return 7
        elseif finality == NewlyClosedFinality
            # Provides a novel final solution
            return 11
        end
    end
    if enable_warning
        @printf(stderr, "WARNING: ComparisonCategory should be impossible: %s", comparison)
    end
    return 0
end

score(comparison::ComparitiveCategory)::Int = score(comparison.finality, comparison.objectivity)

function score(comparison_counts::Dict{ComparitiveCategory, Int})::Rational{BigInt}
    neg, pos = big"1", big"1"
    for (comp, count) in comparison_counts
        if count == 0
            continue
        end
        prod_score = score(comp)
        if prod_score == 1
            continue
        end

        prod_score = BigInt(prod_score)
        if prod_score < 0
            neg *= abs(prod_score)^count
        else
            pos *= prod_score^count
        end
    end
    pos // neg
end

ComparitiveCategoryScoreMap::Dict{ComparitiveCategory, Int} = Dict(
    ComparitiveCategory(f, o) => score(f, o; enable_warning=false)
    for f in instances(FinalityCategory) for o in instances(ObjectivityCategory)
)

ComparitiveCategoryInstances = (c for (c, s) in ComparitiveCategoryScoreMap if s != 0)

ComparitiveCategoryInstancesAscending = sort(collect(ComparitiveCategoryInstances), by=c->ComparitiveCategoryScoreMap[c])

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
        ? "benchmark_name,ref_nof_adders,ref_adder_depth,ref_solved,ref_solve_s,nof_adders,adder_depth,solved,solve_s,comparison\n"
        : ""
    ) * @sprintf(
        "%s,%s,%s,%s",
        r.benchmark_name,
        isnothing(r.reference_result) ? ",,," : @sprintf(
            "%d,%d,%s,%0.3f",
            r.reference_result.nof_adders,
            r.reference_result.adder_depth,
            r.reference_result.solved,
            r.reference_result.solve_time_s,
        ),
        isnothing(r.result) ? ",,," : @sprintf(
            "%d,%d,%s,%0.3f",
            r.result.nof_adders,
            r.result.adder_depth,
            r.result.solved,
            r.result.solve_time_s,
        ),
        r.comparison
    )
end

function SummarisedComparitiveResultsMCM(
    line::String,
)
    line_data = split(line, ",")

    SummarisedComparitiveResultsMCM(
        String(line_data[1]),
        length(join(line_data[2:5])) == 0 ? nothing : SummarisedResultsMCM(
            solved = parse(Bool, line_data[4]),
            nof_adders = parse(Int, line_data[2]),
            adder_depth = parse(Int, line_data[3]),
            solve_time_s = parse(Float32, line_data[5]),
        ),
        length(join(line_data[6:9])) == 0 ? nothing :  SummarisedResultsMCM(
            solved = parse(Bool, line_data[8]),
            nof_adders = parse(Int, line_data[6]),
            adder_depth = parse(Int, line_data[7]),
            solve_time_s = parse(Float32, line_data[9]),
        )
    )
end

@kwdef struct ResultsKey
    timestamp::DateTime
    benchmark_name::String
    gurobi_parameters::GurobiParam
    mcm_parameters::MCMParam
    solved_fully::Bool
    feasible::Bool
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

function SummarisedResultsMCM(rp::Pair{ResultsKey, ResultsMCM})
    SummarisedResultsMCM(
        solved = rp.first.solved_fully,
        nof_adders = rp.second.adder_count,
        adder_depth = rp.second.depth_max,
        solve_time_s = rp.first.elapsed_ns/1e9,
    )
end

function mcm_run_parameters_key(
    gp::GurobiParam,
    mp::MCMParam
)::String
    @sprintf(
        "G(<%ds:%sP:%sI):%s:L(%sc:%sz:%su):C(%sssd:%si)",
        gp.TimeLimit,
        gp.Presolve == 1 ? "y" : "n",
        gp.IntegralityFocus == 1 ? "y" : "n",
        String(Symbol(mp.max_nof_adders_func))[length("number_of_adders_max_")+1:end],
        mp.lifting_constraints.adder_msd_complex_sorted_coefficient_lock ? "y" : "n",
        mp.lifting_constraints.adder_one_input_noshift ? "y" : "n",
        mp.lifting_constraints.unique_sums ? "y" : "n",
        mp.constraint_options.sign_selection_direct_not_inferred ? "y" : "n",
        mp.constraint_options.use_indicator_constraints_not_big_m ? "y" : "n",
    )
end

mcm_run_parameters_key(r::ResultsKey)::String = mcm_run_parameters_key(r.gurobi_parameters, r.mcm_parameters)
