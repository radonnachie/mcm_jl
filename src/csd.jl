function csd(v::UInt)::String
    b = reverse(bitstring(v))
    r = r"(1+10)" # match zero followed by two or more 1s

    while true
        m_itr = eachmatch(
            r, b
        )
        if isempty(m_itr)
            break
        end
        m = first(m_itr)
        len = length(m.captures[1])
        b = b[1:m.offset-1]*"-"*("0"^(len-2))*"1"*b[m.offset+len:end]
    end

    replace(reverse(b), '1'=>'+')
end

function union_csd(c1::String, c2::String)::String
    String([
        c1[i] == c2[i] ? c1[i] : '?'
        for i in 1:length(c1)
    ])
end

function count_components(csd_bitstring::String)
    count(x!='0' for x in csd_bitstring)
end

function unique_subsections(csd_bitstrings::Vector{String}; nof_non_zero::Int=2)::Vector{String}
    subs = Vector{String}()
    for csd_str in csd_bitstrings
        for sub in eachmatch(Regex("[^0]"*"0+[^0]"^(nof_non_zero-1)), csd_str; overlap=true)
            if !(sub.match in subs)
                push!(subs, sub.match)
            end
        end
    end
    subs
end

function csd2int(csd_str::String; big_endian=true)::Int
    val = 0
    bit_val = 1
    for sbit in (big_endian ? reverse(csd_str) : csd_str)
        if sbit == '+'
            val += bit_val
        elseif sbit == '-'
            val -= bit_val
        end
        bit_val *= 2
    end
    val
end

function get_odd_factor(v::Int)::Int
    while v != 0 && mod(v, 2) == 0
        v = div(v, 2)
    end
    v
end

function number_of_adders_min(coeffs::Vector{UInt}; nof_adder_inputs::Int=2)::Int
	if length(coeffs) == 0
		return 0
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
	return min_adders
end

function number_of_adders_max_ktree(coeffs::Vector{UInt}; nof_adder_inputs::Int=2)::Int
	if length(coeffs) == 0
		return 0
	end
	comp_counts = count_components.(csd.(coeffs))
	return sum(ceil.(Int, (comp_counts .- 1) ./ (nof_adder_inputs-1)))
end

function get_unique_subterms(coeffs::Vector{UInt}; nof_non_zero::Int=2)::Vector{Int}
	if length(coeffs) == 0
		return []
	end
    csds = String.(lstrip.(csd.(coeffs), '0'))
    sub_csds = unique_subsections(csds; nof_non_zero=nof_non_zero)
    sub_csd_ints = csd2int.(sub_csds)
    unique(abs.(sub_csd_ints))
end

function number_of_adders_max_uniqueterms(coeffs::Vector{UInt}; nof_adder_inputs::Int=2)::Int
    sub_csd_ints = get_unique_subterms(coeffs; nof_non_zero=nof_adder_inputs)
    append!(sub_csd_ints, Int.(coeffs))
    return length(unique(abs.(sub_csd_ints)))
end

function number_of_adders_max_nonzeropairs(coeffs::Vector{UInt}; nof_adder_inputs::Int=2)::Int
	comp_counts = count_components.(csd.(coeffs))
    return sum(ceil.(Int, comp_counts./nof_adder_inputs))
end