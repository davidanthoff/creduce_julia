import Base: @deprecate
@deprecate by(d::AbstractDataFrame, cols, s::Vector{Symbol}) aggregate(d, cols, map(eval, s))
@deprecate by(d::AbstractDataFrame, cols, s::Symbol) aggregate(d, cols, eval(s))
@deprecate nullable!(df::AbstractDataFrame, col::ColumnIndex) allowmissing!(df, col)
@deprecate nullable!(df::AbstractDataFrame, cols::Vector{<:ColumnIndex}) allowmissing!(df, cols)
@deprecate nullable!(colnames::Array{Symbol,1}, df::AbstractDataFrame) allowmissing!(df, colnames)
@deprecate nullable!(colnums::Array{Int,1}, df::AbstractDataFrame) allowmissing!(df, colnums)
import Base: keys, values, insert!
@deprecate keys(df::AbstractDataFrame) names(df)
@deprecate values(df::AbstractDataFrame) columns(df)
@deprecate insert!(df::DataFrame, df2::AbstractDataFrame) (foreach(col -> df[col] = df2[col], names(df2)); df)
@deprecate pool categorical
@deprecate pool! categorical!
@deprecate complete_cases! dropmissing!
@deprecate complete_cases completecases
@deprecate sub(df::AbstractDataFrame, rows) view(df, rows, :)
using CodecZlib, TranscodingStreams
export writetable
function writetable(filename::AbstractString,
                    df::AbstractDataFrame;
                    header::Bool = true,
                    separator::Char = getseparator(filename),
                    quotemark::Char = '"',
                    nastring::AbstractString = "NA",
                    append::Bool = false)
    Base.depwarn("writetable is deprecated, use CSV.write from the CSV package instead",
                 :writetable)
    if endswith(filename, ".bz") || endswith(filename, ".bz2")
        throw(ArgumentError("BZip2 compression not yet implemented"))
    end
    if append && isfile(filename) && filesize(filename) > 0
        file_df = readtable(filename, header = false, nrows = 1)
        if size(file_df, 2) != size(df, 2)
            throw(DimensionMismatch("Number of columns differ between file and DataFrame"))
        end
        if header
            if any(i -> Symbol(file_df[1, i]) != index(df)[i], 1:size(df, 2))
                throw(KeyError("Column names don't match names in file"))
            end
            header = false
        end
    end
    encoder = endswith(filename, ".gz") ? GzipCompressorStream : NoopStream
    open(encoder, filename, append ? "a" : "w") do io
        printtable(io,
                   df,
                   header = header,
                   separator = separator,
                   quotemark = quotemark,
                   nastring = nastring)
    end
    return
end
struct ParsedCSV
    bytes::Vector{UInt8} # Raw bytes from CSV file
    bounds::Vector{Int}  # Right field boundary indices
    lines::Vector{Int}   # Line break indices
    quoted::BitVector    # Was field quoted in text
end
struct ParseOptions{S <: String, T <: String}
    header::Bool
    separator::Char
    quotemarks::Vector{Char}
    decimal::Char
    nastrings::Vector{S}
    truestrings::Vector{T}
    falsestrings::Vector{T}
    makefactors::Bool
    names::Vector{Symbol}
    eltypes::Vector
    allowcomments::Bool
    commentmark::Char
    ignorepadding::Bool
    skipstart::Int
    skiprows::AbstractVector{Int}
    skipblanks::Bool
    encoding::Symbol
    allowescapes::Bool
    normalizenames::Bool
end
struct ParseType{ALLOWCOMMENTS, SKIPBLANKS, ALLOWESCAPES, SPC_SEP} end
ParseType(o::ParseOptions) = ParseType{o.allowcomments, o.skipblanks, o.allowescapes, o.separator == ' '}()
macro read_peek_eof(io, nextchr)
    io = esc(io)
    nextchr = esc(nextchr)
    quote
        nextnext = eof($io) ? 0xff : read($io, UInt8)
        $nextchr, nextnext, nextnext == 0xff
    end
end
macro skip_within_eol(io, chr, nextchr, endf)
    io = esc(io)
    chr = esc(chr)
    nextchr = esc(nextchr)
    endf = esc(endf)
    quote
        if $chr == UInt32('\r') && $nextchr == UInt32('\n')
            $chr, $nextchr, $endf = @read_peek_eof($io, $nextchr)
        end
    end
end
macro skip_to_eol(io, chr, nextchr, endf)
    io = esc(io)
    chr = esc(chr)
    nextchr = esc(nextchr)
    endf = esc(endf)
    quote
        while !$endf && !@atnewline($chr, $nextchr)
            $chr, $nextchr, $endf = @read_peek_eof($io, $nextchr)
        end
        @skip_within_eol($io, $chr, $nextchr, $endf)
    end
end
macro atnewline(chr, nextchr)
    chr = esc(chr)
    nextchr = esc(nextchr)
    quote
        $chr == UInt32('\n') || $chr == UInt32('\r')
    end
end
macro atblankline(chr, nextchr)
    chr = esc(chr)
    nextchr = esc(nextchr)
    quote
        ($chr == UInt32('\n') || $chr == UInt32('\r')) &&
        ($nextchr == UInt32('\n') || $nextchr == UInt32('\r'))
    end
end
macro atescape(chr, nextchr, quotemarks)
    chr = esc(chr)
    nextchr = esc(nextchr)
    quotemarks = esc(quotemarks)
    quote
        (UInt32($chr) == UInt32('\\') &&
            (UInt32($nextchr) == UInt32('\\') ||
                UInt32($nextchr) in $quotemarks)) ||
                    (UInt32($chr) == UInt32($nextchr) &&
                        UInt32($chr) in $quotemarks)
    end
end
macro atcescape(chr, nextchr)
    chr = esc(chr)
    nextchr = esc(nextchr)
    quote
        $chr == UInt32('\\') &&
        ($nextchr == UInt32('n') ||
         $nextchr == UInt32('t') ||
         $nextchr == UInt32('r') ||
         $nextchr == UInt32('a') ||
         $nextchr == UInt32('b') ||
         $nextchr == UInt32('f') ||
         $nextchr == UInt32('v') ||
         $nextchr == UInt32('\\'))
    end
end
macro mergechr(chr, nextchr)
    chr = esc(chr)
    nextchr = esc(nextchr)
    quote
        if $chr == UInt32('\\')
            if $nextchr == UInt32('n')
                '\n'
            elseif $nextchr == UInt32('t')
                '\t'
            elseif $nextchr == UInt32('r')
                '\r'
            elseif $nextchr == UInt32('a')
                '\a'
            elseif $nextchr == UInt32('b')
                '\b'
            elseif $nextchr == UInt32('f')
                '\f'
            elseif $nextchr == UInt32('v')
                '\v'
            elseif $nextchr == UInt32('\\')
                '\\'
            else
                msg = @sprintf("Invalid escape character '%s%s' encountered",
                               $chr,
                               $nextchr)
                error(msg)
            end
        else
            msg = @sprintf("Invalid escape character '%s%s' encountered",
                           $chr,
                           $nextchr)
            error(msg)
        end
    end
end
macro isspace(byte)
    byte = esc(byte)
    quote
        0x09 <= $byte <= 0x0d || $byte == 0x20
    end
end
macro push(count, a, val, l)
    count = esc(count) # Number of items in array
    a = esc(a)         # Array to update
    val = esc(val)     # Value to insert
    l = esc(l)         # Length of array
    quote
        $count += 1
        if $l < $count
            $l *= 2
            resize!($a, $l)
        end
        $a[$count] = $val
    end
end
function getseparator(filename::AbstractString)
    m = match(r"\.(\w+)(\.(gz|bz|bz2))?$", filename)
    ext = isa(m, RegexMatch) ? m.captures[1] : ""
    if ext == "csv"
        return ','
    elseif ext == "tsv"
        return '\t'
    elseif ext == "wsv"
        return ' '
    else
        return ','
    end
end
tf = (true, false)
for allowcomments in tf, skipblanks in tf, allowescapes in tf, wsv in tf
    dtype = ParseType{allowcomments, skipblanks, allowescapes, wsv}
    @eval begin
        function readnrows!(p::ParsedCSV,
                            io::IO,
                            nrows::Integer,
                            o::ParseOptions,
                            dispatcher::$(dtype),
                            firstchr::UInt8=0xff)
            n_bytes = 0
            n_bounds = 0
            n_lines = 0
            n_fields = 1
            l_bytes = length(p.bytes)
            l_lines = length(p.lines)
            l_bounds = length(p.bounds)
            l_quoted = length(p.quoted)
            in_quotes = false
            in_escape = false
            $(if allowcomments quote at_start = true end end)
            $(if wsv quote skip_white = true end end)
            chr = 0xff
            nextchr = (firstchr == 0xff && !eof(io)) ? read(io, UInt8) : firstchr
            endf = nextchr == 0xff
            quotemarks = convert(Vector{UInt8}, o.quotemarks)
            @push(n_bounds, p.bounds, 0, l_bounds)
            @push(n_bytes, p.bytes, '\n', l_bytes)
            @push(n_lines, p.lines, 0, l_lines)
            while !endf && ((nrows == -1) || (n_lines < nrows + 1))
                chr, nextchr, endf = @read_peek_eof(io, nextchr)
                $(if allowcomments
                    quote
                        if !in_quotes && chr == UInt32(o.commentmark)
                            @skip_to_eol(io, chr, nextchr, endf)
                            if at_start
                                continue
                            end
                        end
                    end
                end)
                $(if skipblanks
                    quote
                        if !in_quotes
                            while !endf && @atblankline(chr, nextchr)
                                chr, nextchr, endf = @read_peek_eof(io, nextchr)
                                @skip_within_eol(io, chr, nextchr, endf)
                            end
                        end
                    end
                end)
                $(if allowescapes
                    quote
                        if @atcescape(chr, nextchr) && !in_escape
                            chr = @mergechr(chr, nextchr)
                            nextchr = eof(io) ? 0xff : read(io, UInt8)
                            endf = nextchr == 0xff
                            in_escape = true
                        end
                    end
                end)
                $(if allowcomments quote at_start = false end end)
                if !in_quotes
                    if chr in quotemarks
                        in_quotes = true
                        p.quoted[n_fields] = true
                        $(if wsv quote skip_white = false end end)
                    elseif $(if wsv
                                quote chr == UInt32(' ') || chr == UInt32('\t') end
                            else
                                quote chr == UInt32(o.separator) end
                            end)
                        $(if wsv
                            quote
                                if !(nextchr in UInt32[' ', '\t', '\n', '\r']) && !skip_white
                                    @push(n_bounds, p.bounds, n_bytes, l_bounds)
                                    @push(n_bytes, p.bytes, '\n', l_bytes)
                                    @push(n_fields, p.quoted, false, l_quoted)
                                    skip_white = false
                                end
                            end
                        else
                            quote
                                @push(n_bounds, p.bounds, n_bytes, l_bounds)
                                @push(n_bytes, p.bytes, '\n', l_bytes)
                                @push(n_fields, p.quoted, false, l_quoted)
                            end
                        end)
                    elseif @atnewline(chr, nextchr)
                        @skip_within_eol(io, chr, nextchr, endf)
                        $(if allowcomments quote at_start = true end end)
                        @push(n_bounds, p.bounds, n_bytes, l_bounds)
                        @push(n_bytes, p.bytes, '\n', l_bytes)
                        @push(n_lines, p.lines, n_bytes, l_lines)
                        @push(n_fields, p.quoted, false, l_quoted)
                        $(if wsv quote skip_white = true end end)
                    else
                        @push(n_bytes, p.bytes, chr, l_bytes)
                        $(if wsv quote skip_white = false end end)
                    end
                else
                    if @atescape(chr, nextchr, quotemarks) && !in_escape
                        in_escape = true
                    else
                        if UInt32(chr) in quotemarks && !in_escape
                            in_quotes = false
                        else
                            @push(n_bytes, p.bytes, chr, l_bytes)
                        end
                        in_escape = false
                    end
                end
            end
            if endf && !@atnewline(chr, nextchr)
                @push(n_bounds, p.bounds, n_bytes, l_bounds)
                @push(n_bytes, p.bytes, '\n', l_bytes)
                @push(n_lines, p.lines, n_bytes, l_lines)
            end
            return n_bytes, n_bounds - 1, n_lines - 1, nextchr
        end
    end
end
function bytematch(bytes::Vector{UInt8},
                   left::Integer,
                   right::Integer,
                   exemplars::Vector{T}) where T <: String
    l = right - left + 1
    for index in 1:length(exemplars)
        exemplar = exemplars[index]
        if length(exemplar) == l
            matched = true
            for i in 0:(l - 1)
                matched &= bytes[left + i] == UInt32(exemplar[1 + i])
            end
            if matched
                return true
            end
        end
    end
    return false
end
function bytestotype(::Type{N},
                     bytes::Vector{UInt8},
                     left::Integer,
                     right::Integer,
                     nastrings::Vector{T},
                     wasquoted::Bool = false,
                     truestrings::Vector{P} = P[],
                     falsestrings::Vector{P} = P[]) where {N <: Integer,
                                                           T <: String,
                                                           P <: String}
    if left > right
        return 0, true, true
    end
    if bytematch(bytes, left, right, nastrings)
        return 0, true, true
    end
    value = 0
    power = 1
    index = right
    byte = bytes[index]
    while index > left
        if UInt32('0') <= byte <= UInt32('9')
            value += (byte - UInt8('0')) * power
            power *= 10
        else
            return value, false, false
        end
        index -= 1
        byte = bytes[index]
    end
    if byte == UInt32('-')
        return -value, left < right, false
    elseif byte == UInt32('+')
        return value, left < right, false
    elseif UInt32('0') <= byte <= UInt32('9')
        value += (byte - UInt8('0')) * power
        return value, true, false
    else
        return value, false, false
    end
end
let out = Vector{Float64}(undef, 1)
    global bytestotype
    function bytestotype(::Type{N},
                         bytes::Vector{UInt8},
                         left::Integer,
                         right::Integer,
                         nastrings::Vector{T},
                         wasquoted::Bool = false,
                         truestrings::Vector{P} = P[],
                         falsestrings::Vector{P} = P[]) where {N <: AbstractFloat,
                                                               T <: String,
                                                               P <: String}
        if left > right
            return 0.0, true, true
        end
        if bytematch(bytes, left, right, nastrings)
            return 0.0, true, true
        end
        wasparsed = ccall(:jl_substrtod,
                          Int32,
                          (Ptr{UInt8}, Csize_t, Int, Ptr{Float64}),
                          bytes,
                          convert(Csize_t, left - 1),
                          right - left + 1,
                          out) == 0
        return out[1], wasparsed, false
    end
end
function bytestotype(::Type{N},
                     bytes::Vector{UInt8},
                     left::Integer,
                     right::Integer,
                     nastrings::Vector{T},
                     wasquoted::Bool = false,
                     truestrings::Vector{P} = P[],
                     falsestrings::Vector{P} = P[]) where {N <: Bool,
                                                           T <: String,
                                                           P <: String}
    if left > right
        return false, true, true
    end
    if bytematch(bytes, left, right, nastrings)
        return false, true, true
    end
    if bytematch(bytes, left, right, truestrings)
        return true, true, false
    elseif bytematch(bytes, left, right, falsestrings)
        return false, true, false
    else
        return false, false, false
    end
end
function bytestotype(::Type{N},
                     bytes::Vector{UInt8},
                     left::Integer,
                     right::Integer,
                     nastrings::Vector{T},
                     wasquoted::Bool = false,
                     truestrings::Vector{P} = P[],
                     falsestrings::Vector{P} = P[]) where {N <: AbstractString,
                                                           T <: String,
                                                           P <: String}
    if left > right
        if wasquoted
            return "", true, false
        else
            return "", true, true
        end
    end
    if bytematch(bytes, left, right, nastrings)
        return "", true, true
    end
    return String(bytes[left:right]), true, false
end
function builddf(rows::Integer,
                 cols::Integer,
                 bytes::Integer,
                 fields::Integer,
                 p::ParsedCSV,
                 o::ParseOptions)
    columns = Vector{Any}(undef, cols)
    for j in 1:cols
        if isempty(o.eltypes)
            values = Vector{Int}(undef, rows)
        else
            values = Vector{o.eltypes[j]}(undef, rows)
        end
        msng = falses(rows)
        is_int = true
        is_float = true
        is_bool = true
        i = 0
        while i < rows
            i += 1
            left = p.bounds[(i - 1) * cols + j] + 2
            right = p.bounds[(i - 1) * cols + j + 1]
            wasquoted = p.quoted[(i - 1) * cols + j]
            if o.ignorepadding && !wasquoted
                while left < right && @isspace(p.bytes[left])
                    left += 1
                end
                while left <= right && @isspace(p.bytes[right])
                    right -= 1
                end
            end
            if !isempty(o.eltypes)
                values[i], wasparsed, msng[i] =
                    bytestotype(o.eltypes[j],
                                p.bytes,
                                left,
                                right,
                                o.nastrings,
                                wasquoted,
                                o.truestrings,
                                o.falsestrings)
                if wasparsed
                    continue
                else
                    error(@sprintf("Failed to parse '%s' using type '%s'",
                                   String(p.bytes[left:right]),
                                   o.eltypes[j]))
                end
            end
            if is_int
                values[i], wasparsed, msng[i] =
                  bytestotype(Int64,
                              p.bytes,
                              left,
                              right,
                              o.nastrings,
                              wasquoted,
                              o.truestrings,
                              o.falsestrings)
                if wasparsed
                    continue
                else
                    is_int = false
                    values = convert(Array{Float64}, values)
                end
            end
            if is_float
                values[i], wasparsed, msng[i] =
                  bytestotype(Float64,
                              p.bytes,
                              left,
                              right,
                              o.nastrings,
                              wasquoted,
                              o.truestrings,
                              o.falsestrings)
                if wasparsed
                    continue
                else
                    is_float = false
                    values = Vector{Bool}(undef, rows)
                    i = 0
                    continue
                end
            end
            if is_bool
                values[i], wasparsed, msng[i] =
                  bytestotype(Bool,
                              p.bytes,
                              left,
                              right,
                              o.nastrings,
                              wasquoted,
                              o.truestrings,
                              o.falsestrings)
                if wasparsed
                    continue
                else
                    is_bool = false
                    values = Vector{String}(undef, rows)
                    i = 0
                    continue
                end
            end
            values[i], wasparsed, msng[i] =
              bytestotype(String,
                          p.bytes,
                          left,
                          right,
                          o.nastrings,
                          wasquoted,
                          o.truestrings,
                          o.falsestrings)
        end
        vals = similar(values, Union{eltype(values), Missing})
        @inbounds for i in eachindex(vals)
            vals[i] = msng[i] ? missing : values[i]
        end
        if o.makefactors && !(is_int || is_float || is_bool)
            columns[j] = CategoricalArray{Union{eltype(values), Missing}}(vals)
        else
            columns[j] = vals
        end
    end
    if isempty(o.names)
        return DataFrame(columns, gennames(cols))
    else
        return DataFrame(columns, o.names)
    end
end
const RESERVED_WORDS = Set(["local", "global", "export", "let",
    "for", "struct", "while", "const", "continue", "import",
    "function", "if", "else", "try", "begin", "break", "catch",
    "return", "using", "baremodule", "macro", "finally",
    "module", "elseif", "end", "quote", "do"])
function identifier(s::AbstractString)
    s = Unicode.normalize(s)
    if !Base.isidentifier(s)
        s = makeidentifier(s)
    end
    Symbol(in(s, RESERVED_WORDS) ? "_"*s : s)
end
function makeidentifier(s::AbstractString)
    (iresult = iterate(s)) === nothing && return "x"
    res = IOBuffer(zeros(UInt8, sizeof(s)+1), write=true)
    (c, i) = iresult
    under = if Base.is_id_start_char(c)
        write(res, c)
        c == '_'
    elseif Base.is_id_char(c)
        write(res, 'x', c)
        false
    else
        write(res, '_')
        true
    end
    while (iresult = iterate(s, i)) !== nothing
        (c, i) = iresult
        if c != '_' && Base.is_id_char(c)
            write(res, c)
            under = false
        elseif !under
            write(res, '_')
            under = true
        end
    end
    return String(take!(res))
end
function parsenames!(names::Vector{Symbol},
                     ignorepadding::Bool,
                     bytes::Vector{UInt8},
                     bounds::Vector{Int},
                     quoted::BitVector,
                     fields::Int,
                     normalizenames::Bool)
    if fields == 0
        error("Header line was empty")
    end
    resize!(names, fields)
    for j in 1:fields
        left = bounds[j] + 2
        right = bounds[j + 1]
        if ignorepadding && !quoted[j]
            while left < right && @isspace(bytes[left])
                left += 1
            end
            while left <= right && @isspace(bytes[right])
                right -= 1
            end
        end
        name = String(bytes[left:right])
        if normalizenames
            name = identifier(name)
        end
        names[j] = name
    end
    return
end
function findcorruption(rows::Integer,
                        cols::Integer,
                        fields::Integer,
                        p::ParsedCSV)
    n = length(p.bounds)
    lengths = Vector{Int}(undef, rows)
    t = 1
    for i in 1:rows
        bound = p.lines[i + 1]
        f = 0
        while t <= n && p.bounds[t] < bound
            f += 1
            t += 1
        end
        lengths[i] = f
    end
    m = median(lengths)
    corruptrows = findall(lengths .!= m)
    l = corruptrows[1]
    error(@sprintf("Saw %d rows, %d columns and %d fields\n * Line %d has %d columns\n",
                   rows,
                   cols,
                   fields,
                   l,
                   lengths[l] + 1))
end
function readtable!(p::ParsedCSV,
                    io::IO,
                    nrows::Integer,
                    o::ParseOptions)
    chr, nextchr = 0xff, 0xff
    skipped_lines = 0
    if o.skipstart != 0
        while skipped_lines < o.skipstart
            chr, nextchr, endf = @read_peek_eof(io, nextchr)
            @skip_to_eol(io, chr, nextchr, endf)
            skipped_lines += 1
        end
    else
        chr, nextchr, endf = @read_peek_eof(io, nextchr)
    end
    if o.allowcomments || o.skipblanks
        while true
            if o.allowcomments && nextchr == UInt32(o.commentmark)
                chr, nextchr, endf = @read_peek_eof(io, nextchr)
                @skip_to_eol(io, chr, nextchr, endf)
            elseif o.skipblanks && @atnewline(nextchr, nextchr)
                chr, nextchr, endf = @read_peek_eof(io, nextchr)
                @skip_within_eol(io, chr, nextchr, endf)
            else
                break
            end
            skipped_lines += 1
        end
    end
    d = ParseType(o)
    if o.header
        bytes, fields, rows, nextchr = readnrows!(p, io, Int64(1), o, d, nextchr)
        if isempty(o.names)
            parsenames!(o.names, o.ignorepadding, p.bytes, p.bounds, p.quoted, fields, o.normalizenames)
        end
    end
    bytes, fields, rows, nextchr = readnrows!(p, io, Int64(nrows), o, d, nextchr)
    bytes != 0 || error("Failed to read any bytes.")
    rows != 0 || error("Failed to read any rows.")
    fields != 0 || error("Failed to read any fields.")
    cols = fld(fields, rows)
    if length(o.names) != cols && cols == 1 && rows == 1 && fields == 1 && bytes == 2
        fields = 0
        rows = 0
        cols = length(o.names)
    end
    if fields != rows * cols
        findcorruption(rows, cols, fields, p)
    end
    df = builddf(rows, cols, bytes, fields, p, o)
    return df
end
function readtable(io::IO,
                   nbytes::Integer = 1;
                   header::Bool = true,
                   separator::Char = ',',
                   quotemark::Vector{Char} = ['"'],
                   decimal::Char = '.',
                   nastrings::Vector = ["", "NA"],
                   truestrings::Vector = ["T", "t", "TRUE", "true"],
                   falsestrings::Vector = ["F", "f", "FALSE", "false"],
                   makefactors::Bool = false,
                   nrows::Integer = -1,
                   names::Vector = Symbol[],
                   eltypes::Vector = [],
                   allowcomments::Bool = false,
                   commentmark::Char = '#',
                   ignorepadding::Bool = true,
                   skipstart::Integer = 0,
                   skiprows::AbstractVector{Int} = Int[],
                   skipblanks::Bool = true,
                   encoding::Symbol = :utf8,
                   allowescapes::Bool = false,
                   normalizenames::Bool = true)
    if encoding != :utf8
        throw(ArgumentError("Argument 'encoding' only supports ':utf8' currently."))
    elseif !isempty(skiprows)
        throw(ArgumentError("Argument 'skiprows' is not yet supported."))
    elseif decimal != '.'
        throw(ArgumentError("Argument 'decimal' is not yet supported."))
    end
    if !isempty(eltypes)
        for j in 1:length(eltypes)
            if !(eltypes[j] in [String, Bool, Float64, Int64])
                throw(ArgumentError("Invalid eltype $(eltypes[j]) encountered.\nValid eltypes: $(String), Bool, Float64 or Int64"))
            end
        end
    end
    p = ParsedCSV(Vector{UInt8}(undef, nbytes),
                  Vector{Int}(undef, 1),
                  Vector{Int}(undef, 1),
                  BitArray(undef, 1))
    o = ParseOptions(header, separator, quotemark, decimal,
                     nastrings, truestrings, falsestrings,
                     makefactors, names, eltypes,
                     allowcomments, commentmark, ignorepadding,
                     skipstart, skiprows, skipblanks, encoding,
                     allowescapes, normalizenames)
    df = readtable!(p, io, nrows, o)
    close(io)
    return df
end
export readtable
function readtable(pathname::AbstractString;
                   header::Bool = true,
                   separator::Char = getseparator(pathname),
                   quotemark::Vector{Char} = ['"'],
                   decimal::Char = '.',
                   nastrings::Vector = String["", "NA"],
                   truestrings::Vector = String["T", "t", "TRUE", "true"],
                   falsestrings::Vector = String["F", "f", "FALSE", "false"],
                   makefactors::Bool = false,
                   nrows::Integer = -1,
                   names::Vector = Symbol[],
                   eltypes::Vector = [],
                   allowcomments::Bool = false,
                   commentmark::Char = '#',
                   ignorepadding::Bool = true,
                   skipstart::Integer = 0,
                   skiprows::AbstractVector{Int} = Int[],
                   skipblanks::Bool = true,
                   encoding::Symbol = :utf8,
                   allowescapes::Bool = false,
                   normalizenames::Bool = true)
    Base.depwarn("readtable is deprecated, use CSV.read from the CSV package instead",
                 :readtable)
    _r(io) = readtable(io,
                       nbytes,
                       header = header,
                       separator = separator,
                       quotemark = quotemark,
                       decimal = decimal,
                       nastrings = nastrings,
                       truestrings = truestrings,
                       falsestrings = falsestrings,
                       makefactors = makefactors,
                       nrows = nrows,
                       names = names,
                       eltypes = eltypes,
                       allowcomments = allowcomments,
                       commentmark = commentmark,
                       ignorepadding = ignorepadding,
                       skipstart = skipstart,
                       skiprows = skiprows,
                       skipblanks = skipblanks,
                       encoding = encoding,
                       allowescapes = allowescapes,
                       normalizenames = normalizenames)
    if startswith(pathname, "http://") || startswith(pathname, "ftp://")
        error("URL retrieval not yet implemented")
    elseif endswith(pathname, ".gz")
        nbytes = 2 * filesize(pathname)
        io = open(_r, GzipDecompressorStream, pathname, "r")
    elseif endswith(pathname, ".bz") || endswith(pathname, ".bz2")
        error("BZip2 decompression not yet implemented")
    else
        nbytes = filesize(pathname)
        io = open(_r, pathname, "r")
    end
end
inlinetable(s::AbstractString; args...) = readtable(IOBuffer(s); args...)
function inlinetable(s::AbstractString, flags::AbstractString; args...)
    flagbindings = Dict(
        'f' => (:makefactors, true),
        'c' => (:allowcomments, true),
        'H' => (:header, false) )
    for f in flags
        if haskey(flagbindings, f)
            push!(args, flagbindings[f])
        else
            throw(ArgumentError("Unknown inlinetable flag: $f"))
        end
    end
    readtable(IOBuffer(s); args...)
end
export @csv_str, @csv2_str, @tsv_str, @wsv_str
macro csv_str(s, flags...)
    Base.depwarn("@csv_str and the csv\"\"\" syntax are deprecated. " *
                 "Use CSV.read(IOBuffer(...)) from the CSV package instead.",
                 :csv_str)
    inlinetable(s, flags...; separator=',')
end
macro csv2_str(s, flags...)
    Base.depwarn("@csv2_str and the csv2\"\"\" syntax are deprecated. " *
                 "Use CSV.read(IOBuffer(...)) from the CSV package instead.",
                 :csv2_str)
    inlinetable(s, flags...; separator=';', decimal=',')
end
macro wsv_str(s, flags...)
    Base.depwarn("@wsv_str and the wsv\"\"\" syntax are deprecated. " *
                 "Use CSV.read(IOBuffer(...)) from the CSV package instead.",
                 :wsv_str)
    inlinetable(s, flags...; separator=' ')
end
macro tsv_str(s, flags...)
    Base.depwarn("@tsv_str and the tsv\"\"\" syntax are deprecated." *
                 "Use CSV.read(IOBuffer(...)) from the CSV package instead.",
                 :tsv_str)
    inlinetable(s, flags...; separator='\t')
end
@deprecate rename!(x::AbstractDataFrame, from::AbstractArray, to::AbstractArray) rename!(x, [f=>t for (f, t) in zip(from, to)])
@deprecate rename!(x::AbstractDataFrame, from::Symbol, to::Symbol) rename!(x, from => to)
@deprecate rename!(x::Index, f::Function) rename!(f, x)
@deprecate rename(x::AbstractDataFrame, from::AbstractArray, to::AbstractArray) rename(x, [f=>t for (f, t) in zip(from, to)])
@deprecate rename(x::AbstractDataFrame, from::Symbol, to::Symbol) rename(x, from => to)
@deprecate rename(x::Index, f::Function) rename(f, x)
import Base: vcat
@deprecate vcat(x::Vector{<:AbstractDataFrame}) vcat(x...)
@deprecate showcols(df::AbstractDataFrame, all::Bool=false, values::Bool=true) describe(df, stats = [:eltype, :nmissing, :first, :last])
@deprecate showcols(io::IO, df::AbstractDataFrame, all::Bool=false, values::Bool=true) show(io, describe(df, stats = [:eltype, :nmissing, :first, :last]), all)
import Base: show
@deprecate show(io::IO, df::AbstractDataFrame, allcols::Bool, rowlabel::Symbol, summary::Bool) show(io, df, allcols=allcols, rowlabel=rowlabel, summary=summary)
@deprecate show(io::IO, df::AbstractDataFrame, allcols::Bool, rowlabel::Symbol) show(io, df, allcols=allcols, rowlabel=rowlabel)
@deprecate show(io::IO, df::AbstractDataFrame, allcols::Bool) show(io, df, allcols=allcols)
@deprecate show(df::AbstractDataFrame, allcols::Bool, rowlabel::Symbol, summary::Bool) show(df, allcols=allcols, rowlabel=rowlabel, summary=summary)
@deprecate show(df::AbstractDataFrame, allcols::Bool, rowlabel::Symbol) show(df, allcols=allcols, rowlabel=rowlabel)
@deprecate show(df::AbstractDataFrame, allcols::Bool) show(df, allcols=allcols)
@deprecate showall(io::IO, df::AbstractDataFrame, allcols::Bool, rowlabel::Symbol, summary::Bool) show(io, df, allrows=true, allcols=allcols, rowlabel=rowlabel, summary=summary)
@deprecate showall(io::IO, df::AbstractDataFrame, allcols::Bool, rowlabel::Symbol) show(io, df, allrows=true, allcols=allcols, rowlabel=rowlabel)
@deprecate showall(io::IO, df::AbstractDataFrame, allcols::Bool = true) show(io, df, allrows=true, allcols=allcols)
@deprecate showall(df::AbstractDataFrame, allcols::Bool, rowlabel::Symbol, summary::Bool) show(df, allrows=true, allcols=allcols, rowlabel=rowlabel, summary=summary)
@deprecate showall(df::AbstractDataFrame, allcols::Bool, rowlabel::Symbol) show(df, allrows=true, allcols=allcols, rowlabel=rowlabel)
@deprecate showall(df::AbstractDataFrame, allcols::Bool = true) show(df, allrows=true, allcols=allcols)
@deprecate showall(io::IO, dfvec::AbstractVector{T}) where {T <: AbstractDataFrame} foreach(df->show(io, df, allrows=true, allcols=true), dfvec)
@deprecate showall(dfvec::AbstractVector{T}) where {T <: AbstractDataFrame} foreach(df->show(df, allrows=true, allcols=true), dfvec)
@deprecate showall(io::IO, df::GroupedDataFrame) show(io, df, allgroups=true)
@deprecate showall(df::GroupedDataFrame) show(df, allgroups=true)
import Base: delete!, insert!, merge!
@deprecate delete!(df::AbstractDataFrame, cols::Any) deletecols!(df, cols)
@deprecate insert!(df::DataFrame, col_ind::Int, item, name::Symbol; makeunique::Bool=false) insertcols!(df, col_ind, name => item; makeunique=makeunique)
@deprecate merge!(df1::DataFrame, df2::AbstractDataFrame) (foreach(col -> df1[col] = df2[col], names(df2)); df1)
import Base: setindex!
@deprecate setindex!(df::DataFrame, x::Nothing, col_ind::Int) deletecols!(df, col_ind)
import Base: map
@deprecate map(f::Function, sdf::SubDataFrame) f(sdf)
@deprecate map(f::Union{Function,Type}, dfc::DataFrameColumns{<:AbstractDataFrame, Pair{Symbol, AbstractVector}}) mapcols(f, dfc.df)
import Base: length
@deprecate length(df::AbstractDataFrame) size(df, 2)
@deprecate head(df::AbstractDataFrame) first(df, 6)
@deprecate tail(df::AbstractDataFrame) last(df, 6)
@deprecate head(df::AbstractDataFrame, n::Integer) first(df, n)
@deprecate tail(df::AbstractDataFrame, n::Integer) last(df, n)
import Base: convert
@deprecate convert(::Type{Array}, df::AbstractDataFrame) convert(Matrix, df)
@deprecate convert(::Type{Array{T}}, df::AbstractDataFrame) where {T} convert(Matrix{T}, df)
@deprecate convert(::Type{Array}, dfr::DataFrameRow) permutedims(Vector(dfr))
@deprecate DataFrameRow(df::AbstractDataFrame, row::Integer) DataFrameRow(df, row, :)
@deprecate SubDataFrame(df::AbstractDataFrame, rows::AbstractVector{<:Integer}) SubDataFrame(df, rows, :)
@deprecate SubDataFrame(df::AbstractDataFrame, ::Colon) SubDataFrame(df, :, :)
