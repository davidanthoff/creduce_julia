@require JuliaDB begin
using TableTraits
using JuliaDB: DTable
import IndexedTables
TableTraits.isiterable(x::DTable) = true
TableTraits.isiterabletable(x::DTable) = true
function TableTraits.getiterator{S<:DTable}(source::S)
    it  = collect(source)
    iter = getiterator(it)
    return iter
end
function JuliaDB.distribute(source, rowgroups::AbstractArray; idxcols::Union{Void,Vector{Symbol}}=nothing, datacols::Union{Void,Vector{Symbol}}=nothing)
    isiterabletable(source) || error()
    it = IndexedTables.IndexedTable(source, idxcols=idxcols, datacols=datacols)
    dt = JuliaDB.distribute(it, rowgroups)
    return dt
end
function JuliaDB.distribute(source, nchunks::Int=nworkers(); idxcols::Union{Void,Vector{Symbol}}=nothing, datacols::Union{Void,Vector{Symbol}}=nothing)
    isiterabletable(source) || error()
    it = IndexedTables.IndexedTable(source, idxcols=idxcols, datacols=datacols)
    dt = JuliaDB.distribute(it, nchunks)
    return dt
end
end
