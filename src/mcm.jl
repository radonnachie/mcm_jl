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

function mcm(
    model::Model,
    constant_multiples::Vector{Int}
    ;
    nof_adders::Int = 7,
    nof_adder_inputs::Int = 2,
    data_bit_width::Int = 10,
    maximum_shift::Union{Nothing, Int} = nothing,
    objective::ObjectiveMCM = MinAdderCountPlusMaxAdderDepth
)::Vector{ResultsMCM}
	maximum_value = 2^data_bit_width

	nof_constant_multiples = length(constant_multiples)
	
	input_sign_values = [-1, 1]
	nof_input_sign_values = length(input_sign_values)
	
    if isnothing(maximum_shift)
        maximum_shift = ceil(Int, log2(maximum(constant_multiples)))
    end
	input_shift_values = [2^e for e in 0:maximum_shift]
	nof_input_shift_values = length(input_shift_values)

	# Adders have outputs.
	@variable(model,
		-maximum_value <= adder_outputs[0:nof_adders] <= maximum_value,
	Int)
	## A psuedo output for a static, non-existent adder is set to 1
	@constraint(model, adder_outputs[0] == 1)
	## The other outputs selectively target desired values
	@variable(model,
		adder_output_value_sel[
			1:nof_constant_multiples,
			1:nof_adders
		],
	Bin)
	@constraint(model, [a = 1:nof_adders],
		sum(adder_output_value_sel[v, a] for v in 1:nof_constant_multiples) <= 1
	)
	@constraint(model, [v = 1:nof_constant_multiples],
		sum(adder_output_value_sel[v, a] for a in 1:nof_adders) == 1
	)
	## Constrain adder output to its selected value
	delta_M = 2*maximum_value
	@constraint(model, [v = 1:nof_constant_multiples, a = 1:nof_adders],
        constant_multiples[v] - (1 - adder_output_value_sel[v, a])*delta_M <= adder_outputs[a]
	)
	@constraint(model, [v = 1:nof_constant_multiples, a = 1:nof_adders],
		adder_outputs[a] <= constant_multiples[v] + (1 - adder_output_value_sel[v, a])*delta_M
	)

	# Each adder input has 3 factors: sign, shift and value
	## the shift*value product is captured by indicator constraints in `input_shifted`
	## and then the final product is captured by indicator constraints in `input_value`
	@variable(model,
		-maximum_value <= adder_input_shifted[1:nof_adder_inputs, 1:nof_adders] <= maximum_value,
	Int)
	@variable(model,
		-maximum_value <= adder_input_value[1:nof_adder_inputs, 1:nof_adders] <= maximum_value,
	Int)

	# Each adder input is the product of (sign, shift, value)
	## The adder input value results from an indicator constraint on adder outputs
	@variable(model,
		adder_input_value_sel[
			0:nof_adders,
			1:nof_adder_inputs,
			1:nof_adders
		],
	Bin)
	@constraint(model, [i = 1:nof_adder_inputs, a = 1:nof_adders],
		sum(adder_input_value_sel[s, i, a] for s in 0:a-1) == 1
	)
	@constraint(model, [i = 1:nof_adder_inputs, a =1:nof_adders],
		sum(adder_input_value_sel[s, i, a] for s in a:nof_adders) == 0
	)
	value_M = 2*maximum_value
	@constraint(model, [s = 0:nof_adders, i = 1:nof_adder_inputs, a = 1:nof_adders],
		adder_outputs[s] - value_M + adder_input_value_sel[s, i, a]*value_M <= adder_input_value[i, a]
	)
	@constraint(model, [s = 0:nof_adders, i = 1:nof_adder_inputs, a = 1:nof_adders],
		adder_input_value[i, a] <= adder_outputs[s] + value_M - adder_input_value_sel[s, i, a]*value_M
	)

	## The input is selectively shifted, linearised indicator constraints on `input_shifted`
	@variable(model,
		adder_input_shift_sel[
			1:nof_input_shift_values,
			1:nof_adder_inputs,
			1:nof_adders
		],
	Bin)
	@constraint(model, [i = 1:nof_adder_inputs, a =1:nof_adders],
		sum(adder_input_shift_sel[s, i, a] for s in 1:nof_input_shift_values) == 1
	)
	shifted_M = 2*maximum_value*maximum(input_shift_values)
	@constraint(model, [s = 1:nof_input_shift_values, i = 1:nof_adder_inputs, a =1:nof_adders],
		adder_input_value[i,a]*input_shift_values[s] - (1 - adder_input_shift_sel[s, i, a])*shifted_M <= adder_input_shifted[i, a]
	)
	@constraint(model, [s = 1:nof_input_shift_values, i = 1:nof_adder_inputs, a =1:nof_adders],
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
	sign_M = shifted_M
	@constraint(model, [s = 1:nof_input_sign_values, i = 1:nof_adder_inputs, a =1:nof_adders],
		adder_input_shifted[i, a]*input_sign_values[s] - (1 - adder_input_sign_sel[s, i, a])*sign_M <= adder_inputs[i, a]
	)
	@constraint(model, [s = 1:nof_input_sign_values, i = 1:nof_adder_inputs, a =1:nof_adders],
		adder_inputs[i, a] <= adder_input_shifted[i, a]*input_sign_values[s] + (1 - adder_input_sign_sel[s, i, a])*sign_M
	)

	# Adder output is the sum of its inputs
	@variable(model,
		-maximum_value <= adder_results[
			1:nof_adders
		] <= maximum_value,
	Int)
	@constraint(model, [a = 1:nof_adders],
		adder_results[a] == sum(adder_inputs[i, a] for i in 1:nof_adder_inputs)
	)
	## The outputs are gated to effectively disable some adders
	@variable(model,
		adder_enables[
			1:nof_adders
		],
	Bin)
	### When enabled, constrain to result
	output_M = 2*maximum_value
	@constraint(model, [a = 1:nof_adders],
		adder_results[a] - (1 - adder_enables[a])*output_M <= adder_outputs[a]
	)
	@constraint(model, [a = 1:nof_adders],
		adder_outputs[a] <= adder_results[a] + (1 - adder_enables[a])*output_M
	)
	### When disabled, constrain to 0
	@constraint(model, [a = 1:nof_adders],
		0 - adder_enables[a]*output_M <= adder_outputs[a]
	)
	@constraint(model, [a = 1:nof_adders],
		adder_outputs[a] <= 0 + adder_enables[a]*output_M
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

    # if objective in [MinAdderCountPlusMaxAdderDepth, MinMaxAdderDepth]
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
    # end

	# @objective(model, Min, sum(adder_depth))
    if objective == MinAdderCount
	    @objective(model, Min, sum(adder_enables))
    end
    if objective == MinMaxAdderDepth
        @objective(model, Min, adder_depth_max)
    end
    if objective == MinAdderCountPlusMaxAdderDepth
	    @objective(model, Min, sum(adder_enables) + adder_depth_max)
    end
	
    # ts_start = time_ns()
	optimize!(model)
    # ts_end = time_ns()

    @show is_solved_and_feasible(model)
    @show result_count(model)

    results = Vector{ResultsMCM}()
    
    all_ao = [value.(adder_outputs;result=i) for i in 1:result_count(model)]
    unique_ao = unique(all_ao)
    unique_result_indices = [findfirst(x->x==un, all_ao) for un in unique_ao]

    for i in unique_result_indices
        push!(results, ResultsMCM(
            result_index = i,
            adder_count = sum(value.(adder_enables; result=i)),
            depth_max = floor(Int, value(adder_depth_max; result=i)),
            outputs = floor.(Int, value.(adder_outputs; result=i)),
            output_value_sel = value.(adder_output_value_sel; result=i),
            input_shifted = floor.(Int, value.(adder_input_shifted; result=i)),
            input_value = floor.(Int, value.(adder_input_value; result=i)),
            input_value_sel = value.(adder_input_value_sel; result=i),
            input_shift_sel = value.(adder_input_shift_sel; result=i),
            inputs = floor.(Int, value.(adder_inputs; result=i)),
            results = floor.(Int, value.(adder_results; result=i)),
            enables = value.(adder_enables; result=i),
            depth = floor.(Int, value.(adder_depth; result=i)),
            input_depths = floor.(Int, value.(adder_input_depths; result=i)),
        ))
    end
    results
end
