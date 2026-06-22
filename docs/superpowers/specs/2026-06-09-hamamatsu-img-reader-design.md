# HamamatsuStreakFiles.jl — Design Spec

**Date:** 2026-06-09
**Status:** Approved design, pending implementation plan
**Author:** Garrek Stemo (with Claude)

## 1. Purpose & scope

A standalone Julia package that reads **Hamamatsu HPD-TA / HiPic `.img` (ITEX) streak-camera
files** into a typed `StreakImage` struct. It is a sibling of
[JASCOFiles.jl](https://github.com/garrekstemo/JASCOFiles.jl) and
[RigakuFiles.jl](https://github.com/garrekstemo/RigakuFiles.jl): a vendor-format reader at the
*Application* edge of the QPS ecosystem, registerable and reusable, with no dependency on the
analysis or lab-integration layers.

**In scope:** parse a single `.img` file → `StreakImage` (wavelength × time × counts + metadata),
with a quick-look Makie heatmap behind a weak dependency.

**Out of scope (deliberately deferred):**

- QPSTools integration (`load_streak_pl` wrapper, themed/publication plotting, eLabFTW provenance)
  — a separate follow-on cycle in QPSTools, which will `[sources]`-depend on this package.
- `.his` image-sequence reading — see §10 (Future-proofing seam). The single-record parser is
  structured so a `.his` loop can be added later without rework, but no `.his` code ships now.
- The sibling `.dat` export (tab-separated ASCII of the same count matrix, **no axes, no metadata**)
  — strictly inferior to `.img`; not worth a reader. The `.img` is the canonical rich file.

### Approved decisions (from brainstorming)

| Decision | Choice |
|---|---|
| Package name | `HamamatsuStreakFiles.jl` |
| `counts` element type | `Float64` (ecosystem consistency; easy downstream math) |
| Wavelength-axis order | **Preserve on-disk order** (descending), `counts` aligned — matches JASCOFiles' descending-grid behavior |
| Quick-look plot | In-package Makie weakdep extension |
| Makie API | Overload `Makie.convert_arguments` + `Makie.plot(::StreakImage)` (sibling convention), **not** a bespoke `plot_streak` |
| Abstract supertype | `AbstractStreakImage`; `StreakImage <: AbstractStreakImage` (matches `AbstractJASCOSpectrum`/`AbstractRigakuSpectrum`) |
| `path` field on struct | Omitted — the *data* types `JASCOSpectrum`/`RigakuScan` carry none; only multi-record containers do |
| Tests | Synthetic byte-builder (`make_img`/`write_img`), à la JASCOFiles `make_jws`/`write_jws`; no 3 MB real fixture committed |

## 2. File format

Verified byte-exact against a real 3,038,912-byte sample (`15K.img`, HPD-TA 9.5 pf11, camera
C11440-36U, streak unit C10910). Cross-checked against the open-source RosettaSciIO Hamamatsu
reader (`rsciio/hamamatsu/_api.py`) and Bio-Formats `HISReader.java`. Four contiguous regions:

```
┌──────────────────────────────────────────────────────────────────────┐
│ Header        64 bytes                                                  │
│ Comment       comment_len bytes  (INI-style ASCII)                      │
│ Image         width*height*bytes_per_pixel  (little-endian)             │
│ X scaling     count_x * Float32 LE  (at absolute offset from [Scaling]) │
│ Y scaling     count_y * Float32 LE  (at absolute offset from [Scaling]) │
└──────────────────────────────────────────────────────────────────────┘
```

### 2.1 Header (64 bytes, all multi-byte fields little-endian)

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| 0 | 2 | magic `IM` | ASCII `"IM"`; **tolerate a trailing NUL** (`IM\0`); else bad-magic `ArgumentError` |
| 2 | 2 | `comment_len` | `UInt16` |
| 4 | 2 | `width` | `UInt16` (= wavelength pixel count) |
| 6 | 2 | `height` | `UInt16` (= time pixel count) |
| 8 | 2 | `x_off` | `UInt16`; typically 0/unused |
| 10 | 2 | `y_off` | `UInt16`; typically 0/unused |
| 12 | 2 | `type` | `UInt16` dtype code (see §2.3) |
| 14 | 50 | reserved | zero padding |

> **Integer-widening trap.** `width`/`height` are 16-bit. `width*height` overflows `UInt16`/`Int16`
> (sample: 1408×1072 = 1,509,376). **Widen to `Int` before** computing pixel count, data-block
> length, and scaling-offset bounds. RosettaSciIO documents this exact bug class.

### 2.2 Comment (`comment_len` bytes, ASCII INI)

Immediately follows byte 64. INI-like, but with quirks the parser must handle:

- `[Section]` headers and `key=value` pairs, comma-separated **within** a section.
- **Sections butt together with no separator**, e.g. `...SubType=0[DisplayLUT],EntrySize=4`.
- **Values may be quoted**, and quoted values may contain commas, `=`, or `[`
  (e.g. `areSource="0,0,1408,1072"`, `ScalingXScalingFile="#3028992,1408"`).
- The parser is **quote-aware**: a quoted value reads to its closing `"` without comma-splitting;
  an unquoted value terminates at the next comma. Parse **leniently** — `comment_len` (u16) caps
  the INI at 65535 bytes and the instrument may truncate mid-block; never assume well-formed/complete.

Parsed into `metadata::Dict{String, Dict{String,String}}` keyed by section name
(`"Application"`, `"Camera"`, `"Acquisition"`, `"Streak camera"`, `"Spectrograph"`, `"Scaling"`, …).

### 2.3 Image data

`width*height` pixels, **little-endian**, starting at offset `64 + comment_len`. Stored row-major
with **`width` (wavelength) as the fast/contiguous axis**.

> **Pixel orientation (VERIFIED, not assumed).** In Julia's column-major layout,
> `reshape(raw, width, height)` yields `counts[wavelength_i, time_j]` directly — a column is a
> spectrum at one time, a row is a kinetic trace at one wavelength. Confirmed byte-exact: the
> sibling `.dat` ASCII export (1072 time rows × 1408 wavelength cols, row-major) matched
> `img[r*width + c]` across 630 sampled cells plus full rows 0/103/1071 with **0 mismatches**.

**dtype table — the `.img` (HPD-TA) `FileType` enum. AUTHORITATIVE. Do NOT reuse for `.his`.**

| `type` code | Julia type | bytes/px | Status |
|---|---|---|---|
| 0 | `UInt8`  | 1 | supported |
| 1 | *(compressed)* | — | **UNSUPPORTED** → `ArgumentError` (no open decompressor exists; RosettaSciIO comments "not used by HPD-TA") |
| 2 | `UInt16` | 2 | supported — **the sample**; LE |
| 3 | `UInt32` | 4 | supported (the `.img` format's reason-to-exist over 16-bit TIFF export) |

- **No `Int32` and no `Float32` *image* dtype exist** in the HPD-TA enum. `Float32` is the
  *scaling-array* element type only. Unknown code → `ArgumentError`.
- **Code-1 collision:** `1` means *compressed* here, but `UInt8` in the Bio-Formats `.his`
  `dataType` table. The `.img` dtype map **must never be shared** with a future `.his` reader.
- All integer pixels are read LE and converted to `Float64` for `counts`.

### 2.4 Scaling arrays

Appended **after** the image block, referenced from the `[Scaling]` section. The sample:
`ScalingXScalingFile="#3028992,1408"` (X = wavelength/nm), `ScalingYScalingFile="#3034624,1072"`
(Y = time/ns). Both are `Float32` LE arrays whose lengths equal `width`/`height` respectively.

**Resolution order, per axis** (read `ScalingXType`/`ScalingYType` and `ScalingXScalingFile`/…):

1. **`"Other"` or any non-`#`, non-filename sentinel → UNCALIBRATED.** **Check this FIRST**, before
   any `#`/integer parsing, or the reader crashes trying to int-parse `"Other"`. (Documented
   RosettaSciIO gotcha, PRs #347/#387.) Fall through to the linear/pixel fallback (step 5).
2. **Starts with `#` → embedded array.** Parse `#offset,count`. **Validate `offset + count*4 ≤ filesize`**
   (guards truncated files); `seek` to the absolute `offset`; read `count` `Float32` LE values.
3. **Otherwise a filename → external sidecar.** Attempt to open relative to the `.img`'s directory;
   if absent/unreadable, **warn + linear fallback** (step 5). (This is intentionally *more robust*
   than RosettaSciIO, which errors here.)
4. **Empty/missing → linear fallback** (step 5).
5. **Linear / pixel fallback.** If `ScalingXType == 1` (linear) or any fallback above:
   `value[i] = ScalingXOffset + i * ScalingXScale`, units from `ScalingXUnit`. If `ScalingXScale`
   is absent or `0`, use a pure pixel index `0:N-1` with units `"px"`. (Honoring `ScalingXScale` is
   better than RosettaSciIO, which hardcodes scale=1 in its linear branch.)

- `ScalingXType` codes: **1 = linear, 2 = table/file**. `type==2` → step 2 path. **Unknown type →
  warn + linear fallback** (not a hard error).
- **Axes may be non-monotonic / descending.** The sample's X is **662.4 → 395.2 nm (descending)**;
  Y is 0 → 47.24 ns (ascending). **Do not assume ascending and do not sort.** Per the approved
  decision, preserve raw on-disk order with `counts` aligned to it.

## 3. The `StreakImage` type

```julia
abstract type AbstractStreakImage end

struct StreakImage <: AbstractStreakImage
    wavelength::Vector{Float64}   # nm   (x axis, length = width; on-disk order, may descend)
    time::Vector{Float64}         # ns   (y axis, length = height)
    counts::Matrix{Float64}       # size (n_wavelength, n_time); counts[λ_i, t_j]
    xunits::String                # "nm"     (from ScalingXUnit)
    yunits::String                # "ns"     (from ScalingYUnit)
    zunits::String                # "Count"  (from [Acquisition] ZAxisUnit; "" if absent)
    date::DateTime                # acquisition time (from [Application] Date + Time)
    software::String              # "HPD-TA" (from [Application] Software)
    camera::String                # "C11440-36U" (from [Camera] CameraName)
    streak_device::String         # "C10910" (from [Streak camera] DeviceName)
    time_range::String            # "50 ns"  (raw token incl. unit; from [Streak camera] "Time Range")
    center_wavelength::Float64    # 554.969 nm (from [Spectrograph] Wavelength)
    grating::String               # "50 g/mm" (from [Spectrograph] Grating)
    exposure::String              # "14 ms"  (raw token; from [Acquisition] ExposureTime)
    n_exposures::Int              # 47808    (from [Acquisition] NrExposure)
    metadata::Dict{String,Dict{String,String}}   # full raw comment, by section
end
```

- **Sentinels for missing fields** (matches the documented sibling table): `String → ""`,
  `Float64 → 0.0`, `Int → 0`, `DateTime → nothing`.
- The **hoisted field set above is FROZEN** as the minimal lab-relevant subset. Everything else
  stays in `metadata` only — do not keep growing hoisted fields.
- `time_range` and `exposure` are intentionally kept as **raw strings** because they carry a unit
  token (`"50 ns"`, `"14 ms"`); `center_wavelength` is parsed to `Float64` (bare nm value).
- `Base.show` two-method house style: a compact one-line `show(io, ::StreakImage)` and a pretty
  `show(io, ::MIME"text/plain", ::StreakImage)` (dims, ranges, key instrument fields).
- `Base.size(::StreakImage) = (n_wavelength, n_time)`.

## 4. Public API

- **`StreakImage(path::AbstractString)`** — constructor-as-loader (sibling convention:
  `RigakuFile(path)`, `JASCOSpectrum(path)`). Accept any `AbstractString` (e.g. `SubString`).
- **Date parsing is defensive.** `[Application]` `Date`/`Time` use locale-variable separators
  (`/` or `.`) and are **day-first** (`DD?MM?YYYY` per RosettaSciIO's transform), not ISO/US order.
  On any parse failure: keep the raw strings in `metadata` and set `date = nothing` — **never throw**.

## 5. Package layout

```
HamamatsuStreakFiles.jl/
  Project.toml
  src/
    HamamatsuStreakFiles.jl   # module: using Dates; includes; exports
    types.jl                  # AbstractStreakImage, StreakImage, show, size
    binary.jl                 # LE readers (ltoh+reinterpret), header reader, image reader,
                              #   Float32-array reader, bounds checks
    parser.jl                 # orchestration; quote-aware INI parser; scaling resolution
  ext/
    HamamatsuStreakFilesMakieExt.jl
  test/
    runtests.jl               # synthetic make_img/write_img builder + Aqua
  docs/                       # Documenter scaffold (optional; may defer)
  .github/workflows/
    CI.yml                    # JASCOFiles-canonical (see §8)
    TagBot.yml
  .github/dependabot.yml      # github-actions weekly + julia weekly (/ and /docs)
  LICENSE  README.md  CLAUDE.md  .gitignore (ignores Manifest.toml)
```

`binary.jl`'s LE-read helper mirrors JASCOFiles' `read_le` (`ltoh` + `reinterpret`) so big-endian
hosts byte-swap correctly — pixel data **and** `Float32` scaling arrays are little-endian.

## 6. Dependencies

- **`[deps]`**: `Dates` only. The comment is ASCII/UTF-8 (Julia-native) — **no `StringEncodings`**
  (unlike JASCO's SHIFT-JIS text). Matches RigakuFiles' light profile.
- **`[weakdeps]`**: `Makie`. **`[extensions]`**: `HamamatsuStreakFilesMakieExt = "Makie"`.
- **`[compat]`**: `julia = "1.10"`, `Dates = "1"`, `Aqua = "0.8"`, `Makie = "0.20, 0.21, 0.22, 0.23, 0.24"`
  (match JASCOFiles' range). Lower bounds otherwise auto-added by `Pkg.add` and kept.
- **`[extras]`/`[targets]`**: `test = ["Aqua", "Makie", "Test"]`.
- **Manifest.toml is gitignored** (sibling convention; reproducible from Project.toml).

## 7. Makie extension (`ext/HamamatsuStreakFilesMakieExt.jl`)

Follow the JASCOFiles ext pattern exactly:

- `Makie.convert_arguments(P::Type{<:Heatmap}, img::StreakImage)` → `(img.wavelength, img.time, img.counts)`
  so `heatmap(img)` / `heatmap!(ax, img)` work directly.
- `Makie.plot(img::StreakImage; axis=NamedTuple(), kwargs...)` → a `heatmap` returning a
  `FigureAxisPlot`, with axis defaults: `xlabel` from `xunits` ("Wavelength (nm)"),
  `ylabel` from `yunits` ("Time (ns)"), and a colorbar/`zunits` label. An `axis` NamedTuple
  overrides defaults; extra kwargs forward to `Makie.heatmap`.
- Quick-look only. Themed/publication plotting stays in QPSTools.

## 8. Errors

All `ArgumentError` with a specific message unless noted; warnings degrade gracefully.

| Condition | Behavior |
|---|---|
| bad magic (not `IM`/`IM\0`) | `ArgumentError` "not a Hamamatsu .img (bad magic)" |
| file `< 64` bytes | `ArgumentError` "file too short for header" |
| file `< 64 + comment_len + n_pixels*bytes_per_pixel` | `ArgumentError` "image data truncated" |
| `type == 1` (compressed) | `ArgumentError` "compressed .img not supported" |
| unknown `type` code | `ArgumentError` "unknown pixel type code N" |
| scaling `#offset,count` out of bounds (`offset+count*4 > filesize`) | **warn + linear/pixel fallback** (image is still valid) |
| `ScalingXScalingFile == "Other"` / external-missing / empty | **warn + linear/pixel fallback** (not an error) |
| unknown `ScalingXType` | **warn + linear fallback** |
| date unparseable | raw kept in `metadata`, `date = nothing`, **no throw** |

## 9. Tests (`test/runtests.jl`)

Primary mechanism is a **synthetic byte-builder** `make_img(; …)` + `write_img(bytes)` (mirroring
JASCOFiles `make_jws`/`write_jws`) — writes a tiny valid `.img` (e.g. 4×3) with a known comment and
embedded `#offset,count` scaling arrays. No 3 MB real fixture is committed.

Cases:

- **Valid round-trip** — assert exact `wavelength`, `time`, `counts`, units, hoisted metadata.
- **Descending-X round-trip** — write a descending `Float32` X array; assert `wavelength[1] > wavelength[end]`
  **and** `counts` stays aligned (this guards the preserve-on-disk-order decision).
- **Quote-aware INI** — values with embedded commas, `=`, and `[`; butting `[Section]` blocks.
- **Scaling fallbacks** — `"Other"`, missing external file, empty, and unknown `ScalingXType` → warn + linear/pixel.
- **Error paths** — bad magic, header-truncated, image-truncated, scaling-offset OOB, compressed `type=1`, unknown dtype.
- **Date** — locale separators, day-first, and unparseable → `nothing` + raw kept (use `@test_logs` for the warn).
- **Show methods** — compact (one line) and MIME (dims/ranges/instrument fields).
- **Type hierarchy** — `StreakImage <: AbstractStreakImage`.
- **`AbstractString` path** — `SubString` argument works.
- **Makie extension** — `convert_arguments` returns `(wavelength, time, counts)`; `plot(img)` yields a
  `FigureAxisPlot` with expected labels.
- **Aqua** — `Aqua.test_all(HamamatsuStreakFiles; deps_compat = (check_extras = false,))`.

## 10. Future-proofing seam (`.his` — NOT built now)

The `.his` (Hamamatsu Image Sequence) format is a **concatenation of ITEX IMG records**, each with
the **same 64-byte header** decoded here. To keep `.his` cheap to add later, the single-record parse
(header → comment → image → per-record `[Scaling]` with absolute `#offset` arrays) must be a
**reusable unit**, with no single-image assumptions baked in. A future `.his` loader is a thin loop:
read header → read `comment_len` → `dataSize = width*height*bytes_per_pixel` → next record at
`current_data_start + dataSize` → repeat to EOF → return `Vector{StreakImage}`.

**Critical:** `.his` uses a **different `dataType` table** (`{1:UInt8, 2:UInt16, 6:UInt16-12bit,
11/12/14:RGB}` per Bio-Formats `HISReader.java`) that **collides with the `.img` enum on code 1**.
The `.img` dtype map must not be reused for `.his`.

## 11. References

- RosettaSciIO Hamamatsu reader (primary `.img` source): `rsciio/hamamatsu/_api.py` —
  `FileType` enum `{bit8=0, compressed=1, bit16=2, bit32=3}`, `Scaling_Type` `{linear=1, table=2}`,
  the `#offset,count` Float32-seek parser, the quote-aware INI parser, day-first date parsing.
- RosettaSciIO PRs [#87](https://github.com/hyperspy/rosettasciio/pull/87) (added `.img`; 32-bit;
  LE byte-order fix), [#347](https://github.com/hyperspy/rosettasciio/pull/347) /
  [#387](https://github.com/hyperspy/rosettasciio/pull/387) (`"Other"` uncalibrated-axis sentinel).
- Bio-Formats `HISReader.java` (primary `.his` source) — concatenated-record structure, `.his`
  dataType table.
- HiPic v9.1 user manual (`HiPicFileFormat.pdf`) — `[Scaling]` field names (vendor doc).
- Local verification: `QPSTools.jl/data/PL/15K.img` (decoded byte-exact, all four regions reconcile
  to the 3,038,912-byte file) and `15K.dat` (TSV cross-check of pixel orientation).
