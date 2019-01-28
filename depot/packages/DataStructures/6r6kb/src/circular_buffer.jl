mutable struct CircularBuffer{T} <: AbstractVector{T}
    capacity::Int
    first::Int
    length::Int
    buffer::Vector{T}
    CircularBuffer{T}(capacity::Int) where {T} = new{T}(capacity, 1, 0, Vector{T}(undef, capacity))
end
function Base.empty!(cb::CircularBuffer)
    cb.length = 0
    cb
end
Base.@propagate_inbounds function _buffer_index_checked(cb::CircularBuffer, i::Int)
    @boundscheck if i < 1 || i > cb.length
        throw(BoundsError(cb, i))
    end
    _buffer_index(cb, i)
end
@inline function _buffer_index(cb::CircularBuffer, i::Int)
    n = cb.capacity
    idx = cb.first + i - 1
    if idx > n
        idx - n
    else
        idx
    end
end
@inline Base.@propagate_inbounds function Base.getindex(cb::CircularBuffer, i::Int)
    cb.buffer[_buffer_index_checked(cb, i)]
end
@inline Base.@propagate_inbounds function Base.setindex!(cb::CircularBuffer, data, i::Int)
    cb.buffer[_buffer_index_checked(cb, i)] = data
    cb
end
@inline function Base.pop!(cb::CircularBuffer)
    if cb.length == 0
        throw(ArgumentError("array must be non-empty"))
    end
    i = _buffer_index(cb, cb.length)
    cb.length -= 1
    cb.buffer[i]
end
@inline function Base.push!(cb::CircularBuffer, data)
    if cb.length == cb.capacity
        cb.first = (cb.first == cb.capacity ? 1 : cb.first + 1)
    else
        cb.length += 1
    end
    cb.buffer[_buffer_index(cb, cb.length)] = data
    cb
end
function popfirst!(cb::CircularBuffer)
    if cb.length == 0
        throw(ArgumentError("array must be non-empty"))
    end
    i = cb.first
    cb.first = (cb.first + 1 > cb.capacity ? 1 : cb.first + 1)
    cb.length -= 1
    cb.buffer[i]
end
function pushfirst!(cb::CircularBuffer, data)
    cb.first = (cb.first == 1 ? cb.capacity : cb.first - 1)
    if length(cb) < cb.capacity
        cb.length += 1
    end
    cb.buffer[cb.first] = data
    cb
end
function Base.append!(cb::CircularBuffer, datavec::AbstractVector)
    n = length(datavec)
    for i in max(1, n-capacity(cb)+1):n
        push!(cb, datavec[i])
    end
    cb
end
function Base.fill!(cb::CircularBuffer, data)
    for i in 1:capacity(cb)-length(cb)
        push!(cb, data)
    end
    cb
end
Base.length(cb::CircularBuffer) = cb.length
Base.size(cb::CircularBuffer) = (length(cb),)
Base.convert(::Type{Array}, cb::CircularBuffer{T}) where {T} = T[x for x in cb]
Base.isempty(cb::CircularBuffer) = cb.length == 0
capacity(cb::CircularBuffer) = cb.capacity
isfull(cb::CircularBuffer) = length(cb) == cb.capacity
