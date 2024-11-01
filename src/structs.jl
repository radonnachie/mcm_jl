using Printf
using Dates

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

@enum ObjectiveMCM begin
    MinAdderCount
    MinMaxAdderDepth
    MinAdderCountPlusMaxAdderDepth
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

@kwdef struct ResultsKey
    timestamp::DateTime
    benchmark_name::String
    gurobi_parameters::GurobiParam
    objective::ObjectiveMCM
    elapsed_ns::UInt64
end

function Base.show(io::IO, r::ResultsKey)
    @printf(io, 
        "ResultsKey(%s @%s, with %s, %s in %0.3f s)",
        r.timestamp,
        r.benchmark_name,
        r.gurobi_parameters,
        r.objective,
        r.elapsed_ns/1e9
    )
end
