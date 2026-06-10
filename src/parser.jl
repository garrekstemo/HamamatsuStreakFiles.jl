# Parse the .img INI-style comment into Dict{section => Dict{key => value}}.
# HPD-TA quirks (spec §2.2): [Section] blocks may butt together with no
# separator; values may be quoted, and quoted values may contain commas, '='
# and '['; unquoted values terminate at the next comma or '['. The comment may
# be truncated by the instrument (u16 length cap), so parse leniently — never
# throw on malformed input.
function _parse_comment(comment::AbstractString)
    sections = Dict{String, Dict{String, String}}()
    current = nothing
    i = firstindex(comment)
    n = lastindex(comment)
    while i <= n
        c = comment[i]
        if c == '['
            j = findnext(==(']'), comment, i)
            j === nothing && break
            name = comment[nextind(comment, i):prevind(comment, j)]
            current = get!(sections, String(name), Dict{String, String}())
            i = nextind(comment, j)
        elseif c == ',' || c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\0'
            i = nextind(comment, i)
        else
            eq = findnext(==('='), comment, i)
            eq === nothing && break
            key = strip(comment[i:prevind(comment, eq)])
            vstart = nextind(comment, eq)
            local val
            if vstart <= n && comment[vstart] == '"'
                closeq = findnext(==('"'), comment, nextind(comment, vstart))
                if closeq === nothing
                    val = comment[nextind(comment, vstart):n]
                    i = nextind(comment, n)
                else
                    val = comment[nextind(comment, vstart):prevind(comment, closeq)]
                    i = nextind(comment, closeq)
                end
            else
                if vstart > n
                    val = ""
                    i = nextind(comment, n)
                else
                    stop = findnext(ch -> ch == ',' || ch == '[', comment, vstart)
                    if stop === nothing
                        val = comment[vstart:n]
                        i = nextind(comment, n)
                    else
                        val = comment[vstart:prevind(comment, stop)]
                        i = stop
                    end
                end
            end
            if current !== nothing && !isempty(key)
                current[String(key)] =
                    String(rstrip(ch -> ch in (' ', '\r', '\n', '\0'), val))
            end
        end
    end
    return sections
end

# Linear/pixel fallback axis (spec §2.4 step 5):
# value[i] = ScalingNOffset + i * ScalingNScale, unit from ScalingNUnit.
# Degrades to a pixel-index axis with unit "px" when the scale is absent or 0.
function _linear_axis(scaling::Dict{String, String}, axis::String, n::Int)
    scale = something(tryparse(Float64, get(scaling, "Scaling$(axis)Scale", "")), 0.0)
    if scale == 0
        return collect(Float64, 0:n-1), "px"
    end
    offset = something(tryparse(Float64, get(scaling, "Scaling$(axis)Offset", "")), 0.0)
    return collect(offset .+ (0:n-1) .* scale), get(scaling, "Scaling$(axis)Unit", "")
end

# Resolve one calibration axis (spec §2.4). `axis` is "X" or "Y"; `n` is the
# pixel count (width or height); `dir` is the .img file's directory, used to
# locate external sidecar calibration files. Returns (values, unit).
# Resolution order: "Other"/empty sentinels before "#offset,count" parsing
# (int-parsing "Other" is a documented RosettaSciIO crash); embedded tables are
# bounds- and length-checked; every failure path warns and degrades to
# _linear_axis rather than throwing — the image itself is still valid.
function _resolve_axis(bytes::Vector{UInt8}, scaling::Dict{String, String},
                       axis::String, n::Int; dir::String = "")
    typecode = something(tryparse(Int, get(scaling, "Scaling$(axis)Type", "")), 0)
    ref = get(scaling, "Scaling$(axis)ScalingFile", "")
    unit = get(scaling, "Scaling$(axis)Unit", "")

    if typecode == 1
        return _linear_axis(scaling, axis, n)
    elseif typecode != 0 && typecode != 2
        @warn "Hamamatsu .img: unknown Scaling$(axis)Type $typecode; using linear axis"
        return _linear_axis(scaling, axis, n)
    end

    if isempty(ref)
        typecode == 2 && @warn "Hamamatsu .img: Scaling$(axis)Type=2 but no " *
            "Scaling$(axis)ScalingFile; using linear axis"
        return _linear_axis(scaling, axis, n)
    end

    if startswith(ref, "Other")
        @warn "Hamamatsu .img: uncalibrated $axis axis (ScalingFile=\"Other\"); " *
            "using linear axis"
        return _linear_axis(scaling, axis, n)
    end

    if startswith(ref, "#")
        parts = split(ref[2:end], ',')
        off = length(parts) == 2 ? tryparse(Int, parts[1]) : nothing
        cnt = length(parts) == 2 ? tryparse(Int, parts[2]) : nothing
        if off === nothing || cnt === nothing
            @warn "Hamamatsu .img: cannot parse scaling reference $(repr(ref)); " *
                "using linear axis"
        elseif cnt != n
            @warn "Hamamatsu .img: scaling array count $cnt does not match axis " *
                "length $n; using linear axis"
        elseif off < 0 || off > length(bytes) || off + 4cnt > length(bytes)
            @warn "Hamamatsu .img: scaling array out of bounds " *
                "(offset $off, count $cnt); using linear axis"
        else
            return Float64.(ltoh.(reinterpret(Float32, bytes[off+1:off+4cnt]))), unit
        end
        return _linear_axis(scaling, axis, n)
    end

    # ref comes from the file's comment block; absolute or ".." refs resolve
    # outside dir. Acceptable for a trusted-lab-file reader — read-only access.
    sidecar = joinpath(dir, ref)
    if isfile(sidecar)
        raw = read(sidecar)
        if length(raw) == 4n
            return Float64.(ltoh.(reinterpret(Float32, raw))), unit
        end
        @warn "Hamamatsu .img: external scaling file $(repr(ref)) has wrong size; " *
            "using linear axis"
    else
        @warn "Hamamatsu .img: external scaling file $(repr(ref)) not found; " *
            "using linear axis"
    end
    return _linear_axis(scaling, axis, n)
end

# Defensive [Application] Date/Time parsing. Separators vary by locale
# ('/' or '.') and the order may be day-first (DD/MM/YYYY) or year-first
# (YYYY/MM/DD); the 4-digit field is the year, the middle field is the month
# in both orders. Returns the DateTime(1) sentinel when unparseable — the raw
# strings always remain available in metadata["Application"].
function _parse_datetime(datestr::AbstractString, timestr::AbstractString)
    parts = split(replace(datestr, '.' => '/'), '/')
    length(parts) == 3 || return DateTime(1)
    nums = [tryparse(Int, p) for p in parts]
    any(isnothing, nums) && return DateTime(1)
    a, b, c = nums
    y, m, d = a > 999 ? (a, b, c) : (c, b, a)
    hms = match(r"^(\d+):(\d+):(\d+)", timestr)
    h, mi, sec = hms === nothing ? (0, 0, 0) :
        (parse(Int, hms[1]), parse(Int, hms[2]), parse(Int, hms[3]))
    try
        return DateTime(y, m, d, h, mi, sec)
    catch
        return DateTime(1)
    end
end

"""
    StreakImage(path::AbstractString) -> StreakImage

Read a Hamamatsu HPD-TA/HiPic `.img` (ITEX) streak-camera file.

Returns a [`StreakImage`](@ref) holding the wavelength axis (nm), time axis
(ns), the count matrix `counts[wavelength, time]` and the full instrument
metadata. Axis values come from the calibration tables embedded in the file;
on-disk axis order is preserved (HPD-TA commonly stores wavelength descending).
Uncalibrated or unresolvable axes degrade to a linear or pixel-index axis with
a warning.

# Throws
- `ArgumentError` for malformed files: bad magic, truncated header/comment/image,
  compressed (`type=1`) or unknown pixel type.
- `SystemError` if the file cannot be read from disk.

# Example
```julia
s = StreakImage("15K.img")
size(s)            # (1408, 1072)
s.wavelength       # 662.4 → 395.2 nm (descending, as stored)
s.counts[:, 1]     # spectrum at the first time bin
```
"""
function StreakImage(path::AbstractString)
    bytes = read(path)
    hdr = _read_header(bytes)
    64 + hdr.comment_len <= length(bytes) || throw(ArgumentError(
        "Hamamatsu .img: comment truncated (need $(64 + hdr.comment_len) bytes, " *
        "file has $(length(bytes)))"))
    meta = _parse_comment(String(bytes[65:64 + hdr.comment_len]))
    counts = _read_image(bytes, hdr)

    scaling = get(meta, "Scaling", Dict{String, String}())
    dir = dirname(abspath(path))
    wavelength, xunits = _resolve_axis(bytes, scaling, "X", hdr.width; dir)
    time, yunits = _resolve_axis(bytes, scaling, "Y", hdr.height; dir)

    app = get(meta, "Application", Dict{String, String}())
    acq = get(meta, "Acquisition", Dict{String, String}())
    cam = get(meta, "Camera", Dict{String, String}())
    streak = get(meta, "Streak camera", Dict{String, String}())
    spectro = get(meta, "Spectrograph", Dict{String, String}())

    return StreakImage(
        wavelength, time, counts,
        xunits, yunits, get(acq, "ZAxisUnit", ""),
        _parse_datetime(get(app, "Date", ""), get(app, "Time", "")),
        get(app, "Software", ""),
        get(cam, "CameraName", ""),
        get(streak, "DeviceName", ""),
        get(streak, "Time Range", ""),
        something(tryparse(Float64, get(spectro, "Wavelength", "")), 0.0),
        get(spectro, "Grating", ""),
        get(acq, "ExposureTime", ""),
        something(tryparse(Int, get(acq, "NrExposure", "")), 0),
        meta,
    )
end
