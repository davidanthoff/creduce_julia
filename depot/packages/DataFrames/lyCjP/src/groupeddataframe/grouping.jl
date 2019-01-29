""" """ struct GroupedDataFrame{T<:AbstractDataFrame}
    parent::T
    cols::Vector{Int}    # columns used for grouping
    groups::Vector{Int}  # group indices for each row
    idx::Vector{Int}     # indexing vector when grouped by the given columns
    starts::Vector{Int}  # starts of groups
    ends::Vector{Int}    # ends of groups
end
""" """ Base.parent(gd::GroupedDataFrame) = getfield(gd, :parent)
""" """ function groupby(df::AbstractDataFrame, cols::AbstractVector;
                 sort::Bool = false, skipmissing::Bool = false)
    intcols = index(df)[cols]
    sdf = df[intcols]
    df_groups = group_rows(sdf, false, sort, skipmissing)
    GroupedDataFrame(df, intcols, df_groups.groups, df_groups.rperm,
                     df_groups.starts, df_groups.stops)
end
groupby(d::AbstractDataFrame, cols;
        sort::Bool = false, skipmissing::Bool = false) =
    groupby(d, [cols], sort = sort, skipmissing = skipmissing)
function Base.iterate(gd::GroupedDataFrame, i=1)
    if i > length(gd.starts)
        nothing
    else
        (view(gd.parent, gd.idx[gd.starts[i]:gd.ends[i]], :), i+1)
    end
end
Base.length(gd::GroupedDataFrame) = length(gd.starts)
Compat.lastindex(gd::GroupedDataFrame) = length(gd.starts)
Base.first(gd::GroupedDataFrame) = gd[1]
Base.last(gd::GroupedDataFrame) = gd[end]
Base.getindex(gd::GroupedDataFrame, idx::Integer) =
    view(gd.parent, gd.idx[gd.starts[idx]:gd.ends[idx]], :)
Base.getindex(gd::GroupedDataFrame, idxs::AbstractArray) =
    GroupedDataFrame(gd.parent, gd.cols, gd.groups, gd.idx, gd.starts[idxs], gd.ends[idxs])
Base.getindex(gd::GroupedDataFrame, idxs::Colon) =
    GroupedDataFrame(gd.parent, gd.cols, gd.groups, gd.idx, gd.starts, gd.ends)
function Base.:(==)(gd1::GroupedDataFrame, gd2::GroupedDataFrame)
    gd1.cols == gd2.cols &&
        length(gd1) == length(gd2) &&
        all(x -> ==(x...), zip(gd1, gd2))
end
function Base.isequal(gd1::GroupedDataFrame, gd2::GroupedDataFrame)
    isequal(gd1.cols, gd2.cols) &&
        isequal(length(gd1), length(gd2)) &&
        all(x -> isequal(x...), zip(gd1, gd2))
end
Base.names(gd::GroupedDataFrame) = names(gd.parent)
_names(gd::GroupedDataFrame) = _names(gd.parent)
""" """ function Base.map(f::Any, gd::GroupedDataFrame)
    if length(gd) > 0
        idx, valscat = _combine(f, gd)
        parent = hcat!(gd.parent[idx, gd.cols], valscat, makeunique=true)
        starts = Vector{Int}(undef, length(gd))
        ends = Vector{Int}(undef, length(gd))
        starts[1] = 1
        j = 2
        @inbounds for i in 2:length(idx)
            if idx[i] != idx[i-1]
                starts[j] = i
                ends[j-1] = i - 1
                j += 1
            end
        end
        resize!(starts, j-1)
        resize!(ends, j-1)
        ends[end] = length(idx)
        return GroupedDataFrame(parent, collect(1:length(gd.cols)), idx,
                                collect(1:length(idx)), starts, ends)
    else
        return GroupedDataFrame(gd.parent[1:0, gd.cols], collect(1:length(gd.cols)),
                                Int[], Int[], Int[], Int[])
    end
end
""" """ function combine(f::Any, gd::GroupedDataFrame)
    if length(gd) > 0
        idx, valscat = _combine(f, gd)
        return hcat!(gd.parent[idx, gd.cols], valscat, makeunique=true)
    else
        return gd.parent[1:0, gd.cols]
    end
end
combine(gd::GroupedDataFrame, f::Any) = combine(f, gd)
combine(gd::GroupedDataFrame, f::Pair...) = combine(f, gd)
combine(gd::GroupedDataFrame, f::Pair) = combine(f, gd)
combine(gd::GroupedDataFrame; f...) =
    isempty(f) ? combine(identity, gd) : combine(values(f), gd)
wrap(x::Union{AbstractDataFrame, NamedTuple, DataFrameRow}) = x
wrap(x::AbstractMatrix) =
    NamedTuple{Tuple(gennames(size(x, 2)))}(Tuple(view(x, :, i) for i in 1:size(x, 2)))
wrap(x::Any) = (x1=x,)
function do_call(f::Any, gd::GroupedDataFrame, incols::AbstractVector, i::Integer)
    idx = gd.idx[gd.starts[i]:gd.ends[i]]
    f(view(incols, idx))
end
function do_call(f::Any, gd::GroupedDataFrame, incols::NamedTuple, i::Integer)
    idx = gd.idx[gd.starts[i]:gd.ends[i]]
    f(map(c -> view(c, idx), incols))
end
do_call(f::Any, gd::GroupedDataFrame, incols::Nothing, i::Integer) =
    f(gd[i])
_nrow(df::AbstractDataFrame) = nrow(df)
_nrow(x::NamedTuple{<:Any, <:Tuple{Vararg{AbstractVector}}}) =
    isempty(x) ? 0 : length(x[1])
_ncol(df::AbstractDataFrame) = ncol(df)
_ncol(x::Union{NamedTuple, DataFrameRow}) = length(x)
abstract type AbstractAggregate end
struct Reduce{O, C, A} <: AbstractAggregate
    op::O
    condf::C
    adjust::A
end
Reduce(f, condf=nothing) = Reduce(f, condf, nothing)
check_aggregate(f::Any) = f
check_aggregate(::typeof(sum)) = Reduce(Base.add_sum)
check_aggregate(::typeof(prod)) = Reduce(Base.mul_prod)
check_aggregate(::typeof(maximum)) = Reduce(max)
check_aggregate(::typeof(minimum)) = Reduce(min)
check_aggregate(::typeof(mean)) = Reduce(Base.add_sum, nothing, /)
check_aggregate(::typeof(sum∘skipmissing)) = Reduce(Base.add_sum, !ismissing)
check_aggregate(::typeof(prod∘skipmissing)) = Reduce(Base.mul_prod, !ismissing)
check_aggregate(::typeof(maximum∘skipmissing)) = Reduce(max, !ismissing)
check_aggregate(::typeof(minimum∘skipmissing)) = Reduce(min, !ismissing)
check_aggregate(::typeof(mean∘skipmissing)) = Reduce(Base.add_sum, !ismissing, /)
struct Aggregate{F, C} <: AbstractAggregate
    f::F
    condf::C
end
Aggregate(f) = Aggregate(f, nothing)
check_aggregate(::typeof(var)) = Aggregate(var)
check_aggregate(::typeof(var∘skipmissing)) = Aggregate(var, !ismissing)
check_aggregate(::typeof(std)) = Aggregate(std)
check_aggregate(::typeof(std∘skipmissing)) = Aggregate(std, !ismissing)
check_aggregate(::typeof(first)) = Aggregate(first)
check_aggregate(::typeof(first∘skipmissing)) = Aggregate(first, !ismissing)
check_aggregate(::typeof(last)) = Aggregate(last)
check_aggregate(::typeof(last∘skipmissing)) = Aggregate(last, !ismissing)
check_aggregate(::typeof(length)) = Aggregate(length)
for f in (:sum, :prod, :maximum, :minimum, :mean, :var, :std, :first, :last)
    @eval begin
        funname(::typeof(check_aggregate($f))) = Symbol($f)
        funname(::typeof(check_aggregate($f∘skipmissing))) = :function
    end
end
function fillfirst!(condf, outcol::AbstractVector, incol::AbstractVector,
                    gd::GroupedDataFrame; rev::Bool=false)
    nfilled = 0
    @inbounds for i in eachindex(outcol)
        s = gd.starts[i]
        offsets = rev ? (nrow(gd[i])-1:-1:0) : (0:nrow(gd[i])-1)
        for j in offsets
            x = incol[gd.idx[s+j]]
            if !condf === nothing || condf(x)
                outcol[i] = x
                nfilled += 1
                break
            end
        end
    end
    if nfilled < length(outcol)
        throw(ArgumentError("some groups contain only missing values"))
    end
    outcol
end
groupreduce_init(op, condf, incol, gd) =
    Base.reducedim_init(identity, op, view(incol, 1:length(gd)), 2)
for (op, initf) in ((:max, :typemin), (:min, :typemax))
    @eval begin
        function groupreduce_init(::typeof($op), condf, incol::AbstractVector{T}, gd) where T
            outcol = similar(incol, condf === !ismissing ? Missings.T(T) : T, length(gd))
            if incol isa CategoricalVector
                U = Union{CategoricalArrays.leveltype(outcol),
                          eltype(outcol) >: Missing ? Missing : Union{}}
                outcol = CategoricalArray{U, 1}(outcol.refs, incol.pool)
            end
            S = Missings.T(T)
            if isconcretetype(S) && hasmethod($initf, Tuple{S})
                fill!(outcol, $initf(S))
            elseif condf !== nothing
                fillfirst!(condf, outcol, incol, gd)
            else
                @inbounds for i in eachindex(outcol)
                    outcol[i] = incol[gd.idx[gd.starts[i]]]
                end
            end
            return outcol
        end
    end
end
function copyto_widen!(res::AbstractVector{T}, x::AbstractVector) where T
    @inbounds for i in eachindex(res, x)
        val = x[i]
        S = typeof(val)
        if S <: T || promote_type(S, T) <: T
            res[i] = val
        else
            newres = Tables.allocatecolumn(promote_type(S, T), length(x))
            return copyto_widen!(newres, x)
        end
    end
    return res
end
function groupreduce!(res, f, op, condf, adjust,
                      incol::AbstractVector{T}, gd::GroupedDataFrame) where T
    n = length(gd)
    if adjust !== nothing
        counts = zeros(Int, n)
    end
    @inbounds for i in eachindex(incol, gd.groups)
        gix = gd.groups[i]
        x = incol[i]
        if condf === nothing || condf(x)
            res[gix] = op(res[gix], f(x, gix))
            adjust !== nothing && (counts[gix] += 1)
        end
    end
    outcol = adjust === nothing ? res : map(adjust, res, counts)
    if outcol isa CategoricalVector
        U = Union{CategoricalArrays.leveltype(outcol),
                  eltype(outcol) >: Missing ? Missing : Union{}}
        outcol = CategoricalArray{U, 1}(outcol.refs, incol.pool)
    end
    if isconcretetype(eltype(outcol))
        return outcol
    else
        copyto_widen!(Tables.allocatecolumn(typeof(first(outcol)), n), outcol)
    end
end
groupreduce(f, op, condf, adjust, incol::AbstractVector, gd::GroupedDataFrame) =
    groupreduce!(groupreduce_init(op, condf, incol, gd),
                 f, op, condf, adjust, incol, gd)
groupreduce(f, op, condf::typeof(!ismissing), adjust,
            incol::AbstractVector, gd::GroupedDataFrame) =
    groupreduce!(disallowmissing(groupreduce_init(op, condf, incol, gd)),
                 f, op, condf, adjust, incol, gd)
(r::Reduce)(incol::AbstractVector, gd::GroupedDataFrame) =
    groupreduce((x, i) -> x, r.op, r.condf, r.adjust, incol, gd)
function (agg::Aggregate{typeof(var)})(incol::AbstractVector, gd::GroupedDataFrame)
    means = groupreduce((x, i) -> x, Base.add_sum, agg.condf, /, incol, gd)
    if eltype(means) >: Missing && agg.condf !== !ismissing
        T = Union{Missing, real(eltype(means))}
    else
        T = real(eltype(means))
    end
    res = zeros(T, length(gd))
    groupreduce!(res, (x, i) -> @inbounds(abs2(x - means[i])), +,
                 agg.condf, (x, l) -> x / (l-1), incol, gd)
end
function (agg::Aggregate{typeof(std)})(incol::AbstractVector, gd::GroupedDataFrame)
    outcol = Aggregate(var, agg.condf)(incol, gd)
    map!(sqrt, outcol, outcol)
end
for f in (first, last)
    function (agg::Aggregate{typeof(f)})(incol::AbstractVector, gd::GroupedDataFrame)
        n = length(gd)
        outcol = similar(incol, n)
        if agg.condf === !ismissing
            fillfirst!(agg.condf, outcol, incol, gd, rev=agg.f === last)
        else
            v = agg.f === first ? gd.starts : gd.ends
            map!(i -> incol[gd.idx[v[i]]], outcol, 1:n)
        end
        if isconcretetype(eltype(outcol))
            return outcol
        else
            return copyto_widen!(Tables.allocatecolumn(typeof(first(outcol)), n), outcol)
        end
    end
end
(agg::Aggregate{typeof(length)})(incol::AbstractVector, gd::GroupedDataFrame) =
    gd.ends .- gd.starts .+ 1
function do_f(f, x...)
    @inline function fun(x...)
        res = f(x...)
        if res isa Union{AbstractDataFrame, NamedTuple, DataFrameRow, AbstractMatrix}
            throw(ArgumentError("a single value or vector result is required when passing " *
                                "a vector or tuple of functions (got $(typeof(res)))"))
        end
        res
    end
end
function _combine(f::Union{AbstractVector{<:Pair}, Tuple{Vararg{Pair}},
                           NamedTuple{<:Any, <:Tuple{Vararg{Pair}}}},
                  gd::GroupedDataFrame)
    res = map(f) do p
        agg = check_aggregate(last(p))
        if agg isa AbstractAggregate && p isa Pair{<:Union{Symbol,Integer}}
            incol = gd.parent[first(p)]
            idx = gd.idx[gd.starts]
            outcol = agg(incol, gd)
            return idx, outcol
        else
            fun = do_f(last(p))
            if p isa Pair{<:Union{Symbol,Integer}}
                incols = gd.parent[first(p)]
            else
                df = gd.parent[collect(first(p))]
                incols = NamedTuple{Tuple(names(df))}(columns(df))
            end
            firstres = do_call(fun, gd, incols, 1)
            idx, outcols, _ = _combine_with_first(wrap(firstres), fun, gd, incols)
            return idx, outcols[1]
        end
    end
    idx = res[1][1]
    outcols = map(x -> x[2], res)
    if !all(x -> length(x) == length(outcols[1]), outcols)
        throw(ArgumentError("all functions must return values of the same length"))
    end
    if f isa NamedTuple
        nams = collect(Symbol, propertynames(f))
    else
        nams = [f[i] isa Pair{<:Union{Symbol,Integer}} ?
                    Symbol(names(gd.parent)[index(gd.parent)[first(f[i])]],
                           '_', funname(last(f[i]))) :
                    Symbol('x', i)
                for i in 1:length(f)]
    end
    valscat = DataFrame(collect(outcols), nams, makeunique=true)
    return idx, valscat
end
function _combine(f::Any, gd::GroupedDataFrame)
    if f isa Pair{<:Union{Symbol,Integer}}
        incols = gd.parent[first(f)]
        fun = check_aggregate(last(f))
    elseif f isa Pair
        df = gd.parent[collect(first(f))]
        incols = NamedTuple{Tuple(names(df))}(columns(df))
        fun = last(f)
    else
        incols = nothing
        fun = f
    end
    agg = check_aggregate(fun)
    if agg isa AbstractAggregate && f isa Pair{<:Union{Symbol,Integer}}
        idx = gd.idx[gd.starts]
        outcols = (agg(incols, gd),)
    else
        firstres = do_call(fun, gd, incols, 1)
        idx, outcols, nms = _combine_with_first(wrap(firstres), fun, gd, incols)
    end
    if f isa Pair{<:Union{Symbol,Integer}} &&
        (agg isa AbstractAggregate ||
         !isa(firstres, Union{AbstractDataFrame, NamedTuple, DataFrameRow, AbstractMatrix}))
         nms = [Symbol(names(gd.parent)[index(gd.parent)[first(f)]], '_', funname(fun))]
    end
    valscat = DataFrame(collect(outcols), collect(Symbol, nms))
    return idx, valscat
end
function _combine_with_first(first::Union{NamedTuple, DataFrameRow, AbstractDataFrame},
                             f::Any, gd::GroupedDataFrame,
                             incols::Union{Nothing, AbstractVector, NamedTuple})
    if first isa AbstractDataFrame
        n = 0
        eltys = eltypes(first)
    elseif first isa NamedTuple{<:Any, <:Tuple{Vararg{AbstractVector}}}
        n = 0
        eltys = map(eltype, first)
    elseif first isa DataFrameRow
        n = length(gd)
        eltys = eltypes(parent(first))
    else # NamedTuple giving a single row
        n = length(gd)
        eltys = map(typeof, first)
        if any(x -> x <: AbstractVector, eltys)
            throw(ArgumentError("mixing single values and vectors in a (named) tuple is not allowed"))
        end
    end
    idx = Vector{Int}(undef, n)
    local initialcols
    let eltys=eltys, n=n # Workaround for julia#15276
        initialcols = ntuple(i -> Tables.allocatecolumn(eltys[i], n), _ncol(first))
    end
    outcols = _combine_with_first!(first, initialcols, idx, 1, 1, f, gd, incols,
                                   tuple(propertynames(first)...))
    idx, outcols, propertynames(first)
end
function fill_row!(row, outcols::NTuple{N, AbstractVector},
                   i::Integer, colstart::Integer,
                   colnames::NTuple{N, Symbol}) where N
    if !isa(row, Union{NamedTuple, DataFrameRow})
        throw(ArgumentError("return value must not change its kind " *
                            "(single row or variable number of rows) across groups"))
    elseif _ncol(row) != N
        throw(ArgumentError("return value must have the same number of columns " *
                            "for all groups (got $N and $(length(row)))"))
    end
    @inbounds for j in colstart:length(outcols)
        col = outcols[j]
        cn = colnames[j]
        local val
        try
            val = row[cn]
        catch
            throw(ArgumentError("return value must have the same column names " *
                                "for all groups (got $colnames and $(propertynames(row)))"))
        end
        S = typeof(val)
        T = eltype(col)
        if S <: T || promote_type(S, T) <: T
            col[i] = val
        else
            return j
        end
    end
    return nothing
end
function _combine_with_first!(first::Union{NamedTuple, DataFrameRow}, outcols::NTuple{N, AbstractVector},
                              idx::Vector{Int}, rowstart::Integer, colstart::Integer,
                              f::Any, gd::GroupedDataFrame,
                              incols::Union{Nothing, AbstractVector, NamedTuple},
                              colnames::NTuple{N, Symbol}) where N
    len = length(gd)
    j = fill_row!(first, outcols, rowstart, colstart, colnames)
    @assert j === nothing # eltype is guaranteed to match
    idx[rowstart] = gd.idx[gd.starts[rowstart]]
    @inbounds for i in rowstart+1:len
        row = wrap(do_call(f, gd, incols, i))
        j = fill_row!(row, outcols, i, 1, colnames)
        if j !== nothing # Need to widen column type
            local newcols
            let i = i, j = j, outcols=outcols, row=row # Workaround for julia#15276
                newcols = ntuple(length(outcols)) do k
                    S = typeof(row[k])
                    T = eltype(outcols[k])
                    U = promote_type(S, T)
                    if S <: T || U <: T
                        outcols[k]
                    else
                        copyto!(Tables.allocatecolumn(U, length(outcols[k])),
                                1, outcols[k], 1, k >= j ? i-1 : i)
                    end
                end
            end
            return _combine_with_first!(row, newcols, idx, i, j, f, gd, incols, colnames)
        end
        idx[i] = gd.idx[gd.starts[i]]
    end
    outcols
end
if VERSION >= v"1.1.0-DEV.723"
    @inline function do_append!(do_it, col, vals)
        do_it && append!(col, vals)
        return do_it
    end
else
    @noinline function do_append!(do_it, col, vals)
        do_it && append!(col, vals)
        return do_it
    end
end
function append_rows!(rows, outcols::NTuple{N, AbstractVector},
                      colstart::Integer, colnames::NTuple{N, Symbol}) where N
    if !isa(rows, Union{AbstractDataFrame, NamedTuple{<:Any, <:Tuple{Vararg{AbstractVector}}}})
        throw(ArgumentError("return value must not change its kind " *
                            "(single row or variable number of rows) across groups"))
    elseif _ncol(rows) != N
        throw(ArgumentError("return value must have the same number of columns " *
                            "for all groups (got $N and $(_ncol(rows)))"))
    end
    @inbounds for j in colstart:length(outcols)
        col = outcols[j]
        cn = colnames[j]
        local vals
        try
            vals = rows[cn]
        catch
            throw(ArgumentError("return value must have the same column names " *
                                "for all groups (got $(Tuple(colnames)) and $(Tuple(names(rows))))"))
        end
        S = eltype(vals)
        T = eltype(col)
        if !do_append!(S <: T || promote_type(S, T) <: T, col, vals)
            return j
        end
    end
    return nothing
end
function _combine_with_first!(first::Union{AbstractDataFrame,
                                           NamedTuple{<:Any, <:Tuple{Vararg{AbstractVector}}}},
                              outcols::NTuple{N, AbstractVector},
                              idx::Vector{Int}, rowstart::Integer, colstart::Integer,
                              f::Any, gd::GroupedDataFrame,
                              incols::Union{Nothing, AbstractVector, NamedTuple},
                              colnames::NTuple{N, Symbol}) where N
    len = length(gd)
    j = append_rows!(first, outcols, colstart, colnames)
    @assert j === nothing # eltype is guaranteed to match
    append!(idx, Iterators.repeated(gd.idx[gd.starts[rowstart]], _nrow(first)))
    @inbounds for i in rowstart+1:len
        rows = wrap(do_call(f, gd, incols, i))
        j = append_rows!(rows, outcols, 1, colnames)
        if j !== nothing # Need to widen column type
            local newcols
            let i = i, j = j, outcols=outcols, rows=rows # Workaround for julia#15276
                newcols = ntuple(length(outcols)) do k
                    S = eltype(rows[k])
                    T = eltype(outcols[k])
                    U = promote_type(S, T)
                    if S <: T || U <: T
                        outcols[k]
                    else
                        copyto!(Tables.allocatecolumn(U, length(outcols[k])), outcols[k])
                    end
                end
            end
            return _combine_with_first!(rows, newcols, idx, i, j, f, gd, incols, colnames)
        end
        append!(idx, Iterators.repeated(gd.idx[gd.starts[i]], _nrow(rows)))
    end
    outcols
end
""" """ colwise(f, d::AbstractDataFrame) = [f(d[i]) for i in 1:ncol(d)]
colwise(fns::Union{AbstractVector, Tuple}, d::AbstractDataFrame) = [f(d[i]) for f in fns, i in 1:ncol(d)]
colwise(f, gd::GroupedDataFrame) = [colwise(f, g) for g in gd]
""" """ by(d::AbstractDataFrame, cols::Any, f::Any; sort::Bool = false) =
    combine(f, groupby(d, cols, sort = sort))
by(f::Any, d::AbstractDataFrame, cols::Any; sort::Bool = false) =
    by(d, cols, f, sort = sort)
by(d::AbstractDataFrame, cols::Any, f::Pair; sort::Bool = false) =
    combine(f, groupby(d, cols, sort = sort))
by(d::AbstractDataFrame, cols::Any, f::Pair...; sort::Bool = false) =
    combine(f, groupby(d, cols, sort = sort))
by(d::AbstractDataFrame, cols::Any; sort::Bool = false, f...) =
    combine(values(f), groupby(d, cols, sort = sort))
""" """ aggregate(d::AbstractDataFrame, fs::Any; sort::Bool=false) =
    aggregate(d, [fs], sort=sort)
function aggregate(d::AbstractDataFrame, fs::AbstractVector; sort::Bool=false)
    headers = _makeheaders(fs, _names(d))
    _aggregate(d, fs, headers, sort)
end
aggregate(gd::GroupedDataFrame, f::Any; sort::Bool=false) = aggregate(gd, [f], sort=sort)
function aggregate(gd::GroupedDataFrame, fs::AbstractVector; sort::Bool=false)
    headers = _makeheaders(fs, setdiff(_names(gd), _names(gd.parent[gd.cols])))
    res = combine(x -> _aggregate(without(x, gd.cols), fs, headers), gd)
    sort && sort!(res, headers)
    res
end
function aggregate(d::AbstractDataFrame,
                   cols::Union{S, AbstractVector{S}},
                   fs::Any;
                   sort::Bool=false) where {S<:ColumnIndex}
    aggregate(groupby(d, cols, sort=sort), fs)
end
function funname(f)
    n = nameof(f)
    String(n)[1] == '#' ? :function : n
end
_makeheaders(fs::AbstractVector, cn::AbstractVector{Symbol}) =
    [Symbol(colname, '_', funname(f)) for f in fs for colname in cn]
function _aggregate(d::AbstractDataFrame, fs::AbstractVector,
                    headers::AbstractVector{Symbol}, sort::Bool=false)
    res = DataFrame(AbstractVector[vcat(f(d[i])) for f in fs for i in 1:size(d, 2)], headers, makeunique=true)
    sort && sort!(res, headers)
    res
end