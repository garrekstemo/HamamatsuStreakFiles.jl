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
                stop = findnext(ch -> ch == ',' || ch == '[', comment, min(vstart, n))
                if stop === nothing || vstart > n
                    val = vstart > n ? "" : comment[vstart:n]
                    i = nextind(comment, n)
                else
                    val = comment[vstart:prevind(comment, stop)]
                    i = stop
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
