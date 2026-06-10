using Test
using HamamatsuStreakFiles
using Dates
using Aqua

# Fixed comment size keeps embedded "#offset,count" scaling offsets deterministic.
const COMMENT_LEN = 512

# Build a synthetic Hamamatsu .img byte vector (spec §2). Defaults give a valid
# 4×3 UInt16 file with a descending-nm X table and ascending-ns Y table.
# X table offset = 64 + 512 + 24 = 600; Y table offset = 616.
# Pass xref/yref to override the Scaling*ScalingFile value (e.g. "Other",
# "missing.cal", "#999999,4"); comment to replace the whole INI block;
# truncate_at to cut the byte vector short.
function make_img(; width::Int=4, height::Int=3, type::Int=2,
                    magic::String="IM",
                    pixels::Union{Vector{<:Integer}, Nothing}=nothing,
                    xscale::Union{Vector{Float32}, Nothing}=Float32[700, 690, 680, 670],
                    yscale::Union{Vector{Float32}, Nothing}=Float32[0, 2, 4],
                    xref::Union{String, Nothing}=nothing,
                    yref::Union{String, Nothing}=nothing,
                    comment::Union{String, Nothing}=nothing,
                    truncate_at::Union{Int, Nothing}=nothing)
    T = type == 0 ? UInt8 : type == 3 ? UInt32 : UInt16
    px = something(pixels, collect(1:width*height))
    img = collect(reinterpret(UInt8, htol.(T.(px))))
    img_start = 64 + COMMENT_LEN
    xoff = img_start + length(img)
    yoff = xoff + (xscale === nothing ? 0 : 4 * length(xscale))
    xrefstr = something(xref, xscale === nothing ? "Other" : "#$xoff,$(length(xscale))")
    yrefstr = something(yref, yscale === nothing ? "Other" : "#$yoff,$(length(yscale))")
    default_comment =
        "[Application],Date=\"2026/06/02\",Time=\"13:17:16.967\",Software=\"HPD-TA\"" *
        "[Camera],CameraName=\"C11440-36U\"" *
        "[Acquisition],NrExposure=100,ExposureTime=14 ms,ZAxisLabel=Intensity," *
        "ZAxisUnit=Count,areSource=\"0,0,$width,$height\"" *
        "[Streak camera],DeviceName=\"C10910\",Time Range=\"50 ns\"" *
        "[Spectrograph],Wavelength=\"554.969\",Grating=\"50 g/mm\"" *
        "[Scaling],ScalingXType=2,ScalingXScale=1,ScalingXUnit=\"nm\"," *
        "ScalingXScalingFile=\"$xrefstr\",ScalingYType=2,ScalingYScale=1," *
        "ScalingYUnit=\"ns\",ScalingYScalingFile=\"$yrefstr\""
    c = something(comment, default_comment)
    length(c) <= COMMENT_LEN || error("test comment too long ($(length(c)) > $COMMENT_LEN)")
    hdr = zeros(UInt8, 64)
    hdr[1:length(magic)] = codeunits(magic)
    hdr[3:4] = reinterpret(UInt8, [htol(UInt16(COMMENT_LEN))])
    hdr[5:6] = reinterpret(UInt8, [htol(UInt16(width))])
    hdr[7:8] = reinterpret(UInt8, [htol(UInt16(height))])
    hdr[13:14] = reinterpret(UInt8, [htol(UInt16(type))])
    bytes = vcat(hdr, Vector{UInt8}(rpad(c, COMMENT_LEN, ' ')), img)
    xscale === nothing || append!(bytes, reinterpret(UInt8, htol.(xscale)))
    yscale === nothing || append!(bytes, reinterpret(UInt8, htol.(yscale)))
    truncate_at === nothing || (bytes = bytes[1:truncate_at])
    return bytes
end

write_img(bytes) = (path = tempname() * ".img"; write(path, bytes); path)

@testset "HamamatsuStreakFiles" begin

    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(HamamatsuStreakFiles; deps_compat = (check_extras = false,))
    end

    @testset "StreakImage type" begin
        s = StreakImage(
            [662.4, 500.0, 395.2],          # wavelength, descending (on-disk order)
            [0.0, 1.0],                      # time
            [1.0 4.0; 2.0 5.0; 3.0 6.0],     # counts (3 wavelength × 2 time)
            "nm", "ns", "Count",
            DateTime(2026, 6, 2, 13, 17, 16),
            "HPD-TA", "C11440-36U", "C10910", "50 ns",
            554.969, "50 g/mm", "14 ms", 47808,
            Dict("Application" => Dict("Software" => "HPD-TA")),
        )

        @test s isa AbstractStreakImage
        @test StreakImage <: AbstractStreakImage
        @test size(s) == (3, 2)
        @test s.counts[1, 2] == 4.0
        @test s.wavelength[1] > s.wavelength[end]   # descending order preserved

        compact = sprint(show, s)
        @test contains(compact, "StreakImage(3×2")
        @test contains(compact, "nm")
        @test contains(compact, "662.4–395.2")   # storage order, not sorted
        @test !contains(compact, '\n')

        full = sprint(show, MIME("text/plain"), s)
        @test contains(full, "StreakImage")
        @test contains(full, "C11440-36U")
        @test contains(full, "C10910")
        @test contains(full, "50 ns")
        @test contains(full, "554.969")
        @test contains(full, "50 g/mm")
        @test contains(full, "14 ms")
        @test contains(full, "47808")
        @test contains(full, "Acquired:")
        @test contains(full, "2026-06-02 13:17:16")

        # All-sentinel image: optional lines are suppressed, no year-0001 leak
        bare = StreakImage(Float64[], Float64[], zeros(0, 0),
                           "", "", "", DateTime(1),
                           "", "", "", "", 0.0, "", "", 0,
                           Dict{String, Dict{String, String}}())
        bare_show = sprint(show, MIME("text/plain"), bare)
        @test !contains(bare_show, "Acquired:")
        @test !contains(bare_show, "0001")
        @test !contains(bare_show, "Camera:")
        @test sprint(show, bare) == "StreakImage(0×0)"
    end

    @testset "binary header" begin
        b = make_img()
        hdr = HamamatsuStreakFiles._read_header(b)
        @test hdr.comment_len == COMMENT_LEN
        @test hdr.width == 4
        @test hdr.height == 3
        @test hdr.x_off == 0
        @test hdr.y_off == 0
        @test hdr.type == 2

        # fields are widened to Int (width*height must not overflow 16-bit)
        @test hdr.width isa Int
        @test hdr.height isa Int

        @test_throws ArgumentError HamamatsuStreakFiles._read_header(make_img(magic="XM"))
        @test_throws ArgumentError HamamatsuStreakFiles._read_header(make_img()[1:40])
    end

end
