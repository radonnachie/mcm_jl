module MCM

using JuMP
using Gurobi
using Printf
using Dates

include("csd.jl")
export csd, union_csd, count_components, unique_subsections, csd2int, get_odd_factor, number_of_adders_min, number_of_adders_max_ktree, get_unique_subterms, number_of_adders_max_uniqueterms, number_of_adders_max_nonzeropairs


function bitwidth_of_adders(coeffs::Vector{Int})::Int
	ceil(Int, log2(maximum(coeffs)))
end

function maxshift_of_adders(coeffs::Vector{Int})::Int
	ceil(Int, log2(maximum(coeffs)))
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
    adder_msd_complex_sorted_coefficient_lock::Bool=true
    adder_one_input_noshift::Bool=true
    unique_sums::Bool=true
end

@kwdef struct MCMConstraintOptions
    sign_selection_direct_not_inferred::Bool=true
    use_indicator_constraints_not_big_m::Bool=false
end

@kwdef struct MCMParam
    nof_adder_inputs::Int=2
    min_nof_adders_func::Function = number_of_adders_min
    max_nof_adders_func::Function = number_of_adders_max_ktree
    data_bit_width_func::Function = bitwidth_of_adders #{Vector{Int}, Int}
    maximum_shift_func::Function = maxshift_of_adders #{Vector{Int}, Int}
    lifting_constraints::MCMLiftingConstraintsSelection = MCMLiftingConstraintsSelection()
    constraint_options::MCMConstraintOptions = MCMConstraintOptions()
    objective::ObjectiveMCM = MinAdderCountPlusMaxAdderDepth
end

function Base.show(io::IO, r::MCMParam)
    @printf(io, 
        "MCMParam(%d inputs, %s <= N_a <= %s, W=%s, << <=%s, %s)",
        r.nof_adder_inputs,
        r.min_nof_adders_func,
        r.max_nof_adders_func,
        r.data_bit_width_func,
        r.maximum_shift_func,
        r.objective
    )
end


include("structs.jl")
export GurobiParam, SolutionMetricMCM, ReferenceResult, SummarisedResultsMCM, ComparitiveCategory, SummarisedComparitiveResultsMCM, ResultsKey, ObjectiveMCM, ObjectivityCategory, FinalityCategory, ModelWeight
export mcm_run_parameters_key, score, shorthand, to_csv_line, to_csv_elem

include("reference_results_ingest.jl")
export ReferenceResult
export readReferenceResults, getBestReferenceResults

include("benchmark_ingest.jl")
export BenchmarkDetails
export readBenchmarkDetails

export mcm_model, preprocess_coefficients, MCMLiftingConstraintsSelection, MCMConstraintOptions, MCMParam
export optimize!

function sort_by_component_count!(coeffs::Vector{Int})::Vector{Int}
    sort(
        sort(coeffs),
        by=x->count_components(csd(UInt(abs(x))))
    )
end

function preprocess_coefficients(coeffs::Vector{Int})::Vector{Int}
    sort_by_component_count!(filter(
        x -> x > 1,
        unique(
            get_odd_factor.(abs.(coeffs))
        )
    ))
end

function optimization_hook(model::Model; kwargs...)::Vector{ResultsMCM}
	if haskey(kwargs, :optimizer_factory)
		set_optimizer(model, kwargs[:optimizer_factory], add_bridges=get(kwargs, :add_bridges, false))
	end
	for (attr, val) in get(kwargs, :attributes, Dict())
		set_attribute(model, attr, val)
	end
	if !isnothing(get(kwargs, :gurobi, nothing))
		set_optimizer(model, Gurobi.Optimizer, add_bridges=get(kwargs, :add_bridges, false))
		
		param = kwargs[:gurobi]
		set_attribute(model, "TimeLimit", param.TimeLimit)
		set_attribute(model, "Presolve", param.Presolve)
		set_attribute(model, "IntegralityFocus", param.IntegralityFocus)
		set_attribute(model, "MIPFocus", param.MIPFocus)
		set_attribute(model, "ConcurrentMIP", param.ConcurrentMIP)
	end
	
	optimize!(model, ignore_optimize_hook = true)
	@show is_solved_and_feasible(model)
	@show result_count(model)

	results = Vector{ResultsMCM}()
	values = Dict(
		sym => [value.(obj; result=i) for i in 1:result_count(model)]
		for (sym, obj) in model.obj_dict
	)

	all_ao = [unique(values[:adder_outputs][i]) for i in 1:result_count(model)]
	unique_ao = unique(all_ao)
	unique_result_indices = [findfirst(x->x==un, all_ao) for un in unique_ao]

	for i in unique_result_indices
		push!(results, ResultsMCM(
			result_index = i,
			adder_count = sum(round.(Int, values[:adder_enables][i])),
			depth_max = floor(Int, values[:adder_depth_max][i]),
			outputs = floor.(Int, values[:adder_outputs][i]),
			output_value_sel = round.(Int, values[:adder_output_value_sel][i]),
			input_shifted = floor.(Int, values[:adder_input_shifted][i]),
			input_value = floor.(Int, values[:adder_input_value][i]),
			input_value_sel = round.(Int, values[:adder_input_value_sel][i]),
			input_shift_sel = round.(Int, values[:adder_input_shift_sel][i]),
			inputs = floor.(Int, values[:adder_inputs][i]),
			results = zeros(Int, 1),
			enables = round.(Int, values[:adder_enables][i]),
			depth = floor.(Int, values[:adder_depth][i]),
			input_depths = floor.(Int, values[:adder_input_depths][i]),
		))
	end
	results
end

function _model_mcm_constraints!(
	model::Model;
	nof_adders::Int,
	nof_adder_inputs::Int,
	nof_constant_multiples::Int,
	shiftfactor_values::Vector{Int},
	maximum_value::Int,
	lifting_constraints::MCMLiftingConstraintsSelection,
	constraint_options::MCMConstraintOptions
)
	nof_shift_values = length(shiftfactor_values)
	max_shift_factor = maximum(shiftfactor_values)

	signfactor_values = [-1, 1]

	# Adders have outputs.
	@variable(model, # TODO optionally possibly negative
		0 <= adder_outputs[0:nof_adders] <= nof_adder_inputs*max_shift_factor*maximum_value,
	Int)
	## A psuedo output for a static, non-existent adder is set to 1
	@constraint(model, adder_outputs[0] == 1)

	## The adders are enabled
	@variable(model,
		adder_enables[
			1:nof_adders
		],
	Bin)

	# Each adder input has 3 factors: sign, shift and value
	## the shift*value product is captured by indicator constraints in `input_shifted`
	## and then the final product is captured by indicator constraints in `input_value`
	@variable(model,
		-max_shift_factor*maximum_value <= adder_input_shifted[1:nof_adder_inputs, 1:nof_adders] <= max_shift_factor*maximum_value,
	Int)
	@variable(model,
		-nof_adder_inputs*max_shift_factor*maximum_value <= adder_input_value[1:nof_adder_inputs, 1:nof_adders] <= nof_adder_inputs*max_shift_factor*maximum_value,
	Int)

	# Each adder input is the product of (sign, shift, value)
	## The adder input value comes from preceding-adders' outputs
	@variable(model,
		adder_input_value_sel[
			0:nof_adders,
			1:nof_adder_inputs,
			1:nof_adders
		],
	Bin)
	### enabled adders must have each input enabled
	#! C4
	@constraint(model, [i = 1:nof_adder_inputs, a = 1:nof_adders],
		sum(adder_input_value_sel[s, i, a] for s in 0:a-1) == adder_enables[a]
	)
	#TODO cannot select non-enabled adder output
	@constraint(model, [i = 1:nof_adder_inputs, a = 1:nof_adders],
		sum(adder_input_value_sel[s, i, a] for s in a:nof_adders) == 0
	)
	value_M = 2*nof_adder_inputs*max_shift_factor*maximum_value
	if constraint_options.use_indicator_constraints_not_big_m
		@constraint(model, [s = 0:nof_adders, i = 1:nof_adder_inputs, a = 1:nof_adders],
			adder_input_value_sel[s,i,a] --> {adder_input_value[i, a] == adder_outputs[s]}
		)
	else
		@constraint(model, [s = 0:nof_adders, i = 1:nof_adder_inputs, a = 1:nof_adders],
			adder_outputs[s] - (1 - adder_input_value_sel[s, i, a])*value_M <= adder_input_value[i, a]
		)
		@constraint(model, [s = 0:nof_adders, i = 1:nof_adder_inputs, a = 1:nof_adders],
			adder_input_value[i, a] <= adder_outputs[s] + (1 - adder_input_value_sel[s, i, a])*value_M
		)
	end
	### non-enabled adders have zero as input values
	if constraint_options.use_indicator_constraints_not_big_m
		@constraint(model, [i = 1:nof_adder_inputs, a = 1:nof_adders],
			!adder_enables[a] --> {adder_input_value[i, a] == 0}
		)
	else
		@constraint(model, [i = 1:nof_adder_inputs, a = 1:nof_adders],
			0 - adder_enables[a]*value_M <= adder_input_value[i, a]
		)
		@constraint(model, [i = 1:nof_adder_inputs, a = 1:nof_adders],
			adder_input_value[i, a] <= 0 + adder_enables[a]*value_M
		)
	end
	## An adder cannot be selected as an input if it is not-enabled
	@constraint(model, [s = 1:nof_adders, i = 1:nof_adder_inputs, a = 1:nof_adders],
		adder_input_value_sel[s, i, a] <= adder_enables[s]
	)

	## The input is selectively shifted, linearised indicator constraints on `input_shifted`
	@variable(model,
		adder_input_shift_sel[
			1:nof_shift_values,
			1:nof_adder_inputs,
			1:nof_adders
		],
	Bin)
	@constraint(model, [i = 1:nof_adder_inputs, a = 1:nof_adders],
		sum(adder_input_shift_sel[s, i, a] for s in 1:nof_shift_values) == 1
	)
	if lifting_constraints.adder_one_input_noshift
		## for the output to be odd, there must be an odd number of non-shifted inputs (which are all odd) 
		### constrain one input to never be shifted
		@constraint(model, [a = 1:nof_adders],
			adder_input_shift_sel[1, 1, a] == 1
		)
	end
	## if the output is even (an even number of inputs were not shifted), a right shift after the sum will be constrained to drop the low LSBs
	@variable(model, 0 <= adder_input_noshift_sel_oddity[1:nof_adders] <= nof_adder_inputs, Int)
	@variable(model, adder_input_noshift_sel_is_odd[1:nof_adders], Bin)
	@constraint(model, [a = 1:nof_adders],
		sum(adder_input_shift_sel[1, i, a] for i in 1:nof_adder_inputs) == 2*adder_input_noshift_sel_oddity[a]+adder_input_noshift_sel_is_odd[a]
	)
	# TODO if not-enabled, then no shift zero-value inputs.

	shifted_M = 2*maximum_value*max_shift_factor
	if constraint_options.use_indicator_constraints_not_big_m
		@constraint(model, [s = 1:nof_shift_values, i = 1:nof_adder_inputs, a = 1:nof_adders],
			adder_input_shift_sel[s,i,a] --> {adder_input_shifted[i, a] == adder_input_value[i,a]*shiftfactor_values[s]}
		)
	else
		@constraint(model, [s = 1:nof_shift_values, i = 1:nof_adder_inputs, a = 1:nof_adders],
			adder_input_value[i,a]*shiftfactor_values[s] - (1 - adder_input_shift_sel[s, i, a])*shifted_M <= adder_input_shifted[i, a]
		)
		@constraint(model, [s = 1:nof_shift_values, i = 1:nof_adder_inputs, a = 1:nof_adders],
			adder_input_shifted[i, a] <= adder_input_value[i,a]*shiftfactor_values[s] + (1 - adder_input_shift_sel[s, i, a])*shifted_M
		)
	end

	## The shifted input is selectively signed, linearised indicator constraints on `inputs`
	@variable(model,
		-maximum_value <= adder_inputs[1:nof_adder_inputs, 1:nof_adders] <= maximum_value,
	Int)
	sign_M = 2*maximum_value*max_shift_factor
	if constraint_options.sign_selection_direct_not_inferred
		@variable(model,
			adder_input_sign_sel[
				1:2,
				1:nof_adder_inputs,
				1:nof_adders
			],
		Bin)
		@constraint(model, [i = 1:nof_adder_inputs, a = 1:nof_adders],
			sum(adder_input_sign_sel[s, i, a] for s in 1:2) == 1
		)
		## At most one input negated
		@constraint(model, [a = 1:nof_adders],
			sum(adder_input_sign_sel[1, i, a] for i in 1:nof_adder_inputs) <= nof_adder_inputs-1
		)
		if constraint_options.use_indicator_constraints_not_big_m
			@constraint(model, [s = 1:2, i = 1:nof_adder_inputs, a = 1:nof_adders],
				adder_input_sign_sel[s,i,a] --> {adder_inputs[i, a] == adder_input_shifted[i, a]*signfactor_values[s]}
			)
		else
			@constraint(model, [s = 1:2, i = 1:nof_adder_inputs, a = 1:nof_adders],
				adder_input_shifted[i, a]*signfactor_values[s] - (1 - adder_input_sign_sel[s, i, a])*sign_M <= adder_inputs[i, a]
			)
			@constraint(model, [s = 1:2, i = 1:nof_adder_inputs, a = 1:nof_adders],
				adder_inputs[i, a] <= adder_input_shifted[i, a]*signfactor_values[s] + (1 - adder_input_sign_sel[s, i, a])*sign_M
			)
		end
	else		
		@variable(model,
			adder_input_sign_sel[
				1:nof_adder_inputs,
				1:nof_adders
			],
		Bin)
		## At most one input negated
		@constraint(model, [a = 1:nof_adders],
			sum(adder_input_sign_sel[i, a] for i in 1:nof_adder_inputs) <= nof_adder_inputs-1
		)
		if constraint_options.use_indicator_constraints_not_big_m
			@constraint(model, [i = 1:nof_adder_inputs, a = 1:nof_adders],
				adder_input_sign_sel[i,a] --> {adder_inputs[i, a] == -adder_input_shifted[i, a]}
			)
			@constraint(model, [i = 1:nof_adder_inputs, a = 1:nof_adders],
				!adder_input_sign_sel[i,a] --> {adder_inputs[i, a] == adder_input_shifted[i, a]}
			)
		else
			@constraint(model, [i = 1:nof_adder_inputs, a = 1:nof_adders],
				-adder_input_shifted[i, a] - (1-adder_input_sign_sel[i, a])*sign_M <= adder_inputs[i, a]
			)
			@constraint(model, [i = 1:nof_adder_inputs, a = 1:nof_adders],
				adder_inputs[i, a] <= -adder_input_shifted[i, a] + (1-adder_input_sign_sel[i, a])*sign_M
			)
			@constraint(model, [i = 1:nof_adder_inputs, a = 1:nof_adders],
				adder_input_shifted[i, a] - adder_input_sign_sel[i, a]*sign_M <= adder_inputs[i, a]
			)
			@constraint(model, [i = 1:nof_adder_inputs, a = 1:nof_adders],
				adder_inputs[i, a] <= adder_input_shifted[i, a] + adder_input_sign_sel[i, a]*sign_M
			)
		end
	end

	# Adder output is the sum of its inputs
	@variable(model, 0 <= adder_sums[1:nof_adders] <= nof_adder_inputs*max_shift_factor*maximum_value, Int)
	sum_M = 2*nof_adder_inputs*max_shift_factor*maximum_value
	## When enabled, constrain output to sum
	## When not-enabled, constrain output to 0
	### TODO not necessary as inputs are zero when not-enabled
	if constraint_options.use_indicator_constraints_not_big_m
		@constraint(model, [a = 1:nof_adders],
			adder_enables[a] --> {adder_sums[a] == sum(adder_inputs[i, a] for i in 1:nof_adder_inputs)}
		)
		@constraint(model, [a = 1:nof_adders],
			!adder_enables[a] --> {adder_sums[a] == 0}
		)
	else
		@constraint(model, [a = 1:nof_adders],
			sum(adder_inputs[i, a] for i in 1:nof_adder_inputs) - (1 - adder_enables[a])*sum_M <= adder_sums[a]
		)
		@constraint(model, [a = 1:nof_adders],
			adder_sums[a] <= sum(adder_inputs[i, a] for i in 1:nof_adder_inputs) + (1 - adder_enables[a])*sum_M
		)
		@constraint(model, [a = 1:nof_adders],
			0 - adder_enables[a]*sum_M <= adder_sums[a]
		)
		@constraint(model, [a = 1:nof_adders],
			adder_sums[a] <= 0 + adder_enables[a]*sum_M
		)
	end

	if lifting_constraints.unique_sums
		## Adder sums should be unique
		comparison_values = ["equal", "lesser", "greater"]

		@variable(model, adder_sum_comparison_sel[comparison_values, 1:nof_adders, 1:nof_adders], Bin)
		@constraint(model, [a_other = 1:nof_adders, a = 1:nof_adders],
			sum(adder_sum_comparison_sel[c, a, a_other] for c in comparison_values) == 1
		)

		if constraint_options.use_indicator_constraints_not_big_m
			@constraint(model, [a_other = 1:nof_adders, a = 1:nof_adders],
				adder_sum_comparison_sel["equal", a, a_other] --> {adder_sums[a] == adder_sums[a_other]}
			)
			@constraint(model, [a_other = 1:nof_adders, a = 1:nof_adders],
				adder_sum_comparison_sel["lesser", a, a_other] --> {adder_sums[a] <= adder_sums[a_other]-1}
			)
			@constraint(model, [a_other = 1:nof_adders, a = 1:nof_adders],
				adder_sum_comparison_sel["greater", a, a_other] --> {adder_sums[a] >= adder_sums[a_other]+1}
			)
		else
			@constraint(model, [a_other = 1:nof_adders, a = 1:nof_adders],
				adder_sums[a_other] - (1-adder_sum_comparison_sel["equal", a, a_other])*sum_M <= adder_sums[a]
			)
			@constraint(model, [a_other = 1:nof_adders, a = 1:nof_adders],
				adder_sums[a] <= adder_sums[a_other] + (1-adder_sum_comparison_sel["equal", a, a_other])*sum_M
			)

			@constraint(model, [a_other = 1:nof_adders, a = 1:nof_adders],
				adder_sums[a] <= adder_sums[a_other]-1 + (1-adder_sum_comparison_sel["lesser", a, a_other])*sum_M
			)
			@constraint(model, [a_other = 1:nof_adders, a = 1:nof_adders],
				adder_sums[a_other]+1 - (1-adder_sum_comparison_sel["greater", a, a_other])*sum_M <= adder_sums[a]
			)
		end
		# sums equal to selves
		@constraint(model, [a = 1:nof_adders],
			adder_sum_comparison_sel["equal", a, a] == 1
		)
		# sums not equal to any other (unique) if enabled
		@constraint(model, [a = 1:nof_adders, a_other = 1:a-1],
			adder_sum_comparison_sel["equal", a, a_other] <= 1 - adder_enables[a]
		)
		@constraint(model, [a = 1:nof_adders, a_other = a+1:nof_adders],
			adder_sum_comparison_sel["equal", a, a_other] <= 1 - adder_enables[a]
		)
		# sums equal (to zero) otherwise if both are not-enabled
		@constraint(model, [a = 1:nof_adders, a_other = 1:a-1],
			1 - (adder_enables[a]+adder_enables[a_other]) <= adder_sum_comparison_sel["equal", a, a_other] 
		)
		@constraint(model, [a = 1:nof_adders, a_other = 1:a-1],
			adder_sum_comparison_sel["equal", a, a_other] <= 1 + (adder_enables[a]+adder_enables[a_other])
		)
		@constraint(model, [a = 1:nof_adders, a_other = a+1:nof_adders],
			1 - (adder_enables[a]+adder_enables[a_other]) <= adder_sum_comparison_sel["equal", a, a_other] 
		)
		@constraint(model, [a = 1:nof_adders, a_other = a+1:nof_adders],
			adder_sum_comparison_sel["equal", a, a_other] <= 1 + (adder_enables[a]+adder_enables[a_other])
		)
	end

	## the sum can be right shifted if it is even, so that all outputs are odd
	@variable(model, adder_sums_right_shift_sel[1:nof_shift_values, 1:nof_adders], Bin)
	@constraint(model, [a = 1:nof_adders],
		sum(adder_sums_right_shift_sel[s, a] for s in 1:nof_shift_values) == 1
	)
	## if the sum is odd (an odd number of inputs were shifted), there must be a zero right shift
	@constraint(model, [a = 1:nof_adders],
		adder_sums_right_shift_sel[1, a] == adder_input_noshift_sel_is_odd[a]
	)

	## The output is the right shifted sum
	if constraint_options.use_indicator_constraints_not_big_m
		@constraint(model, [s = 1:nof_shift_values, a = 1:nof_adders],
			adder_sums_right_shift_sel[s, a] --> {adder_outputs[a]*shiftfactor_values[s] == adder_sums[a]}
		)
	else
		@constraint(model, [s = 1:nof_shift_values, a = 1:nof_adders],
			adder_sums[a] - (1 - adder_sums_right_shift_sel[s, a])*max_shift_factor*sum_M <= adder_outputs[a]*shiftfactor_values[s]
		)
		@constraint(model, [s = 1:nof_shift_values, a = 1:nof_adders],
			adder_outputs[a]*shiftfactor_values[s] <= adder_sums[a] + (1 - adder_sums_right_shift_sel[s, a])*max_shift_factor*sum_M
		)
	end
	## adder outputs must be odd, when enabled (zero when not enabled)
	@variable(model,
		0 <= adder_output_oddity[
			1:nof_adders
		] <= nof_adder_inputs*max_shift_factor*maximum_value/2,
	Int)
	@constraint(model, [a = 1:nof_adders],
		adder_outputs[a] == 2*adder_output_oddity[a] + adder_enables[a]
	)
end

function mcm_model(
    constant_multiples::Vector{Int},
	param::MCMParam
	;
	suggestions::Vector{Int}=Vector{Int}(),
	model::Union{Nothing, <:Model} = nothing
)::Model
	nof_adder_inputs = param.nof_adder_inputs
	
	constant_multiples_uint = UInt.(constant_multiples)
	min_adders = param.min_nof_adders_func(constant_multiples_uint)
	nof_adders = param.max_nof_adders_func(constant_multiples_uint)
	data_bit_width = param.data_bit_width_func(constant_multiples)
	maximum_shift = param.maximum_shift_func(constant_multiples)

	maximum_value = 2^data_bit_width
	
	sort_by_component_count!(constant_multiples)

	nof_constant_multiples = length(constant_multiples)

	shiftfactor_values = [2^e for e in 0:maximum_shift]
	nof_shift_values = length(shiftfactor_values)
	max_shift_factor = maximum(shiftfactor_values)

	if isnothing(model)
		model = Model()
	end

	if false
		mcm_model_decisions!(
			model;
			nof_adders=nof_adders,
			nof_adder_inputs=nof_adder_inputs,
			nof_constant_multiples=nof_constant_multiples,
			shiftfactor_values=shiftfactor_values,
			maximum_value=maximum_value,
			lifting_constraints=param.lifting_constraints,
			constraint_options=param.constraint_options
		)
	else
		_model_mcm_constraints!(
			model;
			nof_adders=nof_adders,
			nof_adder_inputs=nof_adder_inputs,
			nof_constant_multiples=nof_constant_multiples,
			shiftfactor_values=shiftfactor_values,
			maximum_value=maximum_value,
			lifting_constraints=param.lifting_constraints,
			constraint_options=param.constraint_options
		)
	end

	adder_enables = model.obj_dict[:adder_enables]
	adder_input_value_sel = model.obj_dict[:adder_input_value_sel]
	adder_outputs = model.obj_dict[:adder_outputs]

	# The outputs selectively equal the coefficients requested
	@variable(model, adder_output_value_sel[1:nof_constant_multiples, 1:nof_adders], Bin)

	# C: Each coefficient must be purposefully represented exactly once
	## Does not preclude more than one adder from summing to the coeff (that's the uniqueness constraint's duty)
	@constraint(model, [c = 1:nof_constant_multiples],
		sum(adder_output_value_sel[c, a] for a in 1:nof_adders) == 1
	)
	# C: Adders can only be locked to a coefficient if enabled
	@constraint(model, [a in 1:nof_adders],
		sum(adder_output_value_sel[c, a] for c in 1:nof_constant_multiples) <= 1 # change rhs to adder_enables[a]
	)
	if param.lifting_constraints.adder_msd_complex_sorted_coefficient_lock
		# lock adder output to ascending CSD-complexity
		@constraint(model, [c = 1:nof_constant_multiples],
			adder_output_value_sel[c, nof_adders-nof_constant_multiples+c] == 1
		)
		# Constrain last N to always be enabled
		@constraint(model, [a = nof_adders-(nof_constant_multiples-1):nof_adders],
			adder_enables[a] == 1
		)
	end

	# C: Adder outputs respect their coefficient locks
	if param.constraint_options.use_indicator_constraints_not_big_m
		@constraint(model, [a = 1:nof_adders, c = 1:nof_constant_multiples],
			adder_output_value_sel[c, a] --> {adder_outputs[a] == constant_multiples[c]}
		)
	else
		output_bigM = nof_adder_inputs*max_shift_factor*maximum_value
		@constraint(model, [a = 1:nof_adders, c = 1:nof_constant_multiples],
			adder_outputs[a] <= constant_multiples[c] + (1-adder_output_value_sel[c, a])*output_bigM
		)
		@constraint(model, [a = 1:nof_adders, c = 1:nof_constant_multiples],
			constant_multiples[c] - (1-adder_output_value_sel[c, a])*output_bigM <= adder_outputs[a]
		)
	end

	if length(suggestions) > 0
		## if there are suggestions, constrain the outputs to these when enabled
		# TODO implement

		# @show nof_factor_adders = nof_adders-nof_constant_multiples
		# @show nof_suggestions = length(suggestions)
		# @show nof_free_adders = nof_factor_adders-nof_suggestions
		# @show (nof_factor_adders-(nof_suggestions-1)):nof_factor_adders
		# @constraint(model, [a = (nof_factor_adders-(nof_suggestions-1)):nof_factor_adders],
		# 	adder_outputs[nof_free_adders+a] == adder_enables[nof_free_adders+a]*suggestions[a]
		# )
	end

	## enumerate the depth of the adders
	@variable(model, 0 <= adder_depth[a = 0:nof_adders] <= nof_adders+1, Int)
	@constraint(model, adder_depth[0] == 0)

	@variable(model, 0 <= adder_input_depths[i = 1:nof_adder_inputs, a = 1:nof_adders] <= nof_adders+1, Int)
	depth_M = nof_adders+1
	if param.constraint_options.use_indicator_constraints_not_big_m
		@constraint(model, [s = 0:nof_adders, i = 1:nof_adder_inputs, a = 1:nof_adders],
			adder_input_value_sel[s,i,a] --> {adder_input_depths[i, a] == adder_depth[s]}
		)
	else
		depth_M = nof_adders+1
		@constraint(model, [s = 0:nof_adders, i = 1:nof_adder_inputs, a = 1:nof_adders],
			adder_input_depths[i, a] <= adder_depth[s] + (1-adder_input_value_sel[s,i,a])*depth_M
		)
		@constraint(model, [s = 0:nof_adders, i = 1:nof_adder_inputs, a = 1:nof_adders],
			adder_depth[s] - (1-adder_input_value_sel[s,i,a])*depth_M <= adder_input_depths[i, a]
		)
	end

	@variable(model, 0 <= adder_input_max_depth[a = 1:nof_adders] <= nof_adders, Int)
	@variable(model, adder_input_max_depth_sel[i = 1:nof_adder_inputs, a = 1:nof_adders], Bin)
	@constraint(model, [a = 1:nof_adders],
		sum(adder_input_max_depth_sel[i, a] for i in 1:nof_adder_inputs) == 1
	)
	@constraint(model, [i = 1:nof_adder_inputs, a = 1:nof_adders], # maximum input
		adder_input_max_depth[a] >= adder_input_depths[i, a]
	)
	if param.constraint_options.use_indicator_constraints_not_big_m
		@constraint(model, [i = 1:nof_adder_inputs, a = 1:nof_adders], # select one input depth
			adder_input_max_depth_sel[i,a] --> {adder_input_max_depth[a] == adder_input_depths[i, a]}
		)
	else
		@constraint(model, [i = 1:nof_adder_inputs, a = 1:nof_adders], # select one input depth
			adder_input_depths[i, a] - (1 - adder_input_max_depth_sel[i,a])*depth_M <= adder_input_max_depth[a]
		)
		@constraint(model, [i = 1:nof_adder_inputs, a = 1:nof_adders], # select one input depth
			adder_input_max_depth[a] <= adder_input_depths[i, a] + (1 - adder_input_max_depth_sel[i,a])*depth_M
		)
	end

	## adder depth = max(input_depths) + 1
	if param.constraint_options.use_indicator_constraints_not_big_m
		@constraint(model, [a = 1:nof_adders],
			adder_enables[a] --> {adder_depth[a] == 1 + adder_input_max_depth[a]}
		)
		@constraint(model, [a = 1:nof_adders],
			!adder_enables[a] --> {adder_depth[a] == 0}
		)
	else
		@constraint(model, [a = 1:nof_adders],
			1 + adder_input_max_depth[a] - (1-adder_enables[a])*depth_M <= adder_depth[a]
		)
		@constraint(model, [a = 1:nof_adders],
			adder_depth[a] <= 1 + adder_input_max_depth[a] + (1-adder_enables[a])*depth_M
		)
		@constraint(model, [a = 1:nof_adders],
			0 - adder_enables[a]*depth_M <= adder_depth[a]
		)
		@constraint(model, [a = 1:nof_adders],
			adder_depth[a] <= 0 + adder_enables[a]*depth_M
		)
	end

	## determine the maximum adder_depth
	@variable(model, 1 <= adder_depth_max <= nof_adders, Int)
	@constraint(model, [a = 1:nof_adders],
		adder_depth_max >= adder_depth[a]
	)
	@variable(model, adder_depth_max_sel[1:nof_adders], Bin)
	@constraint(model,
		sum(adder_depth_max_sel) == 1
	)
	if param.constraint_options.use_indicator_constraints_not_big_m
		@constraint(model, [a = 1:nof_adders],
			adder_depth_max_sel[a] --> {adder_depth_max == adder_depth[a]}
		)
	else
		@constraint(model, [a = 1:nof_adders],
			adder_depth[a] - (1 - adder_depth_max_sel[a])*depth_M <= adder_depth_max
		)
		@constraint(model, [a = 1:nof_adders],
			adder_depth_max <= adder_depth[a] + (1 - adder_depth_max_sel[a])*depth_M
		)
	end

	## limit adder depth
	@variable(model, 1 <= adder_depth_limit <= nof_adders, Int)
	@constraint(model, adder_depth_max <= adder_depth_limit)

	## limit adder count
	@variable(model, min_adders <= adder_enable_limit <= nof_adders, Int)
	@constraint(model, min_adders <= sum(adder_enables))
	@constraint(model, sum(adder_enables) <= adder_enable_limit)

	## sum(adder_depth) is between 1*unique_coeff and sum(nof_adders, nof_adders-1, ... 1)
	@variable(model, min_adders <= adder_depth_sum <= (nof_adders+1)*nof_adders/2, Int)
	@constraint(model, adder_depth_sum == sum(adder_depth))

	# @objective(model, Min, sum(adder_depth))
	if param.objective == MinAdderCount
		@objective(model, Min, adder_enable_limit)
	end
	if param.objective == MinMaxAdderDepth
		@objective(model, Min, adder_depth_limit)
	end
	if param.objective == MinAdderCountPlusMaxAdderDepth
		@objective(model, Min, adder_enable_limit + adder_depth_limit)
	end
	if param.objective == MinNaAdderCountPlusMaxAdderDepth
		@objective(model, Min, nof_adders*adder_enable_limit + adder_depth_limit)
	end
	if param.objective == MinAdderCountPlusNaMaxAdderDepth
		@objective(model, Min, adder_enable_limit + nof_adders*adder_depth_limit)
	end
	if param.objective == MinAdderDepthSum
		@objective(model, Min, adder_depth_sum)
	end

	set_optimize_hook(model, optimization_hook)
	model
end

end # module MCM