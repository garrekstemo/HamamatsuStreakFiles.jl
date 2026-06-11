# HamamatsuStreakFiles.jl

[![CI](https://github.com/garrekstemo/HamamatsuStreakFiles.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/garrekstemo/HamamatsuStreakFiles.jl/actions/workflows/CI.yml)
[![docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://garrekstemo.github.io/HamamatsuStreakFiles.jl/dev/)
[![codecov](https://codecov.io/gh/garrekstemo/HamamatsuStreakFiles.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/garrekstemo/HamamatsuStreakFiles.jl)
[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)
[![license](https://img.shields.io/github/license/garrekstemo/HamamatsuStreakFiles.jl)](LICENSE)

Read Hamamatsu HPD-TA / HiPic `.img` (ITEX) streak-camera files in Julia.

## Installation

```julia
using Pkg
Pkg.add("HamamatsuStreakFiles")
```

## Usage

```julia
using HamamatsuStreakFiles

s = StreakImage("measurement.img")
s.wavelength     # spectral axis (nm) — on-disk order preserved
s.time           # temporal axis (ns)
s.counts         # counts[wavelength, time]
s.metadata       # full instrument metadata, by INI section
```

> **The one gotcha:** HPD-TA stores the wavelength axis in instrument order,
> which usually *decreases* (red → blue). `StreakImage` preserves that order,
> so `s.wavelength[1]` is the longest wavelength. The Makie extension flips
> display copies to ascending for you; your own index math should not assume
> ascending order.

## Example: heatmap, spectrum, and decay

A streak image is a wavelength × time matrix of photon counts, so the two
standard lineouts are sums along each axis. Quick-look plotting comes from a
Makie package extension — load any Makie backend first:

```julia
using HamamatsuStreakFiles
using GLMakie

s = StreakImage("measurement.img")

propertynames(s)               # everything the object carries
size(s)                        # (n_wavelength, n_time), e.g. (1408, 1072)
s.camera, s.time_range, s.date # hoisted instrument metadata
s.metadata["Streak camera"]    # ...or the full raw metadata, by section

# Heatmap quick look (plot puts its colorbar at f[1, 2])
f, ax1, hm = plot(s)

# Spectrum: sum each wavelength's row over all time bins
spectrum = vec(sum(s.counts, dims = 2))
ax2 = Axis(f[1, 3], title = "Spectrum", xlabel = "Wavelength (nm)", ylabel = "Counts")
lines!(ax2, s.wavelength, spectrum)

# Decay: sum each time bin's column over all wavelengths
decay = vec(sum(s.counts, dims = 1))
ax3 = Axis(f[2, 1:3], title = "Decay", xlabel = "Time (ns)", ylabel = "Counts")
lines!(ax3, s.time, decay)

f
```

Single rows and columns are lineouts too — `s.counts[:, 100]` is the spectrum
at the 100th time bin — but photon-counting data is noisy bin-by-bin, so sum a
band instead. Remember the wavelength axis decreases:

```julia
i = findfirst(<=(450), s.wavelength)      # first pixel at or below 450 nm
band = vec(sum(s.counts[i-20:i+20, :], dims = 1))
lines(s.time, band)                       # decay near 450 nm
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

Malformed or foreign `.img` files (the extension is shared by several
unrelated vendor formats) fail fast with an error naming the file —
never silent garbage.

## Documentation

Full documentation, including the `.img` format guide and the public API
reference, is at
[garrekstemo.github.io/HamamatsuStreakFiles.jl](https://garrekstemo.github.io/HamamatsuStreakFiles.jl/dev/).

Part of a family of vendor file readers:
[JASCOFiles.jl](https://github.com/garrekstemo/JASCOFiles.jl),
[RigakuFiles.jl](https://github.com/garrekstemo/RigakuFiles.jl).
