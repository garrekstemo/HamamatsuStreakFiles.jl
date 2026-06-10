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

function _read_header(bytes::Vector{UInt8})
    length(bytes) >= 64 || throw(ArgumentError(
        "Hamamatsu .img: file too short for 64-byte header ($(length(bytes)) bytes)"))
    (bytes[1] == UInt8('I') && bytes[2] == UInt8('M')) || throw(ArgumentError(
        "Hamamatsu .img: bad magic (expected \"IM\")"))
    return ImgHeader(
        Int(_read_le(UInt16, bytes, 2)),
        Int(_read_le(UInt16, bytes, 4)),
        Int(_read_le(UInt16, bytes, 6)),
        Int(_read_le(UInt16, bytes, 8)),
        Int(_read_le(UInt16, bytes, 10)),
        Int(_read_le(UInt16, bytes, 12)),
    )
end
