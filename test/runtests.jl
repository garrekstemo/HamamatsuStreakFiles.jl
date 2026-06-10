using Test
using HamamatsuStreakFiles
using Dates
using Aqua
using Makie

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
        @test HamamatsuStreakFiles._read_header(make_img(magic="IM\0")).width == 4   # trailing NUL tolerated
    end

    @testset "image data" begin
        b = make_img()                      # pixels 1:12, width 4, height 3
        hdr = HamamatsuStreakFiles._read_header(b)
        counts = HamamatsuStreakFiles._read_image(b, hdr)
        @test counts isa Matrix{Float64}
        @test size(counts) == (4, 3)
        # width (wavelength) is the fast axis: first stored values fill column 1
        @test counts[:, 1] == [1.0, 2.0, 3.0, 4.0]
        @test counts[1, 2] == 5.0
        @test counts[4, 3] == 12.0

        # UInt8 (type=0) and UInt32 (type=3) pixel dtypes
        b8 = make_img(type=0)
        h8 = HamamatsuStreakFiles._read_header(b8)
        @test HamamatsuStreakFiles._read_image(b8, h8)[2, 1] == 2.0
        b32 = make_img(type=3, pixels=collect(70000:70011))
        h32 = HamamatsuStreakFiles._read_header(b32)
        @test HamamatsuStreakFiles._read_image(b32, h32)[1, 1] == 70000.0

        # compressed type=1 unsupported; unknown codes rejected
        @test_throws ArgumentError HamamatsuStreakFiles._pixel_type(1)
        @test_throws ArgumentError HamamatsuStreakFiles._pixel_type(7)

        # truncated image data
        bt = make_img(truncate_at = 64 + COMMENT_LEN + 5)
        @test_throws ArgumentError HamamatsuStreakFiles._read_image(
            bt, HamamatsuStreakFiles._read_header(bt))
    end

    @testset "INI comment parser" begin
        parse_comment = HamamatsuStreakFiles._parse_comment

        meta = parse_comment("[A],x=1,y=\"two, three\"[B],z=\"a=b[c]\",w=4")
        @test meta["A"]["x"] == "1"
        @test meta["A"]["y"] == "two, three"     # quoted comma preserved
        @test meta["B"]["z"] == "a=b[c]"         # quoted '=' and '[' preserved
        @test meta["B"]["w"] == "4"

        # butting sections after an unquoted value (real HPD-TA pattern:
        # "[Grabber],Type=5,SubType=0[DisplayLUT],EntrySize=4")
        meta2 = parse_comment("[Grabber],Type=5,SubType=0[DisplayLUT],EntrySize=4")
        @test meta2["Grabber"]["SubType"] == "0"
        @test meta2["DisplayLUT"]["EntrySize"] == "4"

        # keys with spaces; unquoted values with spaces
        meta3 = parse_comment("[Streak camera],Time Range=\"50 ns\",Mode=\"Operate\"" *
                              "[Acquisition],ExposureTime=14 ms,AcqMode=3")
        @test meta3["Streak camera"]["Time Range"] == "50 ns"
        @test meta3["Streak camera"]["Mode"] == "Operate"
        @test meta3["Acquisition"]["ExposureTime"] == "14 ms"
        @test meta3["Acquisition"]["AcqMode"] == "3"

        # lenient: CRLF, trailing padding/NULs, unterminated quote, empty input
        meta4 = parse_comment("[A],x=1,\r\n[B],y=\"unterminated")
        @test meta4["A"]["x"] == "1"
        @test meta4["B"]["y"] == "unterminated"
        @test parse_comment("[A],x=1" * " "^20 * "\0\0")["A"]["x"] == "1"
        @test parse_comment("") == Dict{String, Dict{String, String}}()

        # pairs before any section header are dropped, not a crash
        @test isempty(parse_comment("x=1,y=2"))

        # empty values (real HPD-TA emits e.g. ScalingXScalingFile= when undefined)
        meta5 = parse_comment("[A],x=,y=2")
        @test meta5["A"]["x"] == ""
        @test meta5["A"]["y"] == "2"
        @test parse_comment("[A],x=")["A"]["x"] == ""        # trailing '='
        @test parse_comment("[A],x=1[")["A"]["x"] == "1"     # truncated '[' at end
    end

    @testset "scaling resolution" begin
        b = make_img()
        D(pairs...) = Dict{String, String}(pairs...)
        R(scaling; n=4, dir=mktempdir()) =
            HamamatsuStreakFiles._resolve_axis(b, scaling, "X", n; dir)

        # embedded "#offset,count" table (descending values preserved)
        @test R(D("ScalingXType" => "2", "ScalingXUnit" => "nm",
                  "ScalingXScalingFile" => "#600,4")) ==
              ([700.0, 690.0, 680.0, 670.0], "nm")

        # type=1: linear from Scale/Offset — ScalingXScale is honored
        @test R(D("ScalingXType" => "1", "ScalingXScale" => "0.5",
                  "ScalingXOffset" => "100", "ScalingXUnit" => "nm")) ==
              ([100.0, 100.5, 101.0, 101.5], "nm")

        # scale absent or zero => pixel-index axis, unit "px"
        @test R(D("ScalingXType" => "1")) == ([0.0, 1.0, 2.0, 3.0], "px")
        @test R(D()) == ([0.0, 1.0, 2.0, 3.0], "px")

        # "Other" = uncalibrated; must be handled BEFORE any "#" int-parsing
        out = @test_logs (:warn, r"uncalibrated") match_mode = :any R(
            D("ScalingXType" => "2", "ScalingXScalingFile" => "Other",
              "ScalingXUnit" => "nm"))
        @test out == ([0.0, 1.0, 2.0, 3.0], "px")

        # out-of-bounds / malformed / count-mismatch embedded refs => warn + fallback
        @test_logs (:warn, r"out of bounds") match_mode = :any R(
            D("ScalingXType" => "2", "ScalingXScalingFile" => "#999999,4"))
        @test_logs (:warn, r"cannot parse") match_mode = :any R(
            D("ScalingXType" => "2", "ScalingXScalingFile" => "#abc"))
        @test_logs (:warn, r"does not match") match_mode = :any R(
            D("ScalingXType" => "2", "ScalingXScalingFile" => "#600,3"))
        @test_logs (:warn, r"out of bounds") match_mode = :any R(
            D("ScalingXType" => "2",
              "ScalingXScalingFile" => "#9223372036854775000,4"))

        # type=2 promised a table but no ref given => warn + fallback
        @test_logs (:warn, r"no Scaling") match_mode = :any R(D("ScalingXType" => "2"))

        # unknown ScalingXType => warn + linear (not an error)
        @test_logs (:warn, r"unknown") match_mode = :any R(D("ScalingXType" => "5"))

        # external sidecar: present and well-sized => used; missing or
        # wrong-sized => warn + fallback
        dir = mktempdir()
        write(joinpath(dir, "wl.cal"),
              collect(reinterpret(UInt8, htol.(Float32[1, 2, 3, 4]))))
        @test R(D("ScalingXType" => "2", "ScalingXScalingFile" => "wl.cal",
                  "ScalingXUnit" => "nm"); dir) == ([1.0, 2.0, 3.0, 4.0], "nm")
        @test_logs (:warn, r"not found") match_mode = :any R(
            D("ScalingXType" => "2", "ScalingXScalingFile" => "nope.cal"); dir)
        write(joinpath(dir, "bad.cal"), zeros(UInt8, 10))
        @test_logs (:warn, r"wrong size") match_mode = :any R(
            D("ScalingXType" => "2", "ScalingXScalingFile" => "bad.cal"); dir)
    end

    @testset "datetime parsing" begin
        P = HamamatsuStreakFiles._parse_datetime
        @test P("2026/06/02", "13:17:16.967") == DateTime(2026, 6, 2, 13, 17, 16)
        @test P("02.06.2026", "13:17:16") == DateTime(2026, 6, 2, 13, 17, 16)  # day-first
        @test P("2026/06/02", "") == DateTime(2026, 6, 2)
        @test P("", "13:17:16") == DateTime(1)
        @test P("garbage", "13:17:16") == DateTime(1)
        @test P("2026/13/40", "00:00:00") == DateTime(1)   # invalid fields, no throw
        @test P("26/06/02", "13:17:16") == DateTime(1)     # 2-digit year rejected
    end

    @testset "StreakImage(path) round-trip" begin
        path = write_img(make_img())
        s = StreakImage(path)

        @test size(s) == (4, 3)
        @test s.wavelength == [700.0, 690.0, 680.0, 670.0]   # descending preserved
        @test s.wavelength[1] > s.wavelength[end]
        @test s.time == [0.0, 2.0, 4.0]
        @test s.counts[:, 1] == [1.0, 2.0, 3.0, 4.0]          # axis/matrix alignment
        @test s.counts[1, 2] == 5.0
        @test s.xunits == "nm"
        @test s.yunits == "ns"
        @test s.zunits == "Count"
        @test s.date == DateTime(2026, 6, 2, 13, 17, 16)
        @test s.software == "HPD-TA"
        @test s.camera == "C11440-36U"
        @test s.streak_device == "C10910"
        @test s.time_range == "50 ns"
        @test s.center_wavelength == 554.969
        @test s.grating == "50 g/mm"
        @test s.exposure == "14 ms"
        @test s.n_exposures == 100
        @test s.metadata["Acquisition"]["areSource"] == "0,0,4,3"

        # AbstractString path arguments (SubString breaks String-typed signatures)
        sub = SubString(path, 1, length(path))
        @test StreakImage(sub).camera == "C11440-36U"

        # sentinels when metadata sections are absent
        bare = StreakImage(write_img(make_img(
            comment = "[Scaling],ScalingXType=1,ScalingYType=1")))
        @test bare.camera == ""
        @test bare.software == ""
        @test bare.date == DateTime(1)
        @test bare.n_exposures == 0
        @test bare.center_wavelength == 0.0
        @test bare.xunits == "px"
        @test bare.wavelength == [0.0, 1.0, 2.0, 3.0]

        # error paths surface from the lower layers
        @test_throws ArgumentError StreakImage(write_img(make_img(truncate_at = 100)))
        @test_throws ArgumentError StreakImage(write_img(make_img(magic = "XM")))
        @test_throws ArgumentError StreakImage(write_img(make_img(type = 1)))
        @test_throws SystemError StreakImage("this_file_does_not_exist.img")
    end

    @testset "Makie extension" begin
        s = StreakImage(write_img(make_img()))

        # convert_arguments flips display copies to ascending wavelength;
        # the struct itself keeps on-disk (descending) order
        @test Makie.convert_arguments(Makie.CellGrid(), s) ==
              Makie.convert_arguments(Makie.CellGrid(),
                                      reverse(s.wavelength), s.time,
                                      reverse(s.counts; dims=1))
        @test s.wavelength[1] > s.wavelength[end]   # struct untouched

        # heatmap(s) works end-to-end without touching fields
        fap = Makie.heatmap(s)
        @test fap isa Makie.FigureAxisPlot

        # plot defaults: unit-labelled axes
        fig, ax, hm = plot(s)
        @test fig isa Makie.Figure
        @test ax.xlabel[] == "Wavelength (nm)"
        @test ax.ylabel[] == "Time (ns)"

        # user axis NamedTuple overrides defaults
        _, ax2, _ = plot(s; axis = (ylabel = "Delay (ns)",))
        @test ax2.ylabel[] == "Delay (ns)"

        # ascending input passes through unflipped
        asc = StreakImage(write_img(make_img(xscale = Float32[400, 410, 420, 430])))
        @test Makie.convert_arguments(Makie.CellGrid(), asc) ==
              Makie.convert_arguments(Makie.CellGrid(),
                                      asc.wavelength, asc.time, asc.counts)
        @test plot(asc) isa Makie.FigureAxisPlot
    end

end
