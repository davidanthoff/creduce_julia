abstract type CompressorCodec <: TranscodingStreams.Codec end
function Base.show(io::IO, codec::CompressorCodec)
    print(io, summary(codec), "(level=$(codec.level), windowbits=$(codec.windowbits))")
end
struct GzipCompressor <: CompressorCodec
    zstream::ZStream
    level::Int
    windowbits::Int
end
""" """ function GzipCompressor(;level::Integer=Z_DEFAULT_COMPRESSION,
                         windowbits::Integer=Z_DEFAULT_WINDOWBITS)
    if !(-1 ≤ level ≤ 9)
        throw(ArgumentError("compression level must be within -1..9"))
    elseif !(8 ≤ windowbits ≤ 15)
        throw(ArgumentError("windowbits must be within 8..15"))
    end
    return GzipCompressor(ZStream(), level, windowbits+16)
end
const GzipCompressorStream{S} = TranscodingStream{GzipCompressor,S} where S<:IO
""" """ function GzipCompressorStream(stream::IO; kwargs...)
    x, y = splitkwargs(kwargs, (:level, :windowbits))
    return TranscodingStream(GzipCompressor(;x...), stream; y...)
end
struct ZlibCompressor <: CompressorCodec
    zstream::ZStream
    level::Int
    windowbits::Int
end
""" """ function ZlibCompressor(;level::Integer=Z_DEFAULT_COMPRESSION,
                         windowbits::Integer=Z_DEFAULT_WINDOWBITS)
    if !(-1 ≤ level ≤ 9)
        throw(ArgumentError("compression level must be within -1..9"))
    elseif !(8 ≤ windowbits ≤ 15)
        throw(ArgumentError("windowbits must be within 8..15"))
    end
    return ZlibCompressor(ZStream(), level, windowbits)
end
const ZlibCompressorStream{S} = TranscodingStream{ZlibCompressor,S} where S<:IO
""" """ function ZlibCompressorStream(stream::IO; kwargs...)
    x, y = splitkwargs(kwargs, (:level, :windowbits))
    return TranscodingStream(ZlibCompressor(;x...), stream; y...)
end
struct DeflateCompressor <: CompressorCodec
    zstream::ZStream
    level::Int
    windowbits::Int
end
""" """ function DeflateCompressor(;level::Integer=Z_DEFAULT_COMPRESSION,
                        windowbits::Integer=Z_DEFAULT_WINDOWBITS)
    if !(-1 ≤ level ≤ 9)
        throw(ArgumentError("compression level must be within -1..9"))
    elseif !(8 ≤ windowbits ≤ 15)
        throw(ArgumentError("windowbits must be within 8..15"))
    end
    return DeflateCompressor(ZStream(), level, -Int(windowbits))
end
const DeflateCompressorStream{S} = TranscodingStream{DeflateCompressor,S} where S<:IO
""" """ function DeflateCompressorStream(stream::IO; kwargs...)
    x, y = splitkwargs(kwargs, (:level, :windowbits))
    return TranscodingStream(DeflateCompressor(;x...), stream; y...)
end
function TranscodingStreams.initialize(codec::CompressorCodec)
    code = deflate_init!(codec.zstream, codec.level, codec.windowbits)
    if code != Z_OK
        zerror(codec.zstream, code)
    end
    return
end
function TranscodingStreams.finalize(codec::CompressorCodec)
    zstream = codec.zstream
    if zstream.state != C_NULL
        code = deflate_end!(zstream)
        if code != Z_OK
            zerror(zstream, code)
        end
    end
    return
end
function TranscodingStreams.startproc(codec::CompressorCodec, state::Symbol, error::Error)
    code = deflate_reset!(codec.zstream)
    if code == Z_OK
        return :ok
    else
        error[] = ErrorException(zlib_error_message(codec.zstream, code))
        return :error
    end
end
function TranscodingStreams.process(codec::CompressorCodec, input::Memory, output::Memory, error::Error)
    zstream = codec.zstream
    zstream.next_in = input.ptr
    zstream.avail_in = input.size
    zstream.next_out = output.ptr
    zstream.avail_out = output.size
    code = deflate!(zstream, input.size > 0 ? Z_NO_FLUSH : Z_FINISH)
    Δin = Int(input.size - zstream.avail_in)
    Δout = Int(output.size - zstream.avail_out)
    if code == Z_OK
        return Δin, Δout, :ok
    elseif code == Z_STREAM_END
        return Δin, Δout, :end
    else
        error[] = ErrorException(zlib_error_message(zstream, code))
        return Δin, Δout, :error
    end
end