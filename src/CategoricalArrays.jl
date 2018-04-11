__precompile__()
module CategoricalArrays
    export CategoricalPool, CategoricalValue, CategoricalString
    export AbstractCategoricalArray, AbstractCategoricalVector, AbstractCategoricalMatrix,
           CategoricalArray, CategoricalVector, CategoricalMatrix
    export AbstractMissingCategoricalArray, AbstractMissingCategoricalVector,
           AbstractMissingCategoricalMatrix,
           MissingCategoricalArray, MissingCategoricalVector, MissingCategoricalMatrix
    export LevelsException, OrderedLevelsException
    export categorical, compress, decompress, droplevels!, levels, levels!, isordered, ordered!
    export cut, recode, recode!
    using Compat
    using Reexport
    # TODO: cannot @reexport in conditional, the below should be removed when 0.6 is deprecated
    @reexport using Missings
    if VERSION >= v"0.7.0-DEV.3052"
        using Printf
    end
    using JSON # FIXME make JSON optional dependency when core Julia will support that
const DefaultRefType = UInt32
mutable struct CategoricalPool{T, R <: Integer, V}
    index::Vector{T}        # category levels ordered by their reference codes
    invindex::Dict{T, R}    # map from category levels to their reference codes
    order::Vector{R}        # 1-to-1 map from `index` to `level` (position of i-th category in `levels`)
    levels::Vector{T}       # category levels ordered by externally specified order
    valindex::Vector{V}     # "category value" objects 1-to-1 matching `index`
    ordered::Bool
    function CategoricalPool{T, R, V}(index::Vector{T},
                                      invindex::Dict{T, R},
                                      order::Vector{R},
                                      ordered::Bool) where {T, R, V}
        if iscatvalue(T)
            throw(ArgumentError("Level type $T cannot be a categorical value type"))
        end
        if !iscatvalue(V)
            throw(ArgumentError("Type $V is not a categorical value type"))
        end
        if leveltype(V) !== T
            throw(ArgumentError("Level type of the categorical value ($(leveltype(V))) and of the pool ($T) do not match"))
        end
        if reftype(V) !== R
            throw(ArgumentError("Reference type of the categorical value ($(reftype(V))) and of the pool ($R) do not match"))
        end
        levels = similar(index)
        levels[order] = index
        pool = new(index, invindex, order, levels, V[], ordered)
        buildvalues!(pool)
        return pool
    end
end
struct LevelsException{T, R} <: Exception
    levels::Vector{T}
end
struct OrderedLevelsException{T, S} <: Exception
    newlevel::S
    levels::Vector{T}
end
struct CategoricalValue{T, R <: Integer}
    level::R
    pool::CategoricalPool{T, R, CategoricalValue{T, R}}
end
struct CategoricalString{R <: Integer} <: AbstractString
    level::R
    pool::CategoricalPool{String, R, CategoricalString{R}}
end
abstract type AbstractCategoricalArray{T, N, R, V, C, U} <: AbstractArray{Union{C, U}, N} end
const AbstractCategoricalVector{T, R, V, C, U} = AbstractCategoricalArray{T, 1, R, V, C, U}
const AbstractCategoricalMatrix{T, R, V, C, U} = AbstractCategoricalArray{T, 2, R, V, C, U}
struct CategoricalArray{T, N, R <: Integer, V, C, U} <: AbstractCategoricalArray{T, N, R, V, C, U}
    refs::Array{R, N}
    pool::CategoricalPool{V, R, C}
    function CategoricalArray{T, N}(refs::Array{R, N},
                                    pool::CategoricalPool{V, R, C}) where
                                                 {T, N, R <: Integer, V, C}
        T === V || T == Union{V, Missing} || throw(ArgumentError("T ($T) must be equal to $V or Union{$V, Missing}"))
        U = T >: Missing ? Missing : Union{}
        new{T, N, R, V, C, U}(refs, pool)
    end
end
const CategoricalVector{T, R, V, C, U} = CategoricalArray{T, 1, V, C, U}
const CategoricalMatrix{T, R, V, C, U} = CategoricalArray{T, 2, V, C, U}
function buildindex(invindex::Dict{S, R}) where {S, R <: Integer}
    index = Vector{S}(undef, length(invindex))
    for (v, i) in invindex
        index[i] = v
    end
    return index
end
function buildinvindex(index::Vector{T}, ::Type{R}=DefaultRefType) where {T, R}
    if length(index) > typemax(R)
        throw(LevelsException{T, R}(index[typemax(R)+1:end]))
    end
    invindex = Dict{T, R}()
    for (i, v) in enumerate(index)
        invindex[v] = i
    end
    return invindex
end
function buildvalues!(pool::CategoricalPool)
    resize!(pool.valindex, length(levels(pool)))
    for i in eachindex(pool.valindex)
        v = catvalue(i, pool)
        @inbounds pool.valindex[i] = v
    end
    return pool.valindex
end
function buildorder!(order::Array{R},
                     invindex::Dict{S, R},
                     levels::Vector{S}) where {S, R <: Integer}
    for (i, v) in enumerate(levels)
        order[invindex[convert(S, v)]] = i
    end
    return order
end
function buildorder(invindex::Dict{S, R}, levels::Vector) where {S, R <: Integer}
    order = Vector{R}(undef, length(invindex))
    return buildorder!(order, invindex, levels)
end
function CategoricalPool(index::Vector{S},
                         invindex::Dict{S, T},
                         order::Vector{R},
                         ordered::Bool=false) where {S, T <: Integer, R <: Integer}
    invindex = convert(Dict{S, R}, invindex)
    C = catvaluetype(S, R)
    V = leveltype(C) # might be different from S (e.g. S == SubString, V == String)
    CategoricalPool{V, R, C}(index, invindex, order, ordered)
end
CategoricalPool{T, R, C}(ordered::Bool=false) where {T, R, C} =
    CategoricalPool{T, R, C}(T[], Dict{T, R}(), R[], ordered)
CategoricalPool{T, R}(ordered::Bool=false) where {T, R} =
    CategoricalPool(T[], Dict{T, R}(), R[], ordered)
CategoricalPool{T}(ordered::Bool=false) where {T} =
    CategoricalPool{T, DefaultRefType}(ordered)
function CategoricalPool{T, R}(index::Vector,
                               ordered::Bool=false) where {T, R}
    invindex = buildinvindex(index, R)
    order = Vector{R}(1:length(index))
    CategoricalPool(index, invindex, order, ordered)
end
function CategoricalPool(index::Vector, ordered::Bool=false)
    invindex = buildinvindex(index)
    order = Vector{DefaultRefType}(1:length(index))
    return CategoricalPool(index, invindex, order, ordered)
end
function CategoricalPool(invindex::Dict{S, R},
                         ordered::Bool=false) where {S, R <: Integer}
    index = buildindex(invindex)
    order = Vector{DefaultRefType}(1:length(index))
    return CategoricalPool(index, invindex, order, ordered)
end
function CategoricalPool(index::Vector{S},
                         invindex::Dict{S, R},
                         ordered::Bool=false) where {S, R <: Integer}
    order = Vector{DefaultRefType}(1:length(index))
    return CategoricalPool(index, invindex, order, ordered)
end
function CategoricalPool(index::Vector{T},
                         levels::Vector{T},
                         ordered::Bool=false) where {T}
    invindex = buildinvindex(index)
    order = buildorder(invindex, levels)
    return CategoricalPool(index, invindex, order, ordered)
end
function CategoricalPool(invindex::Dict{S, R},
                         levels::Vector{S},
                         ordered::Bool=false) where {S, R <: Integer}
    index = buildindex(invindex)
    order = buildorder(invindex, levels)
    return CategoricalPool(index, invindex, order, ordered)
end
Base.convert(::Type{T}, pool::T) where {T <: CategoricalPool} = pool
Base.convert(::Type{CategoricalPool{S}}, pool::CategoricalPool{T, R}) where {S, T, R <: Integer} =
    convert(CategoricalPool{S, R}, pool)
function Base.convert(::Type{CategoricalPool{S, R}}, pool::CategoricalPool) where {S, R <: Integer}
    if length(levels(pool)) > typemax(R)
        throw(LevelsException{S, R}(levels(pool)[typemax(R)+1:end]))
    end
    indexS = convert(Vector{S}, pool.index)
    invindexS = convert(Dict{S, R}, pool.invindex)
    order = convert(Vector{R}, pool.order)
    return CategoricalPool(indexS, invindexS, order, pool.ordered)
end
function Base.show(io::IO, pool::CategoricalPool{T, R}) where {T, R}
    @printf(io, "%s{%s,%s}([%s])", typeof(pool).name, T, R,
                join(map(repr, levels(pool)), ","))
    pool.ordered && print(io, " with ordered levels")
end
Base.length(pool::CategoricalPool) = length(pool.index)
Base.getindex(pool::CategoricalPool, i::Integer) = pool.valindex[i]
Base.get(pool::CategoricalPool, level::Any) = pool.invindex[level]
Base.get(pool::CategoricalPool, level::Any, default::Any) = get(pool.invindex, level, default)
@inline function push_level!(pool::CategoricalPool{T, R}, level) where {T, R}
    x = convert(T, level)
    n = length(pool)
    if n >= typemax(R)
        throw(LevelsException{T, R}([level]))
    end
    i = R(n + 1)
    push!(pool.index, x)
    push!(pool.order, i)
    push!(pool.levels, x)
    push!(pool.valindex, catvalue(i, pool))
    i
end
@inline function Base.get!(pool::CategoricalPool, level::Any)
    get!(pool.invindex, level) do
        if isordered(pool)
            throw(OrderedLevelsException(level, pool.levels))
        end
        push_level!(pool, level)
    end
end
@inline function Base.push!(pool::CategoricalPool, level)
    get!(pool.invindex, level) do
        push_level!(pool, level)
    end
    return pool
end
function Base.append!(pool::CategoricalPool, levels)
    for level in levels
        push!(pool, level)
    end
    return pool
end
function Base.delete!(pool::CategoricalPool{S}, levels...) where S
    for level in levels
        levelS = convert(S, level)
        if haskey(pool.invindex, levelS)
            ind = pool.invindex[levelS]
            delete!(pool.invindex, levelS)
            splice!(pool.index, ind)
            ord = splice!(pool.order, ind)
            splice!(pool.levels, ord)
            splice!(pool.valindex, ind)
            for i in ind:length(pool)
                pool.invindex[pool.index[i]] -= 1
                pool.valindex[i] = catvalue(i, pool)
            end
            for i in 1:length(pool)
                pool.order[i] > ord && (pool.order[i] -= 1)
            end
        end
    end
    return pool
end
function levels!(pool::CategoricalPool{S, R}, newlevels::Vector) where {S, R}
    levs = convert(Vector{S}, newlevels)
    if !allunique(levs)
        throw(ArgumentError(string("duplicated levels found in levs: ",
                                   join(unique(filter(x->sum(levs.==x)>1, levs)), ", "))))
    end
    n = length(levs)
    if n > typemax(R)
        throw(LevelsException{S, R}(setdiff(levs, levels(pool))[typemax(R)-length(levels(pool))+1:end]))
    end
    # No deletions: can preserve position of existing levels
    # equivalent to issubset but faster due to JuliaLang/julia#24624
    if isempty(setdiff(pool.index, levs))
        append!(pool, setdiff(levs, pool.index))
    else
        empty!(pool.invindex)
        resize!(pool.index, n)
        resize!(pool.valindex, n)
        resize!(pool.order, n)
        resize!(pool.levels, n)
        for i in 1:n
            v = levs[i]
            pool.index[i] = v
            pool.invindex[v] = i
            pool.valindex[i] = catvalue(i, pool)
        end
    end
    buildorder!(pool.order, pool.invindex, levs)
    for (i, x) in enumerate(pool.order)
        pool.levels[x] = pool.index[i]
    end
    return pool
end
index(pool::CategoricalPool) = pool.index
Missings.levels(pool::CategoricalPool) = pool.levels
order(pool::CategoricalPool) = pool.order
isordered(pool::CategoricalPool) = pool.ordered
ordered!(pool::CategoricalPool, ordered) = (pool.ordered = ordered; pool)
function Base.showerror(io::IO, err::LevelsException{T, R}) where {T, R}
    levs = join(repr.(err.levels), ", ", " and ")
    print(io, "cannot store level(s) $levs since reference type $R can only hold $(typemax(R)) levels. Use the decompress function to make room for more levels.")
end
function Base.showerror(io::IO, err::OrderedLevelsException)
    print(io, "cannot add new level $(err.newlevel) since ordered pools cannot be extended implicitly. Use the levels! function to set new levels, or the ordered! function to mark the pool as unordered.")
end
const CatValue{R} = Union{CategoricalValue{T, R} where T,
                          CategoricalString{R}}
iscatvalue(::Type) = false
iscatvalue(::Type{Union{}}) = false # prevent incorrect dispatch to Type{<:CatValue} method
iscatvalue(::Type{<:CatValue}) = true
iscatvalue(x::Any) = iscatvalue(typeof(x))
leveltype(::Type{<:CategoricalValue{T}}) where {T} = T
leveltype(::Type{<:CategoricalString}) = String
leveltype(::Type) = throw(ArgumentError("Not a categorical value type"))
leveltype(x::Any) = leveltype(typeof(x))
reftype(::Type{<:CatValue{R}}) where {R} = R
reftype(x::Any) = reftype(typeof(x))
pool(x::CatValue) = x.pool
level(x::CatValue) = x.level
unwrap_catvaluetype(::Type{T}) where {T} = T
unwrap_catvaluetype(::Type{T}) where {T >: Missing} =
    Union{unwrap_catvaluetype(Missings.T(T)), Missing}
unwrap_catvaluetype(::Type{Union{}}) = Union{} # prevent incorrect dispatch to T<:CatValue method
unwrap_catvaluetype(::Type{Any}) = Any # prevent recursion in T>:Missing method
unwrap_catvaluetype(::Type{T}) where {T <: CatValue} = leveltype(T)
catvaluetype(::Type{T}, ::Type{R}) where {T >: Missing, R} =
    catvaluetype(Missings.T(T), R)
catvaluetype(::Type{T}, ::Type{R}) where {T <: CatValue, R} =
    catvaluetype(leveltype(T), R)
catvaluetype(::Type{Any}, ::Type{R}) where {R} =
    CategoricalValue{Any, R}  # prevent recursion in T>:Missing method
catvaluetype(::Type{T}, ::Type{R}) where {T, R} =
    CategoricalValue{T, R}
catvaluetype(::Type{<:AbstractString}, ::Type{R}) where {R} =
    CategoricalString{R}
catvaluetype(::Type{Union{}}, ::Type{R}) where {R} = CategoricalValue{Union{}, R}
Base.get(x::CatValue) = index(pool(x))[level(x)]
order(x::CatValue) = order(pool(x))[level(x)]
catvalue(level::Integer, pool::CategoricalPool{T, R, C}) where {T, R, C} =
    C(convert(R, level), pool)
Base.promote_rule(::Type{C}, ::Type{T}) where {C <: CatValue, T} = promote_type(leveltype(C), T)
Base.promote_rule(::Type{C}, ::Type{T}) where {C <: CategoricalString, T <: AbstractString} =
    promote_type(leveltype(C), T)
Base.promote_rule(::Type{C}, ::Type{Missing}) where {C <: CatValue} = Union{C, Missing}
Base.convert(::Type{Ref}, x::CatValue) = RefValue{leveltype(x)}(x)
Base.convert(::Type{String}, x::CatValue) = convert(String, get(x))
Base.convert(::Type{Any}, x::CatValue) = x
Base.convert(::Type{T}, x::T) where {T <: CatValue} = x
Base.convert(::Type{Union{T, Missing}}, x::T) where {T <: CatValue} = x # override the convert() below
Base.convert(::Type{S}, x::CatValue) where {S} = convert(S, get(x)) # fallback
if VERSION >= v"0.7.0-DEV.2797"
    function Base.show(io::IO, x::CatValue)
        if get(io, :typeinfo, Any) === typeof(x)
            print(io, repr(x))
        elseif isordered(pool(x))
            @printf(io, "%s %s (%i/%i)",
                    typeof(x), repr(x),
                    order(x), length(pool(x)))
        else
            @printf(io, "%s %s", typeof(x), repr(x))
        end
    end
else
    function Base.show(io::IO, x::CatValue)
        if get(io, :compact, false)
            print(io, repr(x))
        elseif isordered(pool(x))
            @printf(io, "%s %s (%i/%i)",
                    typeof(x), repr(x),
                    order(x), length(pool(x)))
        else
            @printf(io, "%s %s", typeof(x), repr(x))
        end
    end
end
Base.print(io::IO, x::CatValue) = print(io, get(x))
Base.repr(x::CatValue) = repr(get(x))
@inline function Base.:(==)(x::CatValue, y::CatValue)
    if pool(x) === pool(y)
        return level(x) == level(y)
    else
        return get(x) == get(y)
    end
end
Base.:(==)(::CatValue, ::Missing) = missing
Base.:(==)(::Missing, ::CatValue) = missing
Base.:(==)(x::CatValue, y::WeakRef) = get(x) == y
Base.:(==)(x::WeakRef, y::CatValue) = y == x
Base.:(==)(x::CatValue, y::AbstractString) = get(x) == y
Base.:(==)(x::AbstractString, y::CatValue) = y == x
Base.:(==)(x::CatValue, y::Any) = get(x) == y
Base.:(==)(x::Any, y::CatValue) = y == x
@inline function Base.isequal(x::CatValue, y::CatValue)
    if pool(x) === pool(y)
        return level(x) == level(y)
    else
        return isequal(get(x), get(y))
    end
end
Base.isequal(x::CatValue, y::Any) = isequal(get(x), y)
Base.isequal(x::Any, y::CatValue) = isequal(y, x)
Base.isequal(::CatValue, ::Missing) = false
Base.isequal(::Missing, ::CatValue) = false
Base.in(x::CatValue, y::AbstractRange{T}) where {T<:Integer} = get(x) in y
Base.hash(x::CatValue, h::UInt) = hash(get(x), h)
function Base.isless(x::CatValue, y::CatValue)
    if pool(x) !== pool(y)
        throw(ArgumentError("CategoricalValue objects with different pools cannot be tested for order"))
    else
        return order(x) < order(y)
    end
end
function Base.:<(x::CatValue, y::CatValue)
    if pool(x) !== pool(y)
        throw(ArgumentError("CategoricalValue objects with different pools cannot be tested for order"))
    elseif !isordered(pool(x)) # !isordered(pool(y)) is implied by pool(x) === pool(y)
        throw(ArgumentError("Unordered CategoricalValue objects cannot be tested for order using <. Use isless instead, or call the ordered! function on the parent array to change this"))
    else
        return order(x) < order(y)
    end
end
Base.string(x::CategoricalString) = get(x)
Base.eltype(x::CategoricalString) = Char
Base.length(x::CategoricalString) = length(get(x))
Compat.lastindex(x::CategoricalString) = lastindex(get(x))
Base.sizeof(x::CategoricalString) = sizeof(get(x))
Base.nextind(x::CategoricalString, i::Int) = nextind(get(x), i)
Base.prevind(x::CategoricalString, i::Int) = prevind(get(x), i)
Base.next(x::CategoricalString, i::Int) = next(get(x), i)
Base.getindex(x::CategoricalString, i::Int) = getindex(get(x), i)
Base.codeunit(x::CategoricalString, i::Integer) = codeunit(get(x), i)
Base.ascii(x::CategoricalString) = ascii(get(x))
Base.isvalid(x::CategoricalString) = isvalid(get(x))
Base.isvalid(x::CategoricalString, i::Integer) = isvalid(get(x), i)
Base.match(r::Regex, s::CategoricalString,
           idx::Integer=start(s), add_opts::UInt32=UInt32(0)) =
    match(r, get(s), idx, add_opts)
if VERSION > v"0.7.0-DEV.3526"
    Base.matchall(r::Regex, s::CategoricalString; overlap::Bool=false) =
        matchall(r, get(s); overlap=overlap)
else
    Base.matchall(r::Regex, s::CategoricalString; overlap::Bool=false) =
        matchall(r, get(s), overlap)
    Base.matchall(r::Regex, s::CategoricalString, overlap::Bool) =
        matchall(r, get(s), overlap)
end
Base.collect(x::CategoricalString) = collect(get(x))
Base.reverse(x::CategoricalString) = reverse(get(x))
Compat.ncodeunits(x::CategoricalString) = ncodeunits(get(x))
JSON.lower(x::CatValue) = get(x)
import Base: Array, convert, collect, copy, getindex, setindex!, similar, size,
             unique, vcat, in, summary, float, complex
import Compat: copyto!
_isordered(x::AbstractCategoricalArray) = isordered(x)
_isordered(x::Any) = false
function reftype(sz::Int)
    if sz <= typemax(UInt8)
        return UInt8
    elseif sz <= typemax(UInt16)
        return UInt16
    elseif sz <= typemax(UInt32)
        return UInt32
    else
        return UInt64
    end
end
function CategoricalArray end
function CategoricalVector end
function CategoricalMatrix end
CategoricalArray(::UndefInitializer, dims::Int...; ordered=false) =
    CategoricalArray{String}(undef, dims, ordered=ordered)
function CategoricalArray{T, N, R}(::UndefInitializer, dims::NTuple{N,Int};
                                   ordered=false) where {T, N, R}
    C = catvaluetype(T, R)
    V = leveltype(C)
    S = T >: Missing ? Union{V, Missing} : V
    CategoricalArray{S, N}(zeros(R, dims), CategoricalPool{V, R, C}(ordered))
end
CategoricalArray{T, N}(::UndefInitializer, dims::NTuple{N,Int}; ordered=false) where {T, N} =
    CategoricalArray{T, N, DefaultRefType}(undef, dims, ordered=ordered)
CategoricalArray{T}(::UndefInitializer, dims::NTuple{N,Int}; ordered=false) where {T, N} =
    CategoricalArray{T, N}(undef, dims, ordered=ordered)
CategoricalArray{T, 1}(::UndefInitializer, m::Int; ordered=false) where {T} =
    CategoricalArray{T, 1}(undef, (m,), ordered=ordered)
CategoricalArray{T, 2}(::UndefInitializer, m::Int, n::Int; ordered=false) where {T} =
    CategoricalArray{T, 2}(undef, (m, n), ordered=ordered)
CategoricalArray{T, 1, R}(::UndefInitializer, m::Int; ordered=false) where {T, R} =
    CategoricalArray{T, 1, R}(undef, (m,), ordered=ordered)
CategoricalArray{T, 2, R}(::UndefInitializer, m::Int, n::Int; ordered=false) where {T, R <: Integer} =
    CategoricalArray{T, 2, R}(undef, (m, n), ordered=ordered)
CategoricalArray{T, 3, R}(::UndefInitializer, m::Int, n::Int, o::Int; ordered=false) where {T, R} =
    CategoricalArray{T, 3, R}(undef, (m, n, o), ordered=ordered)
CategoricalArray{T}(::UndefInitializer, m::Int; ordered=false) where {T} =
    CategoricalArray{T}(undef, (m,), ordered=ordered)
CategoricalArray{T}(::UndefInitializer, m::Int, n::Int; ordered=false) where {T} =
    CategoricalArray{T}(undef, (m, n), ordered=ordered)
CategoricalArray{T}(::UndefInitializer, m::Int, n::Int, o::Int; ordered=false) where {T} =
    CategoricalArray{T}(undef, (m, n, o), ordered=ordered)
CategoricalVector(::UndefInitializer, m::Integer; ordered=false) =
    CategoricalArray(undef, m, ordered=ordered)
CategoricalVector{T}(::UndefInitializer, m::Int; ordered=false) where {T} =
    CategoricalArray{T}(undef, (m,), ordered=ordered)
CategoricalMatrix(::UndefInitializer, m::Int, n::Int; ordered=false) =
    CategoricalArray(undef, m, n, ordered=ordered)
CategoricalMatrix{T}(::UndefInitializer, m::Int, n::Int; ordered=false) where {T} =
    CategoricalArray{T}(undef, (m, n), ordered=ordered)
function CategoricalArray{T, N, R}(A::CategoricalArray{S, N, Q};
                                   ordered=_isordered(A)) where {S, T, N, Q, R}
    V = unwrap_catvaluetype(T)
    res = convert(CategoricalArray{V, N, R}, A)
    refs = res.refs === A.refs ? deepcopy(res.refs) : res.refs
    pool = res.pool === A.pool ? deepcopy(res.pool) : res.pool
    ordered!(CategoricalArray{V, N}(refs, pool), ordered)
end
function CategoricalArray{T, N, R}(A::AbstractArray; ordered=_isordered(A)) where {T, N, R}
    V = unwrap_catvaluetype(T)
    ordered!(convert(CategoricalArray{V, N, R}, A), ordered)
end
CategoricalArray{T, N}(A::AbstractArray{S, N}; ordered=_isordered(A)) where {S, T, N} =
    CategoricalArray{T, N, DefaultRefType}(A, ordered=ordered)
CategoricalArray{T}(A::AbstractArray{S, N}; ordered=_isordered(A)) where {S, T, N} =
    CategoricalArray{T, N}(A, ordered=ordered)
CategoricalArray(A::AbstractArray{T, N}; ordered=_isordered(A)) where {T, N} =
    CategoricalArray{T, N}(A, ordered=ordered)
CategoricalVector{T}(A::AbstractVector{S}; ordered=_isordered(A)) where {S, T} =
    CategoricalArray{T, 1}(A, ordered=ordered)
CategoricalVector(A::AbstractVector{T}; ordered=_isordered(A)) where {T} =
    CategoricalArray{T, 1}(A, ordered=ordered)
CategoricalMatrix{T}(A::AbstractMatrix{S}; ordered=_isordered(A)) where {S, T} =
    CategoricalArray{T, 2}(A, ordered=ordered)
CategoricalMatrix(A::AbstractMatrix{T}; ordered=_isordered(A)) where {T} =
    CategoricalArray{T, 2}(A, ordered=ordered)
CategoricalArray{T, N}(A::CategoricalArray{S, N, R};
                       ordered=_isordered(A)) where {S, T, N, R} =
    CategoricalArray{T, N, R}(A, ordered=ordered)
CategoricalArray{T}(A::CategoricalArray{S, N, R};
                    ordered=_isordered(A)) where {S, T, N, R} =
    CategoricalArray{T, N, R}(A, ordered=ordered)
CategoricalArray(A::CategoricalArray{T, N, R};
                 ordered=_isordered(A)) where {T, N, R} =
    CategoricalArray{T, N, R}(A, ordered=ordered)
CategoricalVector{T}(A::CategoricalArray{S, 1, R};
                     ordered=_isordered(A)) where {S, T, R} =
    CategoricalArray{T, 1, R}(A, ordered=ordered)
CategoricalVector(A::CategoricalArray{T, 1, R};
                  ordered=_isordered(A)) where {T, R} =
    CategoricalArray{T, 1, R}(A, ordered=ordered)
CategoricalMatrix{T}(A::CategoricalArray{S, 2, R};
                     ordered=_isordered(A)) where {S, T, R} =
    CategoricalArray{T, 2, R}(A, ordered=ordered)
CategoricalMatrix(A::CategoricalArray{T, 2, R};
                  ordered=_isordered(A)) where {T, R} =
    CategoricalArray{T, 2, R}(A, ordered=ordered)
convert(::Type{CategoricalArray{T, N}}, A::AbstractArray{S, N}) where {S, T, N} =
    convert(CategoricalArray{T, N, DefaultRefType}, A)
convert(::Type{CategoricalArray{T}}, A::AbstractArray{S, N}) where {S, T, N} =
    convert(CategoricalArray{T, N}, A)
convert(::Type{CategoricalArray}, A::AbstractArray{T, N}) where {T, N} =
    convert(CategoricalArray{T, N}, A)
convert(::Type{CategoricalVector{T}}, A::AbstractVector) where {T} =
    convert(CategoricalVector{T, DefaultRefType}, A)
convert(::Type{CategoricalVector}, A::AbstractVector{T}) where {T} =
    convert(CategoricalVector{T}, A)
convert(::Type{CategoricalVector{T}}, A::CategoricalVector{T}) where {T} = A
convert(::Type{CategoricalVector}, A::CategoricalVector) = A
convert(::Type{CategoricalMatrix{T}}, A::AbstractMatrix) where {T} =
    convert(CategoricalMatrix{T, DefaultRefType}, A)
convert(::Type{CategoricalMatrix}, A::AbstractMatrix{T}) where {T} =
    convert(CategoricalMatrix{T}, A)
convert(::Type{CategoricalMatrix{T}}, A::CategoricalMatrix{T}) where {T} = A
convert(::Type{CategoricalMatrix}, A::CategoricalMatrix) = A
function convert(::Type{CategoricalArray{T, N, R}}, A::AbstractArray{S, N}) where {S, T, N, R}
    res = CategoricalArray{T, N, R}(undef, size(A))
    copyto!(res, A)
    # if order is defined for level type, automatically apply it
    L = leveltype(res)
    if hasmethod(isless, Tuple{L, L})
        levels!(res.pool, sort(levels(res.pool)))
    end
    res
end
function convert(::Type{CategoricalArray{T, N, R}}, A::CategoricalArray{S, N}) where {S, T, N, R}
    if length(A.pool) > typemax(R)
        throw(LevelsException{T, R}(levels(A)[typemax(R)+1:end]))
    end
    if T >: Missing
        U = Missings.T(T)
    else
        U = T
        S >: Missing && any(iszero, A.refs) &&
            throw(MissingException("cannot convert CategoricalArray with missing values to a CategoricalArray{$T}"))
    end
    pool = convert(CategoricalPool{unwrap_catvaluetype(U), R}, A.pool)
    refs = convert(Array{R, N}, A.refs)
    CategoricalArray{unwrap_catvaluetype(T), N}(refs, pool)
end
convert(::Type{CategoricalArray{T, N}}, A::CategoricalArray{S, N, R}) where {S, T, N, R} =
    convert(CategoricalArray{T, N, R}, A)
convert(::Type{CategoricalArray{T}}, A::CategoricalArray{S, N, R}) where {S, T, N, R} =
    convert(CategoricalArray{T, N, R}, A)
convert(::Type{CategoricalArray}, A::CategoricalArray{T, N, R}) where {T, N, R} =
    convert(CategoricalArray{T, N, R}, A)
convert(::Type{CategoricalArray{T, N, R}}, A::CategoricalArray{T, N, R}) where {T, N, R<:Integer} = A
convert(::Type{CategoricalArray{T, N}}, A::CategoricalArray{T, N}) where {T, N} = A
convert(::Type{CategoricalArray{T}}, A::CategoricalArray{T}) where {T} = A
convert(::Type{CategoricalArray}, A::CategoricalArray) = A
function Base.:(==)(A::CategoricalArray{S}, B::CategoricalArray{T}) where {S, T}
    if size(A) != size(B)
        return false
    end
    anymissing = false
    if A.pool === B.pool
        @inbounds for (a, b) in zip(A.refs, B.refs)
            if a == 0 || b == 0
                (S >: Missing || T >: Missing) && (anymissing = true)
            elseif a != b
                return false
            end
        end
    else
        @inbounds for (a, b) in zip(A, B)
            eq = (a == b)
            if eq === false
                return false
            elseif S >: Missing || T >: Missing
                anymissing |= ismissing(eq)
            end
        end
    end
    return anymissing ? missing : true
end
function Base.isequal(A::CategoricalArray, B::CategoricalArray)
    if size(A) != size(B)
        return false
    end
    if A.pool === B.pool
        @inbounds for (a, b) in zip(A.refs, B.refs)
            if a != b
                return false
            end
        end
    else
        @inbounds for (a, b) in zip(A, B)
            if !isequal(a, b)
                return false
            end
        end
    end
    return true
end
size(A::CategoricalArray) = size(A.refs)
Base.IndexStyle(::Type{<:CategoricalArray}) = IndexLinear()
@inline function setindex!(A::CategoricalArray, v::Any, I::Real...)
    @boundscheck checkbounds(A, I...)
    @inbounds A.refs[I...] = get!(A.pool, v)
end
Base.fill!(A::CategoricalArray, v::Any) =
    (fill!(A.refs, get!(A.pool, convert(leveltype(A), v))); A)
function mergelevels(ordered, levels...)
    T = Base.promote_eltype(levels...)
    res = Vector{T}(undef, 0)
    nonempty_lv = Compat.findfirst(!isempty, levels)
    if nonempty_lv === nothing
        # no levels
        return res, ordered
    elseif all(l -> isempty(l) || l == levels[nonempty_lv], levels)
        # Fast path if all non-empty levels are equal
        append!(res, levels[nonempty_lv])
        return res, ordered
    end
    for l in levels
        levelsmap = indexin(l, res)
        i = length(res)+1
        for j = length(l):-1:1
            @static if VERSION >= v"0.7.0-DEV.3627"
                if levelsmap[j] === nothing
                    insert!(res, i, l[j])
                else
                    i = levelsmap[j]
                end
            else
                if levelsmap[j] == 0
                    insert!(res, i, l[j])
                else
                    i = levelsmap[j]
                end
            end
        end
    end
    # Check that result is ordered
    if ordered
        levelsmaps = [Compat.indexin(res, l) for l in levels]
        # Check that each original order is preserved
        for m in levelsmaps
            issorted(Iterators.filter(x -> x != nothing, m)) || return res, false
        end
        # Check that all order relations between pairs of subsequent elements
        # are defined in at least one set of original levels
        pairs = fill(false, length(res)-1)
        for m in levelsmaps
            @inbounds for i in eachindex(pairs)
                pairs[i] |= (m[i] != nothing) & (m[i+1] != nothing)
            end
            all(pairs) && return res, true
        end
    end
    res, false
end
copy(A::CategoricalArray) = deepcopy(A)
CatArrOrSub{T, N} = Union{CategoricalArray{T, N},
                          SubArray{<:Any, N, <:CategoricalArray{T}}} where {T, N}
function copyto!(dest::CatArrOrSub{T, N}, dstart::Integer,
                 src::CatArrOrSub{<:Any, N}, sstart::Integer,
                 n::Integer) where {T, N}
    n == 0 && return dest
    n < 0 && throw(ArgumentError(string("tried to copy n=", n, " elements, but n should be nonnegative")))
    destinds, srcinds = linearindices(dest), linearindices(src)
    (dstart ∈ destinds && dstart+n-1 ∈ destinds) || throw(BoundsError(dest, dstart:dstart+n-1))
    (sstart ∈ srcinds  && sstart+n-1 ∈ srcinds)  || throw(BoundsError(src,  sstart:sstart+n-1))
    drefs = refs(dest)
    srefs = refs(src)
    dpool = pool(dest)
    spool = pool(src)
    # try converting src to dest type to avoid partial copy corruption of dest
    # in the event that the src cannot be copied into dest
    slevs = convert(Vector{T}, levels(src))
    if eltype(src) >: Missing && !(eltype(dest) >: Missing) && !all(x -> x > 0, srefs)
        throw(MissingException("cannot copy array with missing values to an array with element type $T"))
    end
    newlevels, ordered = mergelevels(isordered(dest), levels(dest), slevs)
    # Orderedness cannot be preserved if the source was unordered and new levels
    # need to be added: new comparisons would only be based on the source's order
    # (this is consistent with what happens when adding a new level via setindex!)
    ordered &= isordered(src) | (length(newlevels) == length(levels(dest)))
    if ordered != isordered(dest)
        isa(dest, SubArray) && throw(ArgumentError("cannot set ordered=$ordered on dest SubArray as it would affect the parent. Found when trying to set levels to $newlevels."))
        ordered!(dest, ordered)
    end
    # Simple case: replace all values
    if !isa(dest, SubArray) && dstart == dstart == 1 && n == length(dest) == length(src)
        # Set index to reflect refs
        levels!(dpool, T[]) # Needed in case src and dest share some levels
        levels!(dpool, index(spool))
        # Set final levels in their visible order
        levels!(dpool, newlevels)
        copyto!(drefs, srefs)
    else # More work to do: preserve some values (and therefore index)
        levels!(dpool, newlevels)
        indexmap = indexin(index(spool), index(dpool))
        @inbounds for i = 0:(n-1)
            x = srefs[sstart+i]
            drefs[dstart+i] = x > 0 ? indexmap[x] : 0
        end
    end
    dest
end
copyto!(dest::CatArrOrSub, src::CatArrOrSub) =
    copyto!(dest, 1, src, 1, length(src))
copyto!(dest::CatArrOrSub, dstart::Integer, src::CatArrOrSub) =
    copyto!(dest, dstart, src, 1, length(src))
similar(A::CategoricalArray{S, M, R}, ::Type{T},
        dims::NTuple{N, Int}) where {T, N, S, M, R} =
    Array{T, N}(undef, dims)
similar(A::CategoricalArray{S, M, R}, ::Type{Missing},
        dims::NTuple{N, Int}) where {N, S, M, R} =
    Array{Missing, N}(missing, dims)
similar(A::CategoricalArray{S, M, Q}, ::Type{T},
        dims::NTuple{N, Int}) where {R, T<:CatValue{R}, N, S, M, Q} =
    CategoricalArray{T, N, R}(undef, dims)
similar(A::CategoricalArray{S, M, R}, ::Type{T},
        dims::NTuple{N, Int}) where {S, T<:CatValue, M, N, R} =
    CategoricalArray{T, N, R}(undef, dims)
similar(A::CategoricalArray{S, M, Q}, ::Type{T},
        dims::NTuple{N, Int}) where {R, T<:Union{CatValue{R}, Missing}, N, S, M, Q} =
    CategoricalArray{Union{T, Missing}, N, R}(undef, dims)
similar(A::CategoricalArray{S, M, R}, ::Type{T},
        dims::NTuple{N, Int}) where {S, T<:Union{CatValue, Missing}, M, N, R} =
    CategoricalArray{Union{T, Missing}, N, R}(undef, dims)
function compress(A::CategoricalArray{T, N}) where {T, N}
    R = reftype(length(index(A.pool)))
    convert(CategoricalArray{T, N, R}, A)
end
decompress(A::CategoricalArray{T, N}) where {T, N} =
    convert(CategoricalArray{T, N, DefaultRefType}, A)
function vcat(A::CategoricalArray...)
    ordered = any(isordered, A) && all(a->isordered(a) || isempty(levels(a)), A)
    newlevels, ordered = mergelevels(ordered, map(levels, A)...)
    refsvec = map(A) do a
        ii = indexin(index(a.pool), newlevels)
        [x==0 ? 0 : ii[x] for x in a.refs]
    end
    T = Base.promote_eltype(A...) >: Missing ?
        Union{eltype(newlevels), Missing} : eltype(newlevels)
    refs = DefaultRefType[refsvec...;]
    pool = CategoricalPool(newlevels, ordered)
    CategoricalArray{T, ndims(refs)}(refs, pool)
end
@inline function getindex(A::CategoricalArray{T}, I...) where {T}
    @boundscheck checkbounds(A, I...)
    # Let Array indexing code handle everything
    @inbounds r = A.refs[I...]
    if isa(r, Array)
        res = CategoricalArray{T, ndims(r)}(r, deepcopy(A.pool))
        return ordered!(res, isordered(A))
    else
        r > 0 || throw(UndefRefError())
        @inbounds res = A.pool[r]
        return res
    end
end
catvaluetype(::Type{T}) where {T <: CategoricalArray} = Missings.T(eltype(T))
catvaluetype(A::CategoricalArray) = catvaluetype(typeof(A))
leveltype(::Type{T}) where {T <: CategoricalArray} = leveltype(catvaluetype(T))
Missings.levels(A::CategoricalArray) = levels(A.pool)
function levels!(A::CategoricalArray{T}, newlevels::Vector; allow_missing=false) where {T}
    if !allunique(newlevels)
        throw(ArgumentError(string("duplicated levels found: ",
                                   join(unique(filter(x->sum(newlevels.==x)>1, newlevels)), ", "))))
    end
    # first pass to check whether, if some levels are removed, changes can be applied without error
    # TODO: save original levels and undo changes in case of error to skip this step
    # equivalent to issubset but faster due to JuliaLang/julia#24624
    if !isempty(setdiff(index(A.pool), newlevels))
        deleted = [!(l in newlevels) for l in index(A.pool)]
        @inbounds for (i, x) in enumerate(A.refs)
            if T >: Missing
                !allow_missing && x > 0 && deleted[x] &&
                    throw(ArgumentError("cannot remove level $(repr(index(A.pool)[x])) as it is used at position $i and allow_missing=false."))
            else
                deleted[x] &&
                    throw(ArgumentError("cannot remove level $(repr(index(A.pool)[x])) as it is used at position $i. " *
                                        "Change the array element type to Union{$T, Missing} using convert if you want to transform some levels to missing values."))
            end
        end
    end
    # actually apply changes
    oldindex = copy(index(A.pool))
    levels!(A.pool, newlevels)
    if index(A.pool) != oldindex
        levelsmap = similar(A.refs, length(oldindex)+1)
        # 0 maps to a missing value
        levelsmap[1] = 0
        levelsmap[2:end] .= coalesce.(indexin(oldindex, index(A.pool)), 0)
        @inbounds for (i, x) in enumerate(A.refs)
            A.refs[i] = levelsmap[x+1]
        end
    end
    A
end
function _unique(::Type{S},
                 refs::AbstractArray{T},
                 pool::CategoricalPool) where {S, T<:Integer}
    seen = fill(false, length(index(pool))+1)
    trackmissings = S >: Missing
    # If we don't track missings, short-circuit even if none has been seen
    seen[1] = !trackmissings
    batch = 0
    @inbounds for i in refs
        seen[i + 1] = true
        # Only do a costly short-circuit check periodically
        batch += 1
        if batch > 1000
            all(seen) && break
            batch = 0
        end
    end
    seenmissing = popfirst!(seen)
    res = convert(Vector{S}, index(pool)[seen][sortperm(pool.order[seen])])
    if trackmissings && seenmissing
        push!(res, missing)
    end
    res
end
unique(A::CategoricalArray{T}) where {T} = _unique(T, A.refs, A.pool)
droplevels!(A::CategoricalArray) = levels!(A, filter!(!ismissing, unique(A)))
isordered(A::CategoricalArray) = isordered(A.pool)
ordered!(A::CategoricalArray, ordered) = (ordered!(A.pool, ordered); return A)
function Base.resize!(A::CategoricalVector, n::Integer)
    n_orig = length(A)
    resize!(A.refs, n)
    if n > n_orig
        A.refs[n_orig+1:end] = 0
    end
    A
end
function Base.push!(A::CategoricalVector, item)
    r = get!(A.pool, item)
    push!(A.refs, r)
    A
end
function Base.append!(A::CategoricalVector, B::CategoricalArray)
    levels!(A, union(levels(A), levels(B)))
    len = length(A.refs)
    len2 = length(B.refs)
    resize!(A.refs, len + length(B.refs))
    for i = 1:len2
        A[len + i] = B[i]
    end
    return A
end
Base.empty!(A::CategoricalArray) = (empty!(A.refs); return A)
function Base.reshape(A::CategoricalArray{T, N}, dims::Dims) where {T, N}
    x = reshape(A.refs, dims)
    res = CategoricalArray{T, ndims(x)}(x, A.pool)
    ordered!(res, isordered(res))
end
function categorical end
categorical(A::AbstractArray; ordered=_isordered(A)) = CategoricalArray(A, ordered=ordered)
function categorical(A::AbstractArray{T, N}, compress; ordered=_isordered(A)) where {T, N}
    RefType = compress ? reftype(length(unique(A))) : DefaultRefType
    CategoricalArray{T, N, RefType}(A, ordered=ordered)
end
function categorical(A::CategoricalArray{T, N, R}, compress; ordered=_isordered(A)) where {T, N, R}
    RefType = compress ? reftype(length(levels(A))) : R
    CategoricalArray{T, N, RefType}(A, ordered=ordered)
end
function in(x::Any, y::CategoricalArray{T, N, R}) where {T, N, R}
    ref = get(y.pool, x, zero(R))
    ref != 0 ? ref in y.refs : false
end
function in(x::CategoricalValue, y::CategoricalArray{T, N, R}) where {T, N, R}
    if x.pool === y.pool
        return x.level in y.refs
    else
        ref = get(y.pool, index(x.pool)[x.level], zero(R))
        return ref != 0 ? ref in y.refs : false
    end
end
Array(A::CategoricalArray{T}) where {T} = Array{T}(A)
collect(A::CategoricalArray{T}) where {T} = Array{T}(A)
function float(A::CategoricalArray{T}) where T
    if !isconcretetype(T)
        error("`float` not defined on abstractly-typed arrays; please convert to a more specific type")
    end
    convert(AbstractArray{typeof(float(zero(T)))}, A)
end
function complex(A::CategoricalArray{T}) where T
    if !isconcretetype(T)
        error("`complex` not defined on abstractly-typed arrays; please convert to a more specific type")
    end
    convert(AbstractArray{typeof(complex(zero(T)))}, A)
end
summary(A::CategoricalArray{T, N, R}) where {T, N, R} =
    string(Base.dims2string(size(A)), " $CategoricalArray{$T,$N,$R}")
refs(A::CategoricalArray) = A.refs
pool(A::CategoricalArray) = A.pool
import Base: getindex, setindex!, push!, similar, in, collect
@inline function getindex(A::CategoricalArray{T}, I...) where {T>:Missing}
    @boundscheck checkbounds(A, I...)
    # Let Array indexing code handle everything
    @inbounds r = A.refs[I...]
    if isa(r, Array)
        ret = CategoricalArray{T, ndims(r)}(r, deepcopy(A.pool))
        return ordered!(ret, isordered(A))
    else
        if r > 0
            @inbounds return A.pool[r]
        else
            return missing
        end
    end
end
@inline function setindex!(A::CategoricalArray{>:Missing}, v::Missing, I::Real...)
    @boundscheck checkbounds(A, I...)
    @inbounds A.refs[I...] = 0
end
@inline function push!(A::CategoricalVector{>:Missing}, v::Missing)
    push!(A.refs, 0)
    A
end
Base.fill!(A::CategoricalArray{>:Missing}, ::Missing) = (fill!(A.refs, 0); A)
in(x::Missing, y::CategoricalArray) = false
in(x::Missing, y::CategoricalArray{>:Missing}) = !all(v -> v > 0, y.refs)
function Missings.replace(a::CategoricalArray{S, N, R, V, C}, replacement::V) where {S, N, R, V, C}
    pool = deepcopy(a.pool)
    v = C(get!(pool, replacement), pool)
    Missings.replace(a, v)
end
function collect(r::Missings.EachReplaceMissing{<:CategoricalArray{S, N, R, C}}) where {S, N, R, C}
    CategoricalArray{C,N}(R[v.level for v in r], r.replacement.pool)
end
Missings.levels(sa::SubArray{T,N,P}) where {T,N,P<:CategoricalArray} = levels(parent(sa))
isordered(sa::SubArray{T,N,P}) where {T,N,P<:CategoricalArray} = isordered(parent(sa))
levels!(sa::SubArray{T,N,P}, newlevels::Vector) where {T,N,P<:CategoricalArray} =
    levels!(parent(sa), levels)
if VERSION ≥ v"0.7.0-DEV.3020"
    function unique(sa::SubArray{T,N,P}) where {T,N,P<:CategoricalArray}
        A = parent(sa)
        refs = view(A.refs, sa.indices...)
        S = eltype(P) >: Missing ? Union{eltype(index(A.pool)), Missing} : eltype(index(A.pool))
        _unique(S, refs, A.pool)
    end
    refs(A::SubArray{<:Any, <:Any, <:CategoricalArray}) = view(A.parent.refs, A.indices...)
else
    function unique(sa::SubArray{T,N,P}) where {T,N,P<:CategoricalArray}
        A = parent(sa)
        refs = view(A.refs, sa.indexes...)
        S = eltype(P) >: Missing ? Union{eltype(index(A.pool)), Missing} : eltype(index(A.pool))
        _unique(S, refs, A.pool)
    end
    refs(A::SubArray{<:Any, <:Any, <:CategoricalArray}) = view(A.parent.refs, A.indexes...)
end
pool(A::SubArray{<:Any, <:Any, <:CategoricalArray}) = A.parent.pool
function fill_refs!(refs::AbstractArray, X::AbstractArray,
                    breaks::AbstractVector, extend::Bool, allow_missing::Bool)
    n = length(breaks)
    lower = first(breaks)
    upper = last(breaks)
    @inbounds for i in eachindex(X)
        x = X[i]
        if extend && x == upper
            refs[i] = n-1
        elseif !extend && !(lower <= x < upper)
            throw(ArgumentError("value $x (at index $i) does not fall inside the breaks: adapt them manually, or pass extend=true"))
        else
            refs[i] = searchsortedlast(breaks, x)
        end
    end
end
function fill_refs!(refs::AbstractArray, X::AbstractArray{>: Missing},
                    breaks::AbstractVector, extend::Bool, allow_missing::Bool)
    n = length(breaks)
    lower = first(breaks)
    upper = last(breaks)
    @inbounds for i in eachindex(X)
        ismissing(X[i]) && continue
        x = X[i]
        if extend && x == upper
            refs[i] = n-1
        elseif !extend && !(lower <= x < upper)
            allow_missing || throw(ArgumentError("value $x (at index $i) does not fall inside the breaks: adapt them manually, or pass extend=true or allow_missing=true"))
            refs[i] = 0
        else
            refs[i] = searchsortedlast(breaks, x)
        end
    end
end
function cut(x::AbstractArray{T, N}, breaks::AbstractVector;
             extend::Bool=false, labels::AbstractVector{U}=String[],
             allow_missing::Bool=false) where {T, N, U<:AbstractString}
    if !issorted(breaks)
        breaks = sort(breaks)
    end
    if extend
        min_x, max_x = extrema(x)
        if !ismissing(min_x) && breaks[1] > min_x
            pushfirst!(breaks, min_x)
        end
        if !ismissing(max_x) && breaks[end] < max_x
            push!(breaks, max_x)
        end
    end
    refs = Array{DefaultRefType, N}(undef, size(x))
    try
        fill_refs!(refs, x, breaks, extend, allow_missing)
    catch err
        # So that the error appears to come from cut() itself,
        # since it refers to its keyword arguments
        if isa(err, ArgumentError)
            throw(err)
        else
            rethrow(err)
        end
    end
    n = length(breaks)
    if isempty(labels)
        from = map(x -> sprint(showcompact, x), breaks[1:n-1])
        to = map(x -> sprint(showcompact, x), breaks[2:n])
        levs = Vector{String}(undef, n-1)
        for i in 1:n-2
            levs[i] = string("[", from[i], ", ", to[i], ")")
        end
        if extend
            levs[end] = string("[", from[end], ", ", to[end], "]")
        else
            levs[end] = string("[", from[end], ", ", to[end], ")")
        end
    else
        length(labels) == n-1 || throw(ArgumentError("labels must be of length $(n-1), but got length $(length(labels))"))
        # Levels must have element type String for type stability of the result
        levs::Vector{String} = copy(labels)
    end
    pool = CategoricalPool(levs, true)
    S = T >: Missing ? Union{String, Missing} : String
    CategoricalArray{S, N}(refs, pool)
end
cut(x::AbstractArray, ngroups::Integer;
    labels::AbstractVector{U}=String[]) where {U<:AbstractString} =
    cut(x, quantile(x, (1:ngroups-1)/ngroups); extend=true, labels=labels)
const ≅ = isequal
function recode! end
recode!(dest::AbstractArray, src::AbstractArray, pairs::Pair...) =
    recode!(dest, src, nothing, pairs...)
function recode!(dest::AbstractArray{T}, src::AbstractArray, default::Any, pairs::Pair...) where {T}
    if length(dest) != length(src)
        throw(DimensionMismatch("dest and src must be of the same length (got $(length(dest)) and $(length(src)))"))
    end
    @inbounds for i in eachindex(dest, src)
        x = src[i]
        for j in 1:length(pairs)
            p = pairs[j]
            if ((isa(p.first, Union{AbstractArray, Tuple}) && any(x ≅ y for y in p.first)) ||
                x ≅ p.first)
                dest[i] = p.second
                @goto nextitem
            end
        end
        # Value not in any of the pairs
        if ismissing(x)
            eltype(dest) >: Missing ||
                throw(MissingException("missing value found, but dest does not support them: " *
                                       "recode them to a supported value"))
            dest[i] = missing
        elseif default isa Nothing
            try
                dest[i] = x
            catch err
                isa(err, MethodError) || rethrow(err)
                throw(ArgumentError("cannot `convert` value $(repr(x)) (of type $(typeof(x))) to type of recoded levels ($T). " *
                                    "This will happen with recode() when not all original levels are recoded " *
                                    "(i.e. some are preserved) and their type is incompatible with that of recoded levels."))
            end
        else
            dest[i] = default
        end
        @label nextitem
    end
    dest
end
function recode!(dest::CategoricalArray{T}, src::AbstractArray, default::Any, pairs::Pair...) where {T}
    if length(dest) != length(src)
        throw(DimensionMismatch("dest and src must be of the same length (got $(length(dest)) and $(length(src)))"))
    end
    vals = T[p.second for p in pairs]
    default !== nothing && push!(vals, default)
    levels!(dest.pool, filter!(!ismissing, unique(vals)))
    # In the absence of duplicated recoded values, we do not need to lookup the reference
    # for each pair in the loop, which is more efficient (with loop unswitching)
    dupvals = length(vals) != length(levels(dest.pool))
    drefs = dest.refs
    pairmap = [ismissing(v) ? 0 : get(dest.pool, v) for v in vals]
    defaultref = default === nothing || ismissing(default) ? 0 : get(dest.pool, default)
    @inbounds for i in eachindex(drefs, src)
        x = src[i]
        for j in 1:length(pairs)
            p = pairs[j]
            if ((isa(p.first, Union{AbstractArray, Tuple}) && any(x ≅ y for y in p.first)) ||
                x ≅ p.first)
                drefs[i] = dupvals ? pairmap[j] : j
                @goto nextitem
            end
        end
        # Value not in any of the pairs
        if ismissing(x)
            eltype(dest) >: Missing ||
                throw(MissingException("missing value found, but dest does not support them: " *
                                       "recode them to a supported value"))
            drefs[i] = 0
        elseif default === nothing
            try
                dest[i] = x # Need a dictionary lookup, and potentially adding a new level
            catch err
                isa(err, MethodError) || rethrow(err)
                throw(ArgumentError("cannot `convert` value $(repr(x)) (of type $(typeof(x))) to type of recoded levels ($T). " *
                                    "This will happen with recode() when not all original levels are recoded "*
                                    "(i.e. some are preserved) and their type is incompatible with that of recoded levels."))
            end
        else
            drefs[i] = defaultref
        end
        @label nextitem
    end
    # Put existing levels first, and sort them if possible
    # for consistency with CategoricalArray
    oldlevels = setdiff(levels(dest), vals)
    filter!(!ismissing, oldlevels)
    if hasmethod(isless, (eltype(oldlevels), eltype(oldlevels)))
        sort!(oldlevels)
    end
    levels!(dest, union(oldlevels, levels(dest)))
    dest
end
function recode!(dest::CategoricalArray{T}, src::CategoricalArray, default::Any, pairs::Pair...) where {T}
    if length(dest) != length(src)
        throw(DimensionMismatch("dest and src must be of the same length (got $(length(dest)) and $(length(src)))"))
    end
    vals = T[p.second for p in pairs]
    if default === nothing
        srclevels = levels(src)
        # Remove recoded levels as they won't appear in result
        firsts = (p.first for p in pairs)
        keptlevels = Vector{T}(undef, 0)
        sizehint!(keptlevels, length(srclevels))
        for l in srclevels
            if !(any(x -> x ≅ l, firsts) ||
                 any(f -> isa(f, Union{AbstractArray, Tuple}) && any(l ≅ y for y in f), firsts))
                try
                    push!(keptlevels, l)
                catch err
                    isa(err, MethodError) || rethrow(err)
                    throw(ArgumentError("cannot `convert` value $(repr(l)) (of type $(typeof(l))) to type of recoded levels ($T). " *
                                        "This will happen with recode() when not all original levels are recoded " *
                                        "(i.e. some are preserved) and their type is incompatible with that of recoded levels."))
                end
            end
        end
        levs, ordered = mergelevels(isordered(src), keptlevels, filter!(!ismissing, unique(vals)))
    else
        push!(vals, default)
        levs = filter!(!ismissing, unique(vals))
        # The order of default cannot be determined
        ordered = false
    end
    srcindex = src.pool === dest.pool ? copy(index(src.pool)) : index(src.pool)
    levels!(dest.pool, levs)
    drefs = dest.refs
    srefs = src.refs
    origmap = [get(dest.pool, v, 0) for v in srcindex]
    indexmap = Vector{DefaultRefType}(undef, length(srcindex)+1)
    # For missing values (0 if no missing in pairs' keys)
    indexmap[1] = 0
    for p in pairs
        if ((isa(p.first, Union{AbstractArray, Tuple}) && any(ismissing, p.first)) ||
            ismissing(p.first))
            indexmap[1] = get(dest.pool, p.second)
            break
        end
    end
    pairmap = [ismissing(p.second) ? 0 : get(dest.pool, p.second) for p in pairs]
    # Preserving ordered property only makes sense if new order is consistent with previous one
    ordered && (ordered = issorted(pairmap))
    ordered!(dest, ordered)
    defaultref = default === nothing || ismissing(default) ? 0 : get(dest.pool, default)
    @inbounds for (i, l) in enumerate(srcindex)
        for j in 1:length(pairs)
            p = pairs[j]
            if ((isa(p.first, Union{AbstractArray, Tuple}) && any(l ≅ y for y in p.first)) ||
                l ≅ p.first)
                indexmap[i+1] = pairmap[j]
                @goto nextitem
            end
        end
        # Value not in any of the pairs
        if default === nothing
            indexmap[i+1] = origmap[i]
        else
            indexmap[i+1] = defaultref
        end
        @label nextitem
    end
    @inbounds for i in eachindex(drefs)
        v = indexmap[srefs[i]+1]
        if !(eltype(dest) >: Missing)
            v > 0 || throw(MissingException("missing value found, but dest does not support them: " *
                                            "recode them to a supported value"))
        end
        drefs[i] = v
    end
    dest
end
recode!(a::AbstractArray, default::Any, pairs::Pair...) = recode!(a, a, default, pairs...)
recode!(a::AbstractArray, pairs::Pair...) = recode!(a, a, nothing, pairs...)
promote_valuetype(x::Pair{K, V}) where {K, V} = V
promote_valuetype(x::Pair{K, V}, y::Pair...) where {K, V} = promote_type(V, promote_valuetype(y...))
keytype_hasmissing(x::Pair{K}) where {K} = K === Missing
keytype_hasmissing(x::Pair{K}, y::Pair...) where {K} = K === Missing || keytype_hasmissing(y...)
function recode end
recode(a::AbstractArray, pairs::Pair...) = recode(a, nothing, pairs...)
function recode(a::AbstractArray, default::Any, pairs::Pair...)
    V = promote_valuetype(pairs...)
    # T cannot take into account eltype(src), since we can't know
    # whether it matters at compile time (all levels recoded or not)
    # and using a wider type than necessary would be annoying
    T = default isa Nothing ? V : promote_type(typeof(default), V)
    # Exception 1: if T === Missing and default not missing,
    # assume the caller wants to recode only some values to missing,
    # but accept original values
    if T === Missing && !isa(default, Missing)
        dest = Array{Union{eltype(a), Missing}}(size(a))
    # Exception 2: if original array accepted missing values and missing does not appear
    # in one of the pairs' LHS, result must accept missing values
    elseif T >: Missing || default isa Missing || (eltype(a) >: Missing && !keytype_hasmissing(pairs...))
        dest = Array{Union{T, Missing}}(undef, size(a))
    else
        dest = Array{Missings.T(T)}(undef, size(a))
    end
    recode!(dest, a, default, pairs...)
end
function recode(a::CategoricalArray{S, N, R}, default::Any, pairs::Pair...) where {S, N, R}
    V = promote_valuetype(pairs...)
    # T cannot take into account eltype(src), since we can't know
    # whether it matters at compile time (all levels recoded or not)
    # and using a wider type than necessary would be annoying
    T = default isa Nothing ? V : promote_type(typeof(default), V)
    # Exception 1: if T === Missing and default not missing,
    # assume the caller wants to recode only some values to missing,
    # but accept original values
    if T === Missing && !isa(default, Missing)
        dest = CategoricalArray{Union{S, Missing}, N, R}(undef, size(a))
    # Exception 2: if original array accepted missing values and missing does not appear
    # in one of the pairs' LHS, result must accept missing values
    elseif T >: Missing || default isa Missing || (eltype(a) >: Missing && !keytype_hasmissing(pairs...))
        dest = CategoricalArray{Union{T, Missing}, N, R}(undef, size(a))    else
        dest = CategoricalArray{Missings.T(T), N, R}(undef, size(a))
    end
    recode!(dest, a, default, pairs...)
end
@deprecate ordered isordered
@deprecate compact compress
@deprecate uncompact decompress
@deprecate CategoricalArray(::Type{T}, dims::NTuple{N,Int}; ordered=false) where {T, N} CategoricalArray{T}(dims, ordered=ordered)
@deprecate CategoricalArray(::Type{T}, dims::Int...; ordered=false) where {T} CategoricalArray{T}(dims, ordered=ordered)
@deprecate CategoricalVector(::Type{T}, m::Integer; ordered=false) where {T} CategoricalVector{T}(m, ordered=ordered)
@deprecate CategoricalMatrix(::Type{T}, m::Int, n::Int; ordered=false) where {T} CategoricalMatrix{T}(m, n, ordered=ordered)
if VERSION < v"0.7.0-DEV.3017"
    Base.convert(::Type{Nullable{S}}, x::CategoricalValue{Nullable}) where {S} =
        convert(Nullable{S}, get(x))
    Base.convert(::Type{Nullable}, x::CategoricalValue{S}) where {S} = convert(Nullable{S}, x)
    Base.convert(::Type{Nullable{CategoricalValue{Nullable{T}}}},
                 x::CategoricalValue{Nullable{T}}) where {T} =
        Nullable(x)
end
if VERSION < v"0.7.0-DEV.2581"
    CategoricalArray(dims::Int...; ordered=false) =
        CategoricalArray{String}(dims, ordered=ordered)
    function CategoricalArray{T, N, R}(dims::NTuple{N,Int};
                                    ordered=false) where {T, N, R}
        C = catvaluetype(T, R)
        V = leveltype(C)
        S = T >: Missing ? Union{V, Missing} : V
        CategoricalArray{S, N}(zeros(R, dims), CategoricalPool{V, R, C}(ordered))
    end
    CategoricalArray{T, N}(dims::NTuple{N,Int}; ordered=false) where {T, N} =
        CategoricalArray{T, N, DefaultRefType}(dims, ordered=ordered)
    CategoricalArray{T}(dims::NTuple{N,Int}; ordered=false) where {T, N} =
        CategoricalArray{T, N}(dims, ordered=ordered)
    CategoricalArray{T, 1}(m::Int; ordered=false) where {T} =
        CategoricalArray{T, 1}((m,), ordered=ordered)
    CategoricalArray{T, 2}(m::Int, n::Int; ordered=false) where {T} =
        CategoricalArray{T, 2}((m, n), ordered=ordered)
    CategoricalArray{T, 1, R}(m::Int; ordered=false) where {T, R} =
        CategoricalArray{T, 1, R}((m,), ordered=ordered)
    # R <: Integer is required to prevent default constructor from being called instead
    CategoricalArray{T, 2, R}(m::Int, n::Int; ordered=false) where {T, R <: Integer} =
        CategoricalArray{T, 2, R}((m, n), ordered=ordered)
    CategoricalArray{T, 3, R}(m::Int, n::Int, o::Int; ordered=false) where {T, R} =
        CategoricalArray{T, 3, R}((m, n, o), ordered=ordered)
    CategoricalArray{T}(m::Int; ordered=false) where {T} =
        CategoricalArray{T}((m,), ordered=ordered)
    CategoricalArray{T}(m::Int, n::Int; ordered=false) where {T} =
        CategoricalArray{T}((m, n), ordered=ordered)
    CategoricalArray{T}(m::Int, n::Int, o::Int; ordered=false) where {T} =
        CategoricalArray{T}((m, n, o), ordered=ordered)
    CategoricalVector(m::Integer; ordered=false) = CategoricalArray(m, ordered=ordered)
    CategoricalVector{T}(m::Int; ordered=false) where {T} =
        CategoricalArray{T}((m,), ordered=ordered)
    CategoricalMatrix(m::Int, n::Int; ordered=false) = CategoricalArray(m, n, ordered=ordered)
    CategoricalMatrix{T}(m::Int, n::Int; ordered=false) where {T} =
        CategoricalArray{T}((m, n), ordered=ordered)
else
    @deprecate CategoricalArray(dims::Int...; ordered=false) CategoricalArray(undef, dims...; ordered=ordered)
    @deprecate CategoricalArray{T, N, R}(dims::NTuple{N,Int}; ordered=false) where {T, N, R} CategoricalArray{T, N, R}(undef, dims; ordered=ordered)
    @deprecate CategoricalArray{T, N}(dims::NTuple{N,Int}; ordered=false) where {T, N} CategoricalArray{T, N}(undef, dims; ordered=ordered)
    @deprecate CategoricalArray{T}(dims::NTuple{N,Int}; ordered=false) where {T, N} CategoricalArray{T}(undef, dims; ordered=ordered)
    @deprecate CategoricalArray{T, 1}(m::Int; ordered=false) where {T} CategoricalArray{T, 1}(undef, m; ordered=ordered)
    @deprecate CategoricalArray{T, 2}(m::Int, n::Int; ordered=false) where {T} CategoricalArray{T, 2}(undef, m, n; ordered=ordered)
    @deprecate CategoricalArray{T, 1, R}(m::Int; ordered=false) where {T, R} CategoricalArray{T, 1, R}(undef, m; ordered=ordered)
    # R <: Integer is required to prevent default constructor from being called instead
    @deprecate CategoricalArray{T, 2, R}(m::Int, n::Int; ordered=false) where {T, R <: Integer} CategoricalArray{T, 2, R}(undef, m, n; ordered=ordered)
    @deprecate CategoricalArray{T, 3, R}(m::Int, n::Int, o::Int; ordered=false) where {T, R} CategoricalArray{T, 3, R}(undef, m, n, o; ordered=ordered)
    @deprecate CategoricalArray{T}(m::Int; ordered=false) where {T} CategoricalArray{T}(undef, m; ordered=ordered)
    @deprecate CategoricalArray{T}(m::Int, n::Int; ordered=false) where {T} CategoricalArray{T}(undef, m, n; ordered=ordered)
    @deprecate CategoricalArray{T}(m::Int, n::Int, o::Int; ordered=false) where {T} CategoricalArray{T}(undef, m, n, o; ordered=ordered)
    @deprecate CategoricalVector(m::Integer; ordered=false) CategoricalVector(undef, m; ordered=ordered)
    @deprecate CategoricalVector{T}(m::Int; ordered=false) where {T} CategoricalVector{T}(undef, m; ordered=ordered)
    @deprecate CategoricalMatrix(m::Int, n::Int; ordered=false) CategoricalMatrix(undef, m, n; ordered=ordered)
    @deprecate CategoricalMatrix{T}(m::Int, n::Int; ordered=false) where {T} CategoricalMatrix{T}(undef, m::Int, n::Int; ordered=ordered)
end
end