mutable struct IntDisjointSets
    parents::Vector{Int}
    ranks::Vector{Int}
    ngroups::Int
    IntDisjointSets(n::Integer) = new(collect(1:n), zeros(Int, n), n)
end
length(s::IntDisjointSets) = length(s.parents)
num_groups(s::IntDisjointSets) = s.ngroups
function find_root_impl!(parents::Array{Int}, x::Integer)
    p = parents[x]
    @inbounds if parents[p] != p
        parents[x] = p = _find_root_impl!(parents, p)
    end
    p
end
function _find_root_impl!(parents::Array{Int}, x::Integer)
    @inbounds p = parents[x]
    @inbounds if parents[p] != p
        parents[x] = p = _find_root_impl!(parents, p)
    end
    p
end
find_root(s::IntDisjointSets, x::Integer) = find_root_impl!(s.parents, x)
""" """ in_same_set(s::IntDisjointSets, x::Integer, y::Integer) = find_root(s, x) == find_root(s, y)
function union!(s::IntDisjointSets, x::Integer, y::Integer)
    parents = s.parents
    xroot = find_root_impl!(parents, x)
    yroot = find_root_impl!(parents, y)
    xroot != yroot ?  root_union!(s, xroot, yroot) : xroot
end
function root_union!(s::IntDisjointSets, x::Integer, y::Integer)
    parents = s.parents
    rks = s.ranks
    @inbounds xrank = rks[x]
    @inbounds yrank = rks[y]
    if xrank < yrank
        x, y = y, x
    elseif xrank == yrank
        rks[x] += 1
    end
    @inbounds parents[y] = x
    @inbounds s.ngroups -= 1
    x
end
function push!(s::IntDisjointSets)
    x = length(s) + 1
    push!(s.parents, x)
    push!(s.ranks, 0)
    s.ngroups += 1
    return x
end
mutable struct DisjointSets{T}
    intmap::Dict{T,Int}
    revmap::Vector{T}
    internal::IntDisjointSets
    function DisjointSets{T}(xs) where T    # xs must be iterable
        imap = Dict{T,Int}()
        rmap = Vector{T}()
        n = length(xs)
        sizehint!(imap, n)
        sizehint!(rmap, n)
        id = 0
        for x in xs
            imap[x] = (id += 1)
            push!(rmap,x)
        end
        new{T}(imap, rmap, IntDisjointSets(n))
    end
end
length(s::DisjointSets) = length(s.internal)
num_groups(s::DisjointSets) = num_groups(s.internal)
""" """ find_root(s::DisjointSets{T}, x::T) where {T} = s.revmap[find_root(s.internal, s.intmap[x])]
in_same_set(s::DisjointSets{T}, x::T, y::T) where {T} = in_same_set(s.internal, s.intmap[x], s.intmap[y])
union!(s::DisjointSets{T}, x::T, y::T) where {T} = s.revmap[union!(s.internal, s.intmap[x], s.intmap[y])]
root_union!(s::DisjointSets{T}, x::T, y::T) where {T} = s.revmap[root_union!(s.internal, s.intmap[x], s.intmap[y])]
function push!(s::DisjointSets{T}, x::T) where T
    id = push!(s.internal)
    s.intmap[x] = id
    push!(s.revmap,x) # Note, this assumes invariant: length(s.revmap) == id
    x
end