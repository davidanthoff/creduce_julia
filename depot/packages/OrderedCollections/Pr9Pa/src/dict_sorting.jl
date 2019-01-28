import Base: sort, sort!
function sort!(d::OrderedDict; byvalue::Bool=false, args...)
    if d.ndel > 0
        rehash!(d)
    end
    if byvalue
        p = sortperm(d.vals; args...)
    else
        p = sortperm(d.keys; args...)
    end
    d.keys = d.keys[p]
    d.vals = d.vals[p]
    rehash!(d)
    return d
end
sort(d::OrderedDict; args...) = sort!(copy(d); args...)
sort(d::Dict; args...) = sort!(OrderedDict(d); args...)
