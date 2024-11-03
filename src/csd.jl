function csd(v::UInt)
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