struct TranscodingStream{C<:Codec,S<:IO} <: IO
    codec::C
    stream::S
    state::State
    function TranscodingStream{C,S}(codec::C, stream::S, state::State, initialized::Bool) where {C<:Codec,S<:IO}
        if !isopen(stream)
            throw(ArgumentError("closed stream"))
        elseif state.mode != :idle
            throw(ArgumentError("invalid initial mode"))
        end
        if !initialized
            initialize(codec)
        end
        return new(codec, stream, state)
    end
end
function TranscodingStream(codec::C, stream::S, state::State;
                           initialized::Bool=false) where {C<:Codec,S<:IO}
    return TranscodingStream{C,S}(codec, stream, state, initialized)
end
const DEFAULT_BUFFER_SIZE = 16 * 2^10  # 16KiB
function checkbufsize(bufsize::Integer)
    if bufsize ≤ 0
        throw(ArgumentError("non-positive buffer size"))
    end
end
function checksharedbuf(sharedbuf::Bool, stream::IO)
    if sharedbuf && !(stream isa TranscodingStream)
        throw(ArgumentError("invalid stream type for sharedbuf=true"))
    end
end
""" """ function TranscodingStream(codec::Codec, stream::IO;
                           bufsize::Integer=DEFAULT_BUFFER_SIZE,
                           stop_on_end::Bool=false,
                           sharedbuf::Bool=(stream isa TranscodingStream))
    checkbufsize(bufsize)
    checksharedbuf(sharedbuf, stream)
    if sharedbuf
        state = State(Buffer(bufsize), stream.state.buffer1)
    else
        state = State(bufsize)
    end
    state.stop_on_end = stop_on_end
    return TranscodingStream(codec, stream, state)
end
function Base.show(io::IO, stream::TranscodingStream)
    print(io, summary(stream), "(<mode=$(stream.state.mode)>)")
end
function splitkwargs(kwargs, keys)
    hits = []
    others = []
    for kwarg in kwargs
        push!(kwarg[1] ∈ keys ? hits : others, kwarg)
    end
    return hits, others
end
macro checkmode(validmodes)
    mode = esc(:mode)
    quote
        if !$(foldr((x, y) -> :($(mode) == $(QuoteNode(x)) || $(y)), eval(validmodes), init=false))
            throw(ArgumentError(string("invalid mode :", $(mode))))
        end
    end
end
function Base.open(f::Function, ::Type{T}, args...) where T<:TranscodingStream
    stream = T(open(args...))
    try
        f(stream)
    finally
        close(stream)
    end
end
function Base.isopen(stream::TranscodingStream)
    return stream.state.mode != :close && stream.state.mode != :panic
end
function Base.close(stream::TranscodingStream)
    stopped = stream.state.mode == :stop
    if stream.state.mode != :panic
        changemode!(stream, :close)
    end
    if !stopped
        close(stream.stream)
    end
    return nothing
end
function Base.eof(stream::TranscodingStream)
    mode = stream.state.mode
    if mode == :idle
        changemode!(stream, :read)
        return eof(stream)
    elseif mode == :read
        return buffersize(stream.state.buffer1) == 0 && fillbuffer(stream) == 0
    elseif mode == :write
        return eof(stream.stream)
    elseif mode == :close
        return true
    elseif mode == :stop
        return buffersize(stream.state.buffer1) == 0
    elseif mode == :panic
        throw_panic_error()
    else
        @assert false
    end
end
function Base.ismarked(stream::TranscodingStream)
    checkmode(stream)
    return ismarked(stream.state.buffer1)
end
function Base.mark(stream::TranscodingStream)
    checkmode(stream)
    return mark!(stream.state.buffer1)
end
function Base.unmark(stream::TranscodingStream)
    checkmode(stream)
    return unmark!(stream.state.buffer1)
end
function Base.reset(stream::TranscodingStream)
    checkmode(stream)
    return reset!(stream.state.buffer1)
end
function Base.skip(stream::TranscodingStream, offset::Integer)
    checkmode(stream)
    if offset < 0
        throw(ArgumentError("negative offset"))
    end
    mode = stream.state.mode
    buffer1 = stream.state.buffer1
    skipped = 0
    if mode == :read
        while !eof(stream) && buffersize(buffer1) < offset - skipped
            n = buffersize(buffer1)
            emptybuffer!(buffer1)
            skipped += n
        end
        if eof(stream)
            emptybuffer!(buffer1)
        else
            skipbuffer!(buffer1, offset - skipped)
        end
    else
        throw(ArgumentError("not in read mode"))
    end
    return
end
function Base.seekstart(stream::TranscodingStream)
    mode = stream.state.mode
    @checkmode (:idle, :read, :write)
    if mode == :read || mode == :write
        callstartproc(stream, mode)
        emptybuffer!(stream.state.buffer1)
        emptybuffer!(stream.state.buffer2)
    end
    seekstart(stream.stream)
    return
end
function Base.seekend(stream::TranscodingStream)
    mode = stream.state.mode
    @checkmode (:idle, :read, :write)
    if mode == :read || mode == :write
        callstartproc(stream, mode)
        emptybuffer!(stream.state.buffer1)
        emptybuffer!(stream.state.buffer2)
    end
    seekend(stream.stream)
    return
end
function Base.read(stream::TranscodingStream, ::Type{UInt8})
    ready_to_read!(stream)
    if eof(stream)
        throw(EOFError())
    end
    return readbyte!(stream.state.buffer1)
end
function Base.readuntil(stream::TranscodingStream, delim::UInt8; keep::Bool=false)
    ready_to_read!(stream)
    buffer1 = stream.state.buffer1
    local ret::Vector{UInt8}
    filled = 0
    while !eof(stream)
        p = findbyte(buffer1, delim)
        found = false
        if p < marginptr(buffer1)
            found = true
            sz = Int(p + 1 - bufferptr(buffer1))
            if !keep
                sz -= 1
            end
        else
            sz = buffersize(buffer1)
        end
        if @isdefined(ret)
            resize!(ret, filled + sz)
        else
            @assert filled == 0
            ret = Vector{UInt8}(undef, sz)
        end
        copydata!(pointer(ret, filled+1), buffer1, sz)
        filled += sz
        if found
            break
        end
    end
    return ret
end
function Base.unsafe_read(stream::TranscodingStream, output::Ptr{UInt8}, nbytes::UInt)
    ready_to_read!(stream)
    buffer = stream.state.buffer1
    p = output
    p_end = output + nbytes
    while p < p_end && !eof(stream)
        m = min(buffersize(buffer), p_end - p)
        copydata!(p, buffer, m)
        p += m
    end
    if p < p_end && eof(stream)
        throw(EOFError())
    end
    return
end
function Base.readbytes!(stream::TranscodingStream, b::AbstractArray{UInt8}, nb=length(b))
    ready_to_read!(stream)
    filled = 0
    resized = false
    while filled < nb && !eof(stream)
        if length(b) == filled
            resize!(b, min(length(b) * 2, nb))
            resized = true
        end
        filled += unsafe_read(stream, pointer(b, filled+1), min(length(b), nb)-filled)
    end
    if resized
        resize!(b, filled)
    end
    return filled
end
function Base.bytesavailable(stream::TranscodingStream)
    ready_to_read!(stream)
    return buffersize(stream.state.buffer1)
end
function Base.readavailable(stream::TranscodingStream)
    n = bytesavailable(stream)
    data = Vector{UInt8}(undef, n)
    unsafe_read(stream, pointer(data), n)
    return data
end
""" """ function unread(stream::TranscodingStream, data::ByteData)
    unsafe_unread(stream, pointer(data), sizeof(data))
end
""" """ function unsafe_unread(stream::TranscodingStream, data::Ptr, nbytes::Integer)
    if nbytes < 0
        throw(ArgumentError("negative nbytes"))
    end
    ready_to_read!(stream)
    insertdata!(stream.state.buffer1, convert(Ptr{UInt8}, data), nbytes)
    return nothing
end
function ready_to_read!(stream::TranscodingStream)
    mode = stream.state.mode
    if !(mode == :read || mode == :stop)
        changemode!(stream, :read)
    end
    return
end
function Base.write(stream::TranscodingStream)
    changemode!(stream, :write)
    return 0
end
function Base.write(stream::TranscodingStream, b::UInt8)
    changemode!(stream, :write)
    if marginsize(stream.state.buffer1) == 0 && flushbuffer(stream) == 0
        return 0
    end
    return writebyte!(stream.state.buffer1, b)
end
function Base.unsafe_write(stream::TranscodingStream, input::Ptr{UInt8}, nbytes::UInt)
    changemode!(stream, :write)
    state = stream.state
    buffer1 = state.buffer1
    p = input
    p_end = p + nbytes
    while p < p_end && (marginsize(buffer1) > 0 || flushbuffer(stream) > 0)
        m = min(marginsize(buffer1), p_end - p)
        copydata!(buffer1, p, m)
        p += m
    end
    return Int(p - input)
end
struct EndToken end
""" """ const TOKEN_END = EndToken()
function Base.write(stream::TranscodingStream, ::EndToken)
    changemode!(stream, :write)
    flushbufferall(stream)
    flushuntilend(stream)
    return 0
end
function Base.flush(stream::TranscodingStream)
    checkmode(stream)
    if stream.state.mode == :write
        flushbufferall(stream)
        writedata!(stream.stream, stream.state.buffer2)
    end
    flush(stream.stream)
end
""" """ struct Stats
    in::Int64
    out::Int64
    transcoded_in::Int64
    transcoded_out::Int64
end
function Base.show(io::IO, stats::Stats)
    println(io, summary(stats), ':')
    println(io, "  in: ", stats.in)
    println(io, "  out: ", stats.out)
    println(io, "  transcoded_in: ", stats.transcoded_in)
      print(io, "  transcoded_out: ", stats.transcoded_out)
end
""" """ function stats(stream::TranscodingStream)
    state = stream.state
    mode = state.mode
    @checkmode (:idle, :read, :write)
    buffer1 = state.buffer1
    buffer2 = state.buffer2
    if mode == :idle
        transcoded_in = transcoded_out = in = out = 0
    elseif mode == :read
        transcoded_in = buffer2.total
        transcoded_out = buffer1.total
        in = transcoded_in + buffersize(buffer2)
        out = transcoded_out - buffersize(buffer1)
    elseif mode == :write
        transcoded_in = buffer1.total
        transcoded_out = buffer2.total
        in = transcoded_in + buffersize(buffer1)
        out = transcoded_out - buffersize(buffer2)
    else
        assert(false)
    end
    return Stats(in, out, transcoded_in, transcoded_out)
end
function fillbuffer(stream::TranscodingStream)
    changemode!(stream, :read)
    buffer1 = stream.state.buffer1
    buffer2 = stream.state.buffer2
    nfilled::Int = 0
    while buffersize(buffer1) == 0 && stream.state.mode != :stop
        if stream.state.code == :end
            if buffersize(buffer2) == 0 && eof(stream.stream)
                break
            end
            callstartproc(stream, :read)
        end
        makemargin!(buffer2, 1)
        readdata!(stream.stream, buffer2)
        _, Δout = callprocess(stream, buffer2, buffer1)
        nfilled += Δout
    end
    return nfilled
end
function flushbuffer(stream::TranscodingStream, all::Bool=false)
    changemode!(stream, :write)
    state = stream.state
    buffer1 = state.buffer1
    buffer2 = state.buffer2
    nflushed::Int = 0
    while (all ? buffersize(buffer1) > 0 : makemargin!(buffer1, 0) == 0) && state.mode != :stop
        if state.code == :end
            callstartproc(stream, :write)
        end
        writedata!(stream.stream, buffer2)
        Δin, _ = callprocess(stream, buffer1, buffer2)
        nflushed += Δin
    end
    return nflushed
end
function flushbufferall(stream::TranscodingStream)
    return flushbuffer(stream, true)
end
function flushuntilend(stream::TranscodingStream)
    changemode!(stream, :write)
    state = stream.state
    buffer1 = state.buffer1
    buffer2 = state.buffer2
    while state.code != :end
        writedata!(stream.stream, buffer2)
        callprocess(stream, buffer1, buffer2)
    end
    writedata!(stream.stream, buffer2)
    @assert buffersize(buffer1) == 0
    return
end
function callstartproc(stream::TranscodingStream, mode::Symbol)
    state = stream.state
    state.code = startproc(stream.codec, mode, state.error)
    if state.code == :error
        changemode!(stream, :panic)
    end
    return
end
function callprocess(stream::TranscodingStream, inbuf::Buffer, outbuf::Buffer)
    state = stream.state
    input = buffermem(inbuf)
    makemargin!(outbuf, minoutsize(stream.codec, input))
    Δin, Δout, state.code = process(stream.codec, input, marginmem(outbuf), state.error)
    consumed2!(inbuf, Δin)
    supplied2!(outbuf, Δout)
    if state.code == :error
        changemode!(stream, :panic)
    elseif state.code == :ok && Δin == Δout == 0
        makemargin!(outbuf, max(16, marginsize(outbuf) * 2))
    elseif state.code == :end && state.stop_on_end
        changemode!(stream, :stop)
    end
    return Δin, Δout
end
function readdata!(input::IO, output::Buffer)
    if input isa TranscodingStream && input.state.buffer1 === output
        return fillbuffer(input)
    end
    nread::Int = 0
    navail = bytesavailable(input)
    if navail == 0 && marginsize(output) > 0 && !eof(input)
        nread += writebyte!(output, read(input, UInt8))
        navail = bytesavailable(input)
    end
    n = min(navail, marginsize(output))
    Base.unsafe_read(input, marginptr(output), n)
    supplied!(output, n)
    nread += n
    return nread
end
function writedata!(output::IO, input::Buffer)
    if output isa TranscodingStream && output.state.buffer1 === input
        return flushbufferall(output)
    end
    nwritten::Int = 0
    while buffersize(input) > 0
        n = Base.unsafe_write(output, bufferptr(input), buffersize(input))
        consumed!(input, n)
        nwritten += n
    end
    return nwritten
end
function changemode!(stream::TranscodingStream, newmode::Symbol)
    state = stream.state
    mode = state.mode
    buffer1 = state.buffer1
    buffer2 = state.buffer2
    if mode == newmode
        return
    elseif newmode == :panic
        if !haserror(state.error)
            state.error[] = ErrorException("unknown error happened while processing data")
        end
        state.mode = newmode
        finalize_codec(stream.codec, state.error)
        throw(state.error[])
    elseif mode == :idle
        if newmode == :read || newmode == :write
            state.code = startproc(stream.codec, newmode, state.error)
            if state.code == :error
                changemode!(stream, :panic)
            end
            state.mode = newmode
            return
        elseif newmode == :close
            state.mode = newmode
            finalize_codec(stream.codec, state.error)
            return
        end
    elseif mode == :read
        if newmode == :close || newmode == :stop
            state.mode = newmode
            finalize_codec(stream.codec, state.error)
            return
        end
    elseif mode == :write
        if newmode == :close || newmode == :stop
            if newmode == :close
                flushbufferall(stream)
                flushuntilend(stream)
            end
            state.mode = newmode
            finalize_codec(stream.codec, state.error)
            return
        end
    elseif mode == :stop
        if newmode == :close
            state.mode = newmode
            return
        end
    elseif mode == :panic
        throw_panic_error()
    end
    throw(ArgumentError("cannot change the mode from $(mode) to $(newmode)"))
end
function checkmode(stream::TranscodingStream)
    if stream.state.mode == :panic
        throw_panic_error()
    end
end
function throw_panic_error()
    throw(ArgumentError("stream is in unrecoverable error; only isopen and close are callable"))
end
function finalize_codec(codec::Codec, error::Error)
    try
        finalize(codec)
    catch
        if haserror(error)
            throw(error[])
        else
            rethrow()
        end
    end
end