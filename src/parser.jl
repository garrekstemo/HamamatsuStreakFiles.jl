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
