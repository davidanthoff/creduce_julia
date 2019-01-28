""" """ struct DataFrameRow{D<:AbstractDataFrame,S<:AbstractIndex}
    df::D
    colindex::S
    row::Int
    @inline DataFrameRow(df::D, colindex::S, row::Union{Signed, Unsigned}) where {D<:AbstractDataFrame,S<:AbstractIndex} =
        new{D,S}(df, colindex, row)
end
Base.@propagate_inbounds function DataFrameRow(df::DataFrame, row::Integer, cols)
    @boundscheck if !checkindex(Bool, axes(df, 1), row)
        throw(BoundsError("attempt to access a data frame with $(nrow(df)) " *
                          "rows at index $row"))
    end
    DataFrameRow(df, SubIndex(index(df), cols), row)
end
Base.@propagate_inbounds function DataFrameRow(sdf::SubDataFrame, row::Integer, cols)
    @boundscheck if !checkindex(Bool, axes(sdf, 1), row)
        throw(BoundsError("attempt to access a data frame with $(nrow(sdf)) " *
                          "rows at index $row"))
    end
    colindex = SubIndex(index(parent(sdf)), parentcols(index(sdf), cols))
    @inbounds DataFrameRow(parent(sdf), colindex, rows(sdf)[row])
end
row(r::DataFrameRow) = getfield(r, :row)
Base.parent(r::DataFrameRow) = getfield(r, :df)
Base.parentindices(r::DataFrameRow) = (row(r), parentcols(index(r)))
Base.@propagate_inbounds Base.view(adf::AbstractDataFrame, rowind::Integer, ::Colon) =
    DataFrameRow(adf, rowind, :)
Base.@propagate_inbounds Base.view(adf::AbstractDataFrame, rowind::Integer, colinds::AbstractVector) =
    DataFrameRow(adf, rowind, colinds)
Base.@propagate_inbounds Base.getindex(df::AbstractDataFrame, rowind::Integer, colinds::AbstractVector) =
    DataFrameRow(df, rowind, colinds)
Base.@propagate_inbounds Base.getindex(df::AbstractDataFrame, rowind::Integer, ::Colon) =
    DataFrameRow(df, rowind, :)
Base.@propagate_inbounds Base.getindex(r::DataFrameRow, idx::ColumnIndex) =
    parent(r)[row(r), parentcols(index(r), idx)]
Base.@propagate_inbounds Base.getindex(r::DataFrameRow, idxs::AbstractVector) =
    DataFrameRow(parent(r), row(r), parentcols(index(r), idxs))
Base.@propagate_inbounds Base.getindex(r::DataFrameRow, ::Colon) = r
Base.@propagate_inbounds Base.setindex!(r::DataFrameRow, value::Any, idx) =
    setindex!(parent(r), value, row(r), parentcols(index(r), idx))
index(r::DataFrameRow) = getfield(r, :colindex)
Base.names(r::DataFrameRow) = _names(parent(r))[parentcols(index(r), :)]
_names(r::DataFrameRow) = view(_names(parent(r)), parentcols(index(r), :))
Base.haskey(r::DataFrameRow, key::Bool) =
    throw(ArgumentError("invalid key: $key of type Bool"))
Base.haskey(r::DataFrameRow, key::Integer) = 1 ≤ key ≤ size(r, 1)
function Base.haskey(r::DataFrameRow, key::Symbol)
    haskey(parent(r), key) || return false
    index(r) isa Index && return true
    pos = index(parent(r))[key]
    remap = index(r).remap
    length(remap) == 0 && lazyremap!(index(r))
    checkbounds(Bool, remap, pos) || return false
    remap[pos] > 0
end
Base.getproperty(r::DataFrameRow, idx::Symbol) = getindex(r, idx)
Base.setproperty!(r::DataFrameRow, idx::Symbol, x::Any) = setindex!(r, x, idx)
Base.propertynames(r::DataFrameRow, private::Bool=false) = names(r)
Base.view(r::DataFrameRow, col::ColumnIndex) =
    view(parent(r)[parentcols(index(r), col)], row(r))
Base.view(r::DataFrameRow, cols::AbstractVector) =
    DataFrameRow(parent(r), row(r), parentcols(index(r), cols))
Base.view(r::DataFrameRow, ::Colon) = r
Base.size(r::DataFrameRow) = (length(index(r)),)
Base.size(r::DataFrameRow, i) = size(r)[i]
Base.length(r::DataFrameRow) = size(r, 1)
Base.ndims(r::DataFrameRow) = 1
Base.ndims(::Type{<:DataFrameRow}) = 1
Base.lastindex(r::DataFrameRow) = length(r)
Base.iterate(r::DataFrameRow) = iterate(r, 1)
function Base.iterate(r::DataFrameRow, st)
    st > length(r) && return nothing
    return (r[st], st + 1)
end
Base.IteratorEltype(::DataFrameRow) = Base.EltypeUnknown()
function Base.convert(::Type{Vector}, dfr::DataFrameRow)
    T = reduce(promote_type, eltypes(parent(dfr)))
    convert(Vector{T}, dfr)
end
Base.convert(::Type{Vector{T}}, dfr::DataFrameRow) where T =
    T[dfr[i] for i in 1:length(dfr)]
Base.Vector(dfr::DataFrameRow) = convert(Vector, dfr)
Base.Vector{T}(dfr::DataFrameRow) where T = convert(Vector{T}, dfr)
Base.keys(r::DataFrameRow) = names(r)
Base.values(r::DataFrameRow) = ntuple(col -> parent(r)[row(r), parentcols(index(r), col)], length(r))
""" """ Base.copy(r::DataFrameRow) = NamedTuple{Tuple(keys(r))}(values(r))
Base.@propagate_inbounds hash_colel(v::AbstractArray, i, h::UInt = zero(UInt)) = hash(v[i], h)
Base.@propagate_inbounds function hash_colel(v::AbstractCategoricalArray, i, h::UInt = zero(UInt))
    ref = v.refs[i]
    if eltype(v) >: Missing && ref == 0
        hash(missing, h)
    else
        hash(CategoricalArrays.index(v.pool)[ref], h)
    end
end
rowhash(cols::Tuple{AbstractVector}, r::Int, h::UInt = zero(UInt))::UInt =
    hash_colel(cols[1], r, h)
function rowhash(cols::Tuple{Vararg{AbstractVector}}, r::Int, h::UInt = zero(UInt))::UInt
    h = hash_colel(cols[1], r, h)
    rowhash(Base.tail(cols), r, h)
end
Base.hash(r::DataFrameRow, h::UInt = zero(UInt)) =
    rowhash(ntuple(col -> parent(r)[parentcols(index(r), col)], length(r)), row(r), h)
function Base.:(==)(r1::DataFrameRow, r2::DataFrameRow)
    if parent(r1) === parent(r2)
        parentcols(index(r1)) == parentcols(index(r2)) || return false
        row(r1) == row(r2) && return true
    else
        _names(r1) == _names(r2) || return false
    end
    all(((a, b),) -> a == b, zip(r1, r2))
end
function Base.isequal(r1::DataFrameRow, r2::DataFrameRow)
    if parent(r1) === parent(r2)
        parentcols(index(r1)) == parentcols(index(r2)) || return false
        row(r1) == row(r2) && return true
    else
        _names(r1) == _names(r2) || return false
    end
    all(((a, b),) -> isequal(a, b), zip(r1, r2))
end
function Base.isless(r1::DataFrameRow, r2::DataFrameRow)
    length(r1) == length(r2) ||
        throw(ArgumentError("compared DataFrameRows must have the same number " *
                            "of columns (got $(length(r1)) and $(length(r2)))"))
    for (a,b) in zip(r1, r2)
        isequal(a, b) || return isless(a, b)
    end
    return false
end
function DataFrame(dfr::DataFrameRow)
    row, cols = parentindices(dfr)
    parent(dfr)[row:row, cols]
end
@noinline pushhelper!(x, r) = push!(x, x[r])
function Base.push!(df::DataFrame, dfr::DataFrameRow)
    if parent(dfr) === df && index(dfr) isa Index
        r = row(dfr)
        for col in _columns(df)
            pushhelper!(col, r)
        end
    else
        size(df, 2) == length(dfr) || throw(ArgumentError("Inconsistent number of columns"))
        i = 1
        for nm in _names(df)
            try
                push!(df[i], dfr[nm])
            catch
                for j in 1:(i - 1)
                    pop!(df[j])
                end
                msg = "Error adding value to column :$nm."
                throw(ArgumentError(msg))
            end
            i += 1
        end
    end
    df
end
