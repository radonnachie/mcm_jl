using JuMP
using Printf
using Gurobi

function getGurobiModelMILP(;
    param::GurobiParam=GurobiParam()
)::Model

    model = Model(Gurobi.Optimizer)
	set_attribute(model, "TimeLimit", param.TimeLimit)
	set_attribute(model, "Presolve", param.Presolve)
	set_attribute(model, "IntegralityFocus", param.IntegralityFocus)
	set_attribute(model, "MIPFocus", param.MIPFocus)
	set_attribute(model, "ConcurrentMIP", param.ConcurrentMIP)
	# set_attribute(model, "PoolSolutions", 100)

    model
end

function sort_by_component_count!(coeffs::Vector{Int})
    sort(
        sort(coeffs),
        by=x->count_components(csd(UInt(abs(x))))
    )
end

function number_of_adders_minmax(coeffs::Vector{UInt}; nof_adder_inputs::Int=2)::Tuple{Int, Int}
	if length(coeffs) == 0
		return 0, 0
	end
	comp_counts = count_components.(csd.(coeffs))
	l = ceil.(Int, log.(nof_adder_inputs, comp_counts))
	min_adders = l[1]
	if length(l) > 1 
		min_adders += sum(
			max(1, ceil(log(nof_adder_inputs, comp_counts[i+1]/comp_counts[i])))
			for i in 1:length(l)-1
		)
	end
	max_adders = sum(comp_counts .- 1)
	return min_adders, max_adders
end

function mcm!(
    model::Model,
    constant_multiples::Vector{Int},
	param::MCMParam
)::Vector{ResultsMCM}
	maximum_value = 2^param.data_bit_width

	nof_constant_multiples = length(constant_multiples)
	nof_unique_constant_multiples = length(unique(constant_multiples))

	input_sign_values = [-1, 1]
	nof_input_sign_values = length(input_sign_values)

	input_shift_values = [2^e for e in 0:param.maximum_shift]
	nof_shift_values = length(input_shift_values)

	nof_adders = param.max_nof_adders
	nof_adder_inputs = param.nof_adder_inputs

	# Adders have outputs.
	@variable(model,
		0 <= adder_outputs[0:nof_adders] <= maximum_value,
	Int)
	## A psuedo output for a static, non-existent adder is set to 1
	@constraint(model, adder_outputs[0] == 1)
	## Because adder inputs are restricted to the outputs of previous adders
	## the last N outputs are constrained to the coefficients, which are ordered
	## by the number of CSD high-bits
	sort_by_component_count!(constant_multiples)
	@constraint(model, [v = 1:nof_constant_multiples],
		adder_outputs[nof_adders-nof_constant_multiples+v] == constant_multiples[v]
	)
	### backwards compatibility
	adder_output_value_sel = zeros(Bool,
		nof_constant_multiples,
		nof_adders
	)
	for v in 1:nof_constant_multiples
		adder_output_value_sel[v,nof_adders-nof_constant_multiples+v] = true
	end
	## The adders are enabled
	@variable(model,
		adder_enables[
			1:nof_adders
		],
	Bin)
	### Constrain last N to always be enabled
	@constraint(model, [a = nof_adders-(nof_constant_multiples-1):nof_adders],
		adder_enables[a] == 1
	)

	# Each adder input has 3 factors: sign, shift and value
	## the shift*value product is captured by indicator constraints in `input_shifted`
	## and then the final product is captured by indicator constraints in `input_value`
	max_shift_factor = maximum(input_shift_values)
	@variable(model,
		-max_shift_factor*maximum_value <= adder_input_shifted[1:nof_adder_inputs, 1:nof_adders] <= max_shift_factor*maximum_value,
	Int)
	@variable(model,
		-maximum_value <= adder_input_value[1:nof_adder_inputs, 1:nof_adders] <= maximum_value,
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
	@constraint(model, [i = 1:nof_adder_inputs, a = 1:nof_adders],
		sum(adder_input_value_sel[s, i, a] for s in 0:a-1) == adder_enables[a]
	)
	@constraint(model, [i = 1:nof_adder_inputs, a = 1:nof_adders],
		sum(adder_input_value_sel[s, i, a] for s in a:nof_adders) == 0
	)
	value_M = 2*maximum_value
	@constraint(model, [s = 0:nof_adders, i = 1:nof_adder_inputs, a = 1:nof_adders],
		adder_outputs[s] - (1 - adder_input_value_sel[s, i, a])*value_M <= adder_input_value[i, a]
	)
	@constraint(model, [s = 0:nof_adders, i = 1:nof_adder_inputs, a = 1:nof_adders],
		adder_input_value[i, a] <= adder_outputs[s] + (1 - adder_input_value_sel[s, i, a])*value_M
	)
	### non-enabled adders have zero as input values
	@constraint(model, [i = 1:nof_adder_inputs, a = 1:nof_adders],
		0 - adder_enables[a]*value_M <= adder_input_value[i, a]
	)
	@constraint(model, [i = 1:nof_adder_inputs, a = 1:nof_adders],
		adder_input_value[i, a] <= 0 + adder_enables[a]*value_M
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
	## for the output to be odd, there must be an odd number of non-shifted inputs (which are all odd) 
	### constrain one input to never be shifted
	@constraint(model, [a = 1:nof_adders],
		adder_input_shift_sel[1, 1, a] == 1
	)
	## if the output is even (an even number of inputs were not shifted), a right shift after the sum will be constrained to drop the low LSBs
	@variable(model, 0 <= adder_input_noshift_sel_oddity[1:nof_adders] <= nof_adder_inputs, Int)
	@variable(model, adder_input_noshift_sel_is_odd[1:nof_adders], Bin)
	@constraint(model, [a = 1:nof_adders],
		sum(adder_input_shift_sel[1, i, a] for i in 1:nof_adder_inputs) == 2*adder_input_noshift_sel_oddity[a]+adder_input_noshift_sel_is_odd[a]
	)

	shifted_M = 2*maximum_value*maximum(input_shift_values)
	@constraint(model, [s = 1:nof_shift_values, i = 1:nof_adder_inputs, a = 1:nof_adders],
		adder_input_value[i,a]*input_shift_values[s] - (1 - adder_input_shift_sel[s, i, a])*shifted_M <= adder_input_shifted[i, a]
	)
	@constraint(model, [s = 1:nof_shift_values, i = 1:nof_adder_inputs, a = 1:nof_adders],
		adder_input_shifted[i, a] <= adder_input_value[i,a]*input_shift_values[s] + (1 - adder_input_shift_sel[s, i, a])*shifted_M
	)

	## The shifted input is selectively signed, linearised indicator constraints on `inputs`
	@variable(model,
		-maximum_value <= adder_inputs[1:nof_adder_inputs, 1:nof_adders] <= maximum_value,
	Int)
	@variable(model,
		adder_input_sign_sel[
			1:nof_input_sign_values,
			1:nof_adder_inputs,
			1:nof_adders
		],
	Bin)
	@constraint(model, [i = 1:nof_adder_inputs, a = 1:nof_adders],
		sum(adder_input_sign_sel[s, i, a] for s in 1:nof_input_sign_values) == 1
	)
	## At most one input negated
	@constraint(model, [a = 1:nof_adders],
		sum(adder_input_sign_sel[1, i, a] for i in 1:nof_adder_inputs) <= 1
	)
	sign_M = shifted_M
	@constraint(model, [s = 1:nof_input_sign_values, i = 1:nof_adder_inputs, a = 1:nof_adders],
		adder_input_shifted[i, a]*input_sign_values[s] - (1 - adder_input_sign_sel[s, i, a])*sign_M <= adder_inputs[i, a]
	)
	@constraint(model, [s = 1:nof_input_sign_values, i = 1:nof_adder_inputs, a = 1:nof_adders],
		adder_inputs[i, a] <= adder_input_shifted[i, a]*input_sign_values[s] + (1 - adder_input_sign_sel[s, i, a])*sign_M
	)

	# Adder output is the sum of its inputs
	@variable(model, 0 <= adder_sums[1:nof_adders] <= max_shift_factor*maximum_value)
	sum_M = nof_adder_inputs*max_shift_factor*maximum_value
	## Adder sums should be unique
	@variable(model, adder_sum_equivalence_sel[1:nof_adders, 1:nof_adders], Bin)
	@constraint(model, [a_other = 1:nof_adders, a = 1:nof_adders],
		adder_sums[a_other] - (1-adder_sum_equivalence_sel[a_other, a])*sum_M <= adder_sums[a]
	)
	@constraint(model, [a_other = 1:nof_adders, a = 1:nof_adders],
		adder_sums[a] <= adder_sums[a_other] + (1-adder_sum_equivalence_sel[a_other, a])*sum_M
	)
	@variable(model, 1 <= adder_sum_equivalents[1:nof_adders] <= nof_adders, Int)
	@constraint(model, [a = 1:nof_adders],
		adder_sum_equivalents[a] == sum(adder_sum_equivalence_sel[a_other, a] for a_other in 1:nof_adders)
	)
	# @constraint(model, [a = 1:nof_adders],
	# 	1 <= adder_sum_equivalents[a]
	# )
	@constraint(model, [a = 1:nof_adders],
		adder_sum_equivalents[a] <= 1 + (1 - adder_enables[a])*nof_adders
	)
	## When enabled, constrain output to sum
	@constraint(model, [a = 1:nof_adders],
		sum(adder_inputs[i, a] for i in 1:nof_adder_inputs) - (1 - adder_enables[a])*sum_M <= adder_sums[a]
	)
	@constraint(model, [a = 1:nof_adders],
		adder_sums[a] <= sum(adder_inputs[i, a] for i in 1:nof_adder_inputs) + (1 - adder_enables[a])*sum_M
	)
	## When disabled, constrain output to 0
	@constraint(model, [a = 1:nof_adders],
		0 - adder_enables[a]*sum_M <= adder_sums[a]
	)
	@constraint(model, [a = 1:nof_adders],
		adder_sums[a] <= 0 + adder_enables[a]*sum_M
	)
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
	@constraint(model, [s = 1:nof_shift_values, a = 1:nof_adders],
		adder_sums[a] - (1 - adder_sums_right_shift_sel[s, a])*max_shift_factor*sum_M <= adder_outputs[a]*input_shift_values[s]
	)
	@constraint(model, [s = 1:nof_shift_values, a = 1:nof_adders],
		adder_outputs[a]*input_shift_values[s] <= adder_sums[a] + (1 - adder_sums_right_shift_sel[s, a])*max_shift_factor*sum_M
	)
	## adder outputs must be odd, when enabled (zero when not enabled)
	@variable(model,
		0 <= adder_output_oddity[
			1:nof_adders
		] <= nof_adder_inputs*max_shift_factor*maximum_value/2,
	Int)
	@constraint(model, [a = 1:nof_adders],
		adder_outputs[a] == 2*adder_output_oddity[a] + adder_enables[a]
	)

	## Each non-output adder is either used as an input or is not enabled
	@constraint(model, [a = 1:nof_adders-nof_constant_multiples],
		sum(adder_input_value_sel[a, i, s] for s in a+1:nof_adders, i in 1:nof_adder_inputs) <= adder_enables[a]*nof_adders
	)

	## enumerate the depth of the adders
	@variable(model, 0 <= adder_depth[a = 0:nof_adders] <= nof_adders+1, Int)
	@constraint(model, adder_depth[0] == 0)

	@variable(model, 0 <= adder_input_depths[i = 1:nof_adder_inputs, a = 1:nof_adders] <= nof_adders+1, Int)
	depth_M = nof_adders+1
	@constraint(model, [s = 0:nof_adders, i = 1:nof_adder_inputs, a = 1:nof_adders],
		adder_depth[s] - (1 - adder_input_value_sel[s,i,a])*depth_M <= adder_input_depths[i, a] 
	)
	@constraint(model, [s = 0:nof_adders, i = 1:nof_adder_inputs, a = 1:nof_adders],
		adder_input_depths[i, a] <= adder_depth[s] + (1 - adder_input_value_sel[s,i,a])*depth_M
	)

	@variable(model, 0 <= adder_input_max_depth[a = 1:nof_adders] <= nof_adders, Int)
	@variable(model, adder_input_max_depth_sel[i = 1:nof_adder_inputs, a = 1:nof_adders], Bin)
	@constraint(model, [a = 1:nof_adders],
		sum(adder_input_max_depth_sel[i, a] for i in 1:nof_adder_inputs) == 1
	)
	@constraint(model, [i = 1:nof_adder_inputs, a = 1:nof_adders], # select one input depth
		adder_input_depths[i, a] - (1 - adder_input_max_depth_sel[i,a])*depth_M <= adder_input_max_depth[a]
	)
	@constraint(model, [i = 1:nof_adder_inputs, a = 1:nof_adders], # select one input depth
		adder_input_max_depth[a] <= adder_input_depths[i, a] + (1 - adder_input_max_depth_sel[i,a])*depth_M
	)
	@constraint(model, [i = 1:nof_adder_inputs, a = 1:nof_adders], # maximum input
		adder_input_max_depth[a] >= adder_input_depths[i, a]
	)

	## adder depth = max(input_depths) + 1
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

	## determine the maximum adder_depth
	@variable(model, 0 <= adder_depth_max <= nof_adders+1, Int)
	@constraint(model, [a = 1:nof_adders],
		adder_depth_max >= adder_depth[a]
	)
	@variable(model, adder_depth_max_sel[1:nof_adders], Bin)
	@constraint(model,
		sum(adder_depth_max_sel) == 1
	)
	@constraint(model, [a = 1:nof_adders],
		adder_depth[a] - (1 - adder_depth_max_sel[a])*depth_M <= adder_depth_max
	)
	@constraint(model, [a = 1:nof_adders],
		adder_depth_max <= adder_depth[a] + (1 - adder_depth_max_sel[a])*depth_M
	)

	## limit adder depth
	@variable(model, 1 <= adder_depth_limit <= nof_adders+1, Int)
	@constraint(model, adder_depth_max <= adder_depth_limit)

	## limit adder count
	@variable(model, param.min_nof_adders <= adder_enable_limit <= nof_adders, Int)
	@constraint(model, sum(adder_enables) <= adder_enable_limit)

	## sum(adder_depth) is between 1*unique_coeff and sum(nof_adders, nof_adders-1, ... 1)
	@variable(model, param.min_nof_adders <= adder_depth_sum <= (nof_adders+1)*nof_adders/2, Int)
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
	if param.objective == MinAdderDepthSum
		@objective(model, Min, adder_depth_sum)
	end

	optimize!(model)

	@show is_solved_and_feasible(model)
	@show result_count(model)

	results = Vector{ResultsMCM}()

	all_ao = [unique(value.(adder_outputs;result=i)) for i in 1:result_count(model)]
	unique_ao = unique(all_ao)
	unique_result_indices = [findfirst(x->x==un, all_ao) for un in unique_ao]

	for i in unique_result_indices
		push!(results, ResultsMCM(
			result_index = i,
			adder_count = sum(round.(Int, value.(adder_enables; result=i))),
			depth_max = floor(Int, value(adder_depth_max; result=i)),
			outputs = floor.(Int, value.(adder_outputs; result=i)),
			output_value_sel = adder_output_value_sel,
			input_shifted = floor.(Int, value.(adder_input_shifted; result=i)),
			input_value = floor.(Int, value.(adder_input_value; result=i)),
			input_value_sel = round.(Int, value.(adder_input_value_sel; result=i)),
			input_shift_sel = round.(Int, value.(adder_input_shift_sel; result=i)),
			inputs = floor.(Int, value.(adder_inputs; result=i)),
			results = zeros(Int, nof_adders),
			enables = round.(Int, value.(adder_enables; result=i)),
			depth = floor.(Int, value.(adder_depth; result=i)),
			input_depths = floor.(Int, value.(adder_input_depths; result=i)),
		))
	end
	results
end
