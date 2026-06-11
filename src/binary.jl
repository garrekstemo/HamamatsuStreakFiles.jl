# Little-endian scalar read at 0-based byte offset `off`. Caller guarantees bounds.
function _read_le(::Type{T}, bytes::Vector{UInt8}, off::Integer) where {T}
    return ltoh(reinterpret(T, bytes[off+1:off+sizeof(T)])[1])
end

# Decoded 64-byte .img header (spec §2.1). All integer fields are stored as
# UInt16 LE on disk and widened to Int here: 16-bit width*height products
# overflow (1408*1072 = 1,509,376) — a RosettaSciIO-documented trap.
struct ImgHeader
    comment_len::Int
    width::Int
    height::Int
    x_off::Int
    y_off::Int
    type::Int
end

function _read_header(bytes::Vector{UInt8}, fname::AbstractString)
    length(bytes) >= 64 || throw(ArgumentError(
        "$fname: file too short for the 64-byte .img header ($(length(bytes)) bytes)"))
    (bytes[1] == UInt8('I') && bytes[2] == UInt8('M')) || throw(ArgumentError(
        "$fname: not a Hamamatsu .img file (bad magic; expected \"IM\")"))
    return ImgHeader(
        Int(_read_le(UInt16, bytes, 2)),
        Int(_read_le(UInt16, bytes, 4)),
        Int(_read_le(UInt16, bytes, 6)),
        Int(_read_le(UInt16, bytes, 8)),
        Int(_read_le(UInt16, bytes, 10)),
        Int(_read_le(UInt16, bytes, 12)),
    )
end

# Pixel dtype table for the .img header `type` field — the HPD-TA FileType
# enum: 0=UInt8, 1=compressed (unsupported, no open decompressor exists),
# 2=UInt16, 3=UInt32. There is no signed-int or Float32 *image* dtype; Float32
# appears only as the scaling-array element type. NOTE: this table must NOT be
# reused for .his files, whose dataType enum differs (1 means UInt8 there).
function _pixel_type(code::Int, fname::AbstractString)
    code == 0 && return UInt8
    code == 2 && return UInt16
    code == 3 && return UInt32
    code == 1 && throw(ArgumentError(
        "$fname: compressed .img image data (type=1) is not supported"))
    throw(ArgumentError("$fname: unknown .img pixel type code $code"))
end

# Read the pixel block into counts[wavelength, time] (Float64). The data is
# stored row-major with width (wavelength) as the fast axis, so filling a
# (width, height) matrix in Julia's column-major linear order is a direct copy.
function _read_image(bytes::Vector{UInt8}, hdr::ImgHeader, fname::AbstractString)
    T = _pixel_type(hdr.type, fname)
    npix = hdr.width * hdr.height
    start = 64 + hdr.comment_len
    nbytes = npix * sizeof(T)
    start + nbytes <= length(bytes) || throw(ArgumentError(
        "$fname: image data truncated (need $(start + nbytes) bytes, " *
        "file has $(length(bytes)))"))
    raw = reinterpret(T, bytes[start+1:start+nbytes])
    counts = Matrix{Float64}(undef, hdr.width, hdr.height)
    for i in eachindex(raw)
        counts[i] = Float64(ltoh(raw[i]))
    end
    return counts
end
