```@meta
CurrentModule = HamamatsuStreakFiles
```

# The `.img` (ITEX) file format

[`StreakImage`](@ref) reads the single-image `.img` files written by Hamamatsu's HPD-TA and HiPic acquisition software.
This page documents what the parser expects, how axis calibration is resolved, and the known limitations.

## Layout

Every `.img` file has four contiguous regions:

| Region | Size | Content |
|---|---|---|
| Header | 64 bytes | magic `"IM"`, comment length, width, height, pixel type (all little-endian `UInt16`) |
| Comment | `comment_len` bytes | INI-style ASCII metadata, `[Section]` blocks of `key=value` pairs |
| Image | `width × height × bytes_per_pixel` | pixel counts, little-endian, wavelength as the fast axis |
| Scaling | trailing `Float32` arrays | per-axis calibration tables referenced from `[Scaling]` |

`width` is the wavelength pixel count and `height` the time pixel count, so the matrix loads directly as `counts[wavelength, time]` in Julia's column-major order.

## Pixel types

The header `type` field selects the pixel data type:

| Code | Type | Status |
|---|---|---|
| 0 | `UInt8` | supported |
| 1 | compressed | **unsupported** — throws `ArgumentError` (no open decompressor exists) |
| 2 | `UInt16` | supported (the common case) |
| 3 | `UInt32` | supported |

All pixels are converted to `Float64` in `counts`.

## Axis calibration

Each axis is resolved from the `[Scaling]` section in this order:

1. `ScalingXType=1` → **linear axis** from `ScalingXOffset` + `ScalingXScale`. A missing or zero scale degrades to a pixel-index axis with unit `"px"`.
2. `ScalingXScalingFile="#offset,count"` → **embedded table**: `count` little-endian `Float32` values at absolute byte `offset` in the file. The reference is bounds- and length-checked.
3. `ScalingXScalingFile="somefile"` → **external sidecar file**, looked up next to the `.img` file.
4. `ScalingXScalingFile="Other"` or empty → **uncalibrated**: pixel-index fallback.

Every failure path (out-of-bounds table, missing sidecar, count mismatch, unknown type code) **warns and degrades** to the linear/pixel fallback rather than throwing — the image itself is still valid data. Warnings and errors name the file, so batch loads identify their source.

## Axis order

HPD-TA stores the wavelength table in instrument order, which usually **descends** (red → blue; e.g. 662.4 → 395.2 nm).
The reader preserves on-disk order and keeps `counts` aligned with it — it never sorts or flips.
The Makie extension flips display copies only.

## Dates

`[Application]` `Date`/`Time` separators vary by locale (`/` or `.`) and may be day-first or year-first; the parser handles both and never throws.
An unparseable date gives the sentinel `DateTime(1)` (year 0001), with the raw strings still available in `s.metadata["Application"]`.

## Errors

Malformed files fail fast with an `ArgumentError` naming the file:

- not a Hamamatsu `.img` file (bad magic),
- file too short for the 64-byte header,
- comment or image data truncated,
- compressed (`type=1`) or unknown pixel type.

A missing/unreadable path throws the usual `SystemError`.

## Not supported

- **Compressed images** (`type=1`) — no open decompressor exists; HPD-TA does not write them in practice.
- **`.his` image sequences** — a planned addition. A `.his` file is a concatenation of ITEX records, but its data-type enum differs from the `.img` one, so it needs its own reader.
- The sibling `.dat` export (tab-separated ASCII of the same matrix, without axes or metadata) — the `.img` file is strictly richer; load that instead.

## References

The byte layout was verified against real HPD-TA 9.5 files and cross-checked with the open-source [RosettaSciIO](https://github.com/hyperspy/rosettasciio) Hamamatsu reader and Bio-Formats' `HISReader`, plus Hamamatsu's HiPic file-format documentation.
