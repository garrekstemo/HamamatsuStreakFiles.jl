# HamamatsuStreakFiles.jl Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement HamamatsuStreakFiles.jl — a standalone Julia reader for Hamamatsu HPD-TA/HiPic `.img` streak-camera files, per the approved spec at `docs/superpowers/specs/2026-06-09-hamamatsu-img-reader-design.md`.

**Architecture:** Binary layer (`binary.jl`: little-endian readers, 64-byte header, pixel block) → comment layer (`parser.jl`: quote-aware INI parser, scaling-axis resolution, `StreakImage(path)` orchestration) → typed result (`types.jl`: `StreakImage <: AbstractStreakImage`). Makie quick-look plotting lives behind a weak dependency in `ext/`. Tests use a synthetic byte-builder (`make_img`/`write_img`) — no large real fixture is committed.

**Tech Stack:** Julia ≥ 1.10. `[deps]`: Dates only. `[weakdeps]`: Makie. Tests: Test + Aqua + Makie.

**Working directory for ALL commands:** `/Users/garrek/Developer/HamamatsuStreakFiles.jl` (the package root; repo already exists with the spec committed on `main`).

**Run tests with:** `julia --project=. -e 'using Pkg; Pkg.test()'`

**Conventions (from spec + user's global CLAUDE.md):**
- No `##` comments (reserved by VS Code Julia extension).
- `eachindex(arr)` over `1:length(arr)`; `something(a, default)` over ternary-nothing checks.
- Internal (unexported) functions are underscore-prefixed (`_read_header`), matching JASCOFiles/RigakuFiles.
- Sentinels for missing metadata: `String → ""`, `Float64 → 0.0`, `Int → 0`, `DateTime → DateTime(1)`.
- Never edit Manifest.toml; it is gitignored.

## File structure

| File | Responsibility |
|---|---|
| `Project.toml` | Package metadata; Dates dep; Makie weakdep + extension (added in Task 8) |
| `src/HamamatsuStreakFiles.jl` | Module: `using Dates`, includes, exports |
| `src/types.jl` | `AbstractStreakImage`, `StreakImage`, `Base.show` (2 methods), `Base.size` |
| `src/binary.jl` | `_read_le`, `ImgHeader`, `_read_header`, `_pixel_type`, `_read_image` |
| `src/parser.jl` | `_parse_comment`, `_linear_axis`, `_resolve_axis`, `_parse_datetime`, `StreakImage(path)` |
| `ext/HamamatsuStreakFilesMakieExt.jl` | `Makie.convert_arguments` (CellGrid) + `Makie.plot(::StreakImage)` heatmap |
| `test/runtests.jl` | `make_img`/`write_img` synthetic builder + all testsets + Aqua |
| `.github/workflows/CI.yml`, `TagBot.yml`, `.github/dependabot.yml` | CI per JASCOFiles-canonical layout (docs job omitted — Documenter deferred) |
| `README.md`, `LICENSE` | Repo finishing |

Format reference (byte layout, dtype table, scaling resolution rules) is the spec §2 — keep it open while implementing. Real-file ground truth for Task 9: `/Users/garrek/Developer/QPSTools.jl/data/PL/15K.img`.

---

### Task 1: Package scaffold

**Files:**
- Create: `Project.toml`
- Create: `src/HamamatsuStreakFiles.jl`
- Create: `test/runtests.jl`
- Create: `LICENSE`

- [ ] **Step 1: Generate a UUID for the package**

Run: `julia -e 'using UUIDs; println(uuid4())'`
Expected: a UUID string. Use it as `<UUID>` in the next step.

- [ ] **Step 2: Create `Project.toml`**

```toml
name = "HamamatsuStreakFiles"
uuid = "<UUID>"
authors = ["Garrek Stemo <8449000+garrekstemo@users.noreply.github.com>"]
version = "0.1.0"

[deps]
Dates = "ade2ca70-3891-5945-98fb-dc099432e06a"

[compat]
Aqua = "0.8"
Dates = "1"
julia = "1.10"

[extras]
Aqua = "4c88cf16-eb10-579e-8560-4a9242c79595"
Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[targets]
test = ["Aqua", "Test"]
```

- [ ] **Step 3: Create `src/HamamatsuStreakFiles.jl`** (includes are added by later tasks)

```julia
module HamamatsuStreakFiles

using Dates

export AbstractStreakImage, StreakImage

end # module
```

- [ ] **Step 4: Create `test/runtests.jl`**

```julia
using Test
using HamamatsuStreakFiles
using Dates
using Aqua

@testset "HamamatsuStreakFiles" begin

    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(HamamatsuStreakFiles; deps_compat = (check_extras = false,))
    end

end
```

- [ ] **Step 5: Create `LICENSE`** — MIT, copy the text from `/Users/garrek/Developer/RigakuFiles.jl/LICENSE` verbatim (same author/holder: Garrek Stemo). Update the year to 2026 if it differs.

- [ ] **Step 6: Run tests**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: PASS (Aqua only).

- [ ] **Step 7: Commit**

```bash
git add Project.toml src/HamamatsuStreakFiles.jl test/runtests.jl LICENSE
git commit -m "feat: package scaffold with Aqua test harness"
```

---

### Task 2: `StreakImage` type, show methods, size

**Files:**
- Create: `src/types.jl`
- Modify: `src/HamamatsuStreakFiles.jl` (add include)
- Modify: `test/runtests.jl` (add testset)

- [ ] **Step 1: Write the failing tests** — insert this testset in `test/runtests.jl` immediately after the Aqua testset (inside the outer `@testset`):

```julia
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
```

- [ ] **Step 2: Run tests to verify failure**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: FAIL/ERROR — `StreakImage` constructor with 16 arguments is undefined.

- [ ] **Step 3: Create `src/types.jl`**

```julia
"""
    AbstractStreakImage

Abstract supertype for Hamamatsu streak-camera images.
"""
abstract type AbstractStreakImage end

"""
    StreakImage <: AbstractStreakImage

A Hamamatsu HPD-TA/HiPic `.img` streak-camera image: wavelength × time → counts,
plus instrument metadata. Construct with `StreakImage(path)`.

# Fields
- `wavelength::Vector{Float64}` — spectral axis (typically nm). On-disk order is
  preserved; HPD-TA commonly stores wavelength descending (red → blue).
- `time::Vector{Float64}` — temporal axis (typically ns).
- `counts::Matrix{Float64}` — size `(length(wavelength), length(time))`;
  `counts[i, j]` is the signal at `wavelength[i]`, `time[j]`.
- `xunits::String`, `yunits::String`, `zunits::String` — axis unit labels
  (e.g. `"nm"`, `"ns"`, `"Count"`).
- `date::DateTime` — acquisition timestamp (`[Application]` Date + Time).
- `software::String` — acquisition software (`[Application]` Software), e.g. `"HPD-TA"`.
- `camera::String` — readout camera model (`[Camera]` CameraName).
- `streak_device::String` — streak unit model (`[Streak camera]` DeviceName).
- `time_range::String` — sweep window, raw token incl. unit (`[Streak camera]`
  "Time Range"), e.g. `"50 ns"`.
- `center_wavelength::Float64` — spectrograph center wavelength in nm
  (`[Spectrograph]` Wavelength).
- `grating::String` — spectrograph grating (`[Spectrograph]` Grating).
- `exposure::String` — exposure time, raw token incl. unit (`[Acquisition]`
  ExposureTime), e.g. `"14 ms"`.
- `n_exposures::Int` — accumulated exposure count (`[Acquisition]` NrExposure).
- `metadata::Dict{String, Dict{String, String}}` — the full raw comment block,
  keyed by `[Section]` name, then key.

# Sentinels for missing fields

| Field type | Sentinel |
|------------|----------|
| `String`   | `""` |
| `Float64`  | `0.0` |
| `Int`      | `0` |
| `DateTime` | `DateTime(1)` (year 0001) |

For strict "present vs. missing" checks, inspect the raw `metadata` dict.
"""
struct StreakImage <: AbstractStreakImage
    wavelength::Vector{Float64}
    time::Vector{Float64}
    counts::Matrix{Float64}
    xunits::String
    yunits::String
    zunits::String
    date::DateTime
    software::String
    camera::String
    streak_device::String
    time_range::String
    center_wavelength::Float64
    grating::String
    exposure::String
    n_exposures::Int
    metadata::Dict{String, Dict{String, String}}
end

Base.size(s::AbstractStreakImage) = size(s.counts)

function Base.show(io::IO, s::StreakImage)
    print(io, "StreakImage(", length(s.wavelength), "×", length(s.time))
    if !isempty(s.wavelength)
        lo, hi = extrema((s.wavelength[1], s.wavelength[end]))
        print(io, ", ", round(lo, digits=1), "–", round(hi, digits=1), " ", s.xunits)
    end
    if !isempty(s.time)
        print(io, ", ", round(s.time[1], digits=2), "–",
              round(s.time[end], digits=2), " ", s.yunits)
    end
    print(io, ")")
end

function Base.show(io::IO, ::MIME"text/plain", s::StreakImage)
    println(io, "StreakImage")
    println(io, "  Size:         ", length(s.wavelength), " wavelength × ",
            length(s.time), " time")
    if !isempty(s.wavelength)
        println(io, "  Wavelength:   ", round(s.wavelength[1], digits=2), " – ",
                round(s.wavelength[end], digits=2), " ", s.xunits)
    end
    if !isempty(s.time)
        println(io, "  Time:         ", round(s.time[1], digits=3), " – ",
                round(s.time[end], digits=3), " ", s.yunits)
    end
    !isempty(s.camera) && println(io, "  Camera:       ", s.camera)
    !isempty(s.streak_device) && println(io, "  Streak unit:  ", s.streak_device)
    !isempty(s.time_range) && println(io, "  Time range:   ", s.time_range)
    if s.center_wavelength > 0
        println(io, "  Spectrograph: ", s.center_wavelength, " nm center",
                isempty(s.grating) ? "" : ", " * s.grating)
    end
    if !isempty(s.exposure)
        println(io, "  Exposure:     ", s.exposure,
                s.n_exposures > 0 ? " × " * string(s.n_exposures) : "")
    end
    if s.date != DateTime(1)
        println(io, "  Acquired:     ", Dates.format(s.date, "yyyy-mm-dd HH:MM:SS"))
    end
    print(io, "  Metadata:     ", length(s.metadata), " sections")
end
```

- [ ] **Step 4: Add the include to `src/HamamatsuStreakFiles.jl`** — after the `export` line:

```julia
include("types.jl")
```

- [ ] **Step 5: Run tests to verify pass**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/types.jl src/HamamatsuStreakFiles.jl test/runtests.jl
git commit -m "feat: StreakImage type with show methods and sentinels"
```

---

### Task 3: Binary header reading + synthetic test builder

**Files:**
- Create: `src/binary.jl`
- Modify: `src/HamamatsuStreakFiles.jl` (add include)
- Modify: `test/runtests.jl` (add builder + testset)

- [ ] **Step 1: Add the synthetic `.img` builder to `test/runtests.jl`** — insert after `using Aqua`, BEFORE the outer `@testset`:

```julia
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
```

- [ ] **Step 2: Write the failing testset** — insert inside the outer `@testset`, after the "StreakImage type" testset:

```julia
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
```

- [ ] **Step 3: Run tests to verify failure**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: FAIL/ERROR — `_read_header` not defined.

- [ ] **Step 4: Create `src/binary.jl`**

```julia
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
```

- [ ] **Step 5: Add the include to `src/HamamatsuStreakFiles.jl`** — after `include("types.jl")`:

```julia
include("binary.jl")
```

- [ ] **Step 6: Run tests to verify pass**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/binary.jl src/HamamatsuStreakFiles.jl test/runtests.jl
git commit -m "feat: .img header reader with synthetic test builder"
```

---

### Task 4: Pixel dtype table + image block reading

**Files:**
- Modify: `src/binary.jl` (append)
- Modify: `test/runtests.jl` (add testset)

- [ ] **Step 1: Write the failing testset** — insert after the "binary header" testset:

```julia
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
```

- [ ] **Step 2: Run tests to verify failure**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: FAIL/ERROR — `_read_image` / `_pixel_type` not defined.

- [ ] **Step 3: Append to `src/binary.jl`**

```julia
# Pixel dtype table for the .img header `type` field — the HPD-TA FileType
# enum: 0=UInt8, 1=compressed (unsupported, no open decompressor exists),
# 2=UInt16, 3=UInt32. There is no signed-int or Float32 *image* dtype; Float32
# appears only as the scaling-array element type. NOTE: this table must NOT be
# reused for .his files, whose dataType enum differs (1 means UInt8 there).
function _pixel_type(code::Int)
    code == 0 && return UInt8
    code == 2 && return UInt16
    code == 3 && return UInt32
    code == 1 && throw(ArgumentError(
        "Hamamatsu .img: compressed image data (type=1) is not supported"))
    throw(ArgumentError("Hamamatsu .img: unknown pixel type code $code"))
end

# Read the pixel block into counts[wavelength, time] (Float64). The data is
# stored row-major with width (wavelength) as the fast axis, so filling a
# (width, height) matrix in Julia's column-major linear order is a direct copy.
function _read_image(bytes::Vector{UInt8}, hdr::ImgHeader)
    T = _pixel_type(hdr.type)
    npix = hdr.width * hdr.height
    start = 64 + hdr.comment_len
    nbytes = npix * sizeof(T)
    start + nbytes <= length(bytes) || throw(ArgumentError(
        "Hamamatsu .img: image data truncated (need $(start + nbytes) bytes, " *
        "file has $(length(bytes)))"))
    raw = reinterpret(T, bytes[start+1:start+nbytes])
    counts = Matrix{Float64}(undef, hdr.width, hdr.height)
    for i in eachindex(raw)
        counts[i] = Float64(ltoh(raw[i]))
    end
    return counts
end
```

- [ ] **Step 4: Run tests to verify pass**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/binary.jl test/runtests.jl
git commit -m "feat: pixel dtype table and image block reader"
```

---

### Task 5: Quote-aware INI comment parser

**Files:**
- Create: `src/parser.jl`
- Modify: `src/HamamatsuStreakFiles.jl` (add include)
- Modify: `test/runtests.jl` (add testset)

- [ ] **Step 1: Write the failing testset** — insert after the "image data" testset:

```julia
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
    end
```

- [ ] **Step 2: Run tests to verify failure**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: FAIL/ERROR — `_parse_comment` not defined.

- [ ] **Step 3: Create `src/parser.jl`**

```julia
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
```

- [ ] **Step 4: Add the include to `src/HamamatsuStreakFiles.jl`** — after `include("binary.jl")`:

```julia
include("parser.jl")
```

- [ ] **Step 5: Run tests to verify pass**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/parser.jl src/HamamatsuStreakFiles.jl test/runtests.jl
git commit -m "feat: quote-aware INI comment parser"
```

---

### Task 6: Scaling-axis resolution

**Files:**
- Modify: `src/parser.jl` (append)
- Modify: `test/runtests.jl` (add testset)

- [ ] **Step 1: Write the failing testset** — insert after the "INI comment parser" testset. Note: with `make_img()` defaults the X table lives at absolute offset 600 (= 64 + 512 + 24) and holds 4 Float32s.

```julia
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
```

- [ ] **Step 2: Run tests to verify failure**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: FAIL/ERROR — `_resolve_axis` not defined.

- [ ] **Step 3: Append to `src/parser.jl`**

```julia
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
        elseif off < 0 || off + 4cnt > length(bytes)
            @warn "Hamamatsu .img: scaling array out of bounds " *
                "(offset $off, count $cnt); using linear axis"
        elseif cnt != n
            @warn "Hamamatsu .img: scaling array count $cnt does not match axis " *
                "length $n; using linear axis"
        else
            return Float64.(ltoh.(reinterpret(Float32, bytes[off+1:off+4cnt]))), unit
        end
        return _linear_axis(scaling, axis, n)
    end

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
```

- [ ] **Step 4: Run tests to verify pass**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/parser.jl test/runtests.jl
git commit -m "feat: scaling-axis resolution with Other/external/linear fallbacks"
```

---

### Task 7: Defensive date parsing + `StreakImage(path)` loader

**Files:**
- Modify: `src/parser.jl` (append)
- Modify: `test/runtests.jl` (add two testsets)

- [ ] **Step 1: Write the failing testsets** — insert after the "scaling resolution" testset:

```julia
    @testset "datetime parsing" begin
        P = HamamatsuStreakFiles._parse_datetime
        @test P("2026/06/02", "13:17:16.967") == DateTime(2026, 6, 2, 13, 17, 16)
        @test P("02.06.2026", "13:17:16") == DateTime(2026, 6, 2, 13, 17, 16)  # day-first
        @test P("2026/06/02", "") == DateTime(2026, 6, 2)
        @test P("", "13:17:16") == DateTime(1)
        @test P("garbage", "13:17:16") == DateTime(1)
        @test P("2026/13/40", "00:00:00") == DateTime(1)   # invalid fields, no throw
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
```

- [ ] **Step 2: Run tests to verify failure**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: FAIL/ERROR — `_parse_datetime` and `StreakImage(::String)` not defined.

- [ ] **Step 3: Append to `src/parser.jl`**

```julia
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
```

- [ ] **Step 4: Run tests to verify pass**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: PASS — full synthetic round-trip green.

- [ ] **Step 5: Commit**

```bash
git add src/parser.jl test/runtests.jl
git commit -m "feat: StreakImage(path) loader with defensive date parsing"
```

---

### Task 8: Makie weakdep extension

**Files:**
- Modify: `Project.toml` (weakdeps/extensions/compat/extras/targets)
- Create: `ext/HamamatsuStreakFilesMakieExt.jl`
- Modify: `test/runtests.jl` (add `using Makie` + testset)

- [ ] **Step 1: Update `Project.toml`** — add the four sections/entries (keep existing content; `[compat]` keys stay alphabetized):

```toml
[weakdeps]
Makie = "ee78f7c6-11fb-53f2-987a-cfe4a2b5a57a"

[extensions]
HamamatsuStreakFilesMakieExt = "Makie"

[compat]
Aqua = "0.8"
Dates = "1"
Makie = "0.20, 0.21, 0.22, 0.23, 0.24"
julia = "1.10"

[extras]
Aqua = "4c88cf16-eb10-579e-8560-4a9242c79595"
Makie = "ee78f7c6-11fb-53f2-987a-cfe4a2b5a57a"
Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[targets]
test = ["Aqua", "Makie", "Test"]
```

- [ ] **Step 2: Write the failing testset** — add `using Makie` to the imports at the top of `test/runtests.jl`, then insert after the "StreakImage(path) round-trip" testset:

```julia
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
```

- [ ] **Step 3: Run tests to verify failure**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: FAIL/ERROR — no `convert_arguments` method for `StreakImage` (extension file doesn't exist yet).

- [ ] **Step 4: Create `ext/HamamatsuStreakFilesMakieExt.jl`**

```julia
module HamamatsuStreakFilesMakieExt

using HamamatsuStreakFiles
using Makie

# Display copy in ascending-wavelength order. The struct preserves on-disk
# (often descending) order, so flip the axis and the matrix together; Makie's
# heatmap requires sorted axis vectors.
function _ascending(s::StreakImage)
    if length(s.wavelength) >= 2 && s.wavelength[1] > s.wavelength[end]
        return reverse(s.wavelength), reverse(s.counts; dims=1)
    end
    return s.wavelength, s.counts
end

_label(name, unit) = isempty(unit) ? name : string(name, " (", unit, ")")

# Enable `heatmap(s)`, `heatmap!(ax, s)`, `contourf(s)`, etc. CellGrid is the
# conversion-trait singleton for heatmap-like plots.
function Makie.convert_arguments(t::Makie.CellGrid, s::StreakImage)
    x, z = _ascending(s)
    return Makie.convert_arguments(t, x, s.time, z)
end

"""
    plot(s::StreakImage; axis=NamedTuple(), kwargs...)

Quick-look heatmap of a streak image: wavelength (ascending) vs. time, colored
by counts. Available when Makie is loaded; load a backend (`using CairoMakie`
or `using GLMakie`) first. Returns a `FigureAxisPlot` that destructures into
`(figure, axis, plot)`.

Axis defaults: `xlabel = "Wavelength (<xunits>)"`, `ylabel = "Time (<yunits>)"`.
Pass an `axis` NamedTuple to override; extra keyword arguments are forwarded to
`Makie.heatmap` (e.g. `colormap`, `colorrange`).

```julia
using HamamatsuStreakFiles, GLMakie

s = StreakImage("15K.img")
fig, ax, hm = plot(s)
fig, ax, hm = plot(s; colormap = :inferno)
```
"""
function Makie.plot(s::StreakImage; axis::NamedTuple = NamedTuple(), kwargs...)
    x, z = _ascending(s)
    default_axis = (
        xlabel = _label("Wavelength", s.xunits),
        ylabel = _label("Time", s.yunits),
    )
    return Makie.heatmap(x, s.time, z;
        axis = merge(default_axis, axis),
        kwargs...,
    )
end

end # module
```

- [ ] **Step 5: Run tests to verify pass**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: PASS (Pkg resolves Makie into the test env via the test target).

- [ ] **Step 6: Commit**

```bash
git add Project.toml ext/HamamatsuStreakFilesMakieExt.jl test/runtests.jl
git commit -m "feat: Makie weakdep extension with quick-look heatmap"
```

---

### Task 9: Real-file verification gate (no commit)

Verify the reader against the real instrument file decoded during design. This
is a manual gate — the 3 MB file is NOT committed; nothing in the repo changes.

**Files:** none (read-only verification)

- [ ] **Step 1: Run the loader against the real file with the ground-truth assertions**

Run:

```bash
julia --project=. -e '
using HamamatsuStreakFiles, Dates
s = StreakImage("/Users/garrek/Developer/QPSTools.jl/data/PL/15K.img")
@assert size(s) == (1408, 1072)
@assert isapprox(s.wavelength[1], 662.3832; atol=1e-3)
@assert isapprox(s.wavelength[end], 395.2035; atol=1e-3)
@assert s.time[1] == 0.0
@assert isapprox(s.time[end], 47.2428; atol=1e-3)
@assert minimum(s.counts) == 0.0
@assert maximum(s.counts) == 75.0
@assert isapprox(sum(s.counts)/length(s.counts), 1.1404; atol=1e-3)
@assert s.xunits == "nm" && s.yunits == "ns" && s.zunits == "Count"
@assert s.camera == "C11440-36U"
@assert s.streak_device == "C10910"
@assert s.time_range == "50 ns"
@assert s.center_wavelength == 554.969
@assert s.grating == "50 g/mm"
@assert s.exposure == "14 ms"
@assert s.n_exposures == 47808
@assert s.software == "HPD-TA"
@assert s.date == DateTime(2026, 6, 2, 13, 17, 16)
@assert haskey(s.metadata, "DisplayLUT")   # real butting-section case parsed
line1 = split(readline("/Users/garrek/Developer/QPSTools.jl/data/PL/15K.dat"), "\t")
@assert parse.(Float64, line1) == s.counts[:, 1]   # byte-exact vs ASCII export
show(stdout, MIME("text/plain"), s); println()
println("REAL-FILE VERIFICATION PASSED")'
```

Expected: the pretty-printed `StreakImage` summary followed by `REAL-FILE VERIFICATION PASSED`. Any `AssertionError` here means a parser bug — STOP and debug before proceeding (use superpowers:systematic-debugging).

---

### Task 10: CI, repo files, final check

**Files:**
- Create: `.github/workflows/CI.yml`
- Create: `.github/workflows/TagBot.yml`
- Create: `.github/dependabot.yml`
- Create: `README.md`
- Create: `CLAUDE.md`

- [ ] **Step 1: Create `.github/workflows/CI.yml`** (JASCOFiles-canonical, minus the docs job — Documenter is deferred):

```yaml
name: CI
on:
  push:
    branches:
      - main
    tags: ['*']
  pull_request:
  workflow_dispatch:
concurrency:
  # Skip intermediate builds: always.
  # Cancel intermediate builds: only if it is a pull request build.
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ startsWith(github.ref, 'refs/pull/') }}
jobs:
  test:
    # Lightweight matrix for PRs and main: Linux only, Julia LTS + current.
    name: Julia ${{ matrix.version }} - ubuntu
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        version: ['1', '1.10']
    steps:
      - uses: actions/checkout@v6
      - uses: julia-actions/setup-julia@v3
        with:
          version: ${{ matrix.version }}
      - uses: julia-actions/cache@v3
      - uses: julia-actions/julia-buildpkg@v1
      - uses: julia-actions/julia-runtest@v1
      - uses: julia-actions/julia-processcoverage@v1
      - uses: codecov/codecov-action@v6
        with:
          token: ${{ secrets.CODECOV_TOKEN }}
          files: lcov.info
          fail_ci_if_error: false
  test-cross-platform:
    # Cross-platform verification only on tags / manual dispatch.
    # macOS minutes count 10x and Windows 2x in GitHub billing weight,
    # so we skip them on PRs and main pushes.
    name: Julia 1 - ${{ matrix.os }}
    if: startsWith(github.ref, 'refs/tags/') || github.event_name == 'workflow_dispatch'
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os: [macos-latest, windows-latest]
    steps:
      - uses: actions/checkout@v6
      - uses: julia-actions/setup-julia@v3
        with:
          version: '1'
      - uses: julia-actions/cache@v3
      - uses: julia-actions/julia-buildpkg@v1
      - uses: julia-actions/julia-runtest@v1
```

- [ ] **Step 2: Create `.github/workflows/TagBot.yml`** — copy verbatim from `/Users/garrek/Developer/JASCOFiles.jl/.github/workflows/TagBot.yml`.

- [ ] **Step 3: Create `.github/dependabot.yml`**

```yaml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
  - package-ecosystem: "julia"
    directory: "/"
    schedule:
      interval: "weekly"
```

- [ ] **Step 4: Create `README.md`**

````markdown
# HamamatsuStreakFiles.jl

Read Hamamatsu HPD-TA / HiPic `.img` (ITEX) streak-camera files in Julia.

```julia
using HamamatsuStreakFiles

s = StreakImage("measurement.img")
s.wavelength     # spectral axis (nm) — on-disk order preserved
s.time           # temporal axis (ns)
s.counts         # counts[wavelength, time]
s.metadata       # full instrument metadata, by INI section
```

Quick-look plotting via a Makie extension (load a backend first):

```julia
using GLMakie
fig, ax, hm = plot(s)
```

## Format support

| Feature | Status |
|---|---|
| 8/16/32-bit unsigned pixel data | ✅ |
| Embedded `#offset,count` calibration tables | ✅ |
| External sidecar calibration files | ✅ (falls back to linear with a warning if missing) |
| Uncalibrated (`"Other"`) / linear axes | ✅ (linear or pixel-index fallback) |
| Compressed images (`type=1`) | ❌ not supported (no open decompressor exists) |
| `.his` image sequences | ❌ planned |

Part of a family of vendor file readers:
[JASCOFiles.jl](https://github.com/garrekstemo/JASCOFiles.jl),
[RigakuFiles.jl](https://github.com/garrekstemo/RigakuFiles.jl).
````

- [ ] **Step 5: Create `CLAUDE.md`**

```markdown
# HamamatsuStreakFiles.jl

Standalone reader for Hamamatsu HPD-TA/HiPic `.img` (ITEX) streak-camera files.
Sibling of JASCOFiles.jl / RigakuFiles.jl; not yet registered.

- Design spec: `docs/superpowers/specs/2026-06-09-hamamatsu-img-reader-design.md`
  (byte layout, dtype table, scaling resolution rules — authoritative).
- `StreakImage(path)` is the only public entry point; internals are
  underscore-prefixed and unexported.
- Wavelength axis preserves on-disk order (commonly DESCENDING). Never sort or
  flip in the reader; the Makie ext flips display copies only.
- The `.img` dtype table must NOT be reused for future `.his` support — the
  `.his` dataType enum differs (code 1 = UInt8 there, compressed here).
- Tests are synthetic (`make_img` builder in `test/runtests.jl`); no real
  instrument file is committed. Real-file ground truth lives at
  `QPSTools.jl/data/PL/15K.img` (see plan Task 9).
```

- [ ] **Step 6: Run the full test suite one final time**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: PASS, all testsets green.

- [ ] **Step 7: Commit**

```bash
git add .github README.md CLAUDE.md
git commit -m "chore: CI workflows, dependabot, README, CLAUDE.md"
```

---

## Completion criteria

- All 10 tasks committed; `git log` shows one focused commit per task.
- Full test suite green: synthetic round-trips, all scaling fallbacks, all error
  paths, show methods, Makie ext, Aqua.
- Task 9 real-file gate passed (including the `.dat` cross-check).
- Not in scope here: GitHub repo creation/push, registration, QPSTools
  integration (`load_streak_pl`) — follow-on work.
