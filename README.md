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
