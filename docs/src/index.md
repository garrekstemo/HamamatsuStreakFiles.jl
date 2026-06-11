```@meta
CurrentModule = HamamatsuStreakFiles
```

# HamamatsuStreakFiles.jl

```@docs
HamamatsuStreakFiles
```

HamamatsuStreakFiles.jl reads the native `.img` (ITEX) files written by Hamamatsu's HPD-TA and HiPic streak-camera software into a [`StreakImage`](@ref) struct: a wavelength × time matrix of photon counts, both calibrated axes, and the full instrument metadata. There is no manual export step — the binary file the instrument writes is the file you load.

The package is deliberately small (its only dependency is `Dates`) so that it loads quickly. A quick-look heatmap is available through a Makie package extension.

## Installation

```julia
using Pkg
Pkg.add("HamamatsuStreakFiles")
```

## Reading a file

Point [`StreakImage`](@ref) at a `.img` file and you get a parsed struct back:

```julia
using HamamatsuStreakFiles

s = StreakImage("measurement.img")
```

In the REPL, the image prints a compact summary:

```julia-repl
julia> s = StreakImage("15K.img")
StreakImage(1408×1072, 662.4–395.2 nm, 0.0–47.24 ns)

julia> show(stdout, MIME("text/plain"), s)
StreakImage
  Size:         1408 wavelength × 1072 time
  Wavelength:   662.38 – 395.2 nm
  Time:         0.0 – 47.243 ns
  Camera:       C11440-36U
  Streak unit:  C10910
  Time range:   50 ns
  Spectrograph: 554.969 nm center, 50 g/mm
  Exposure:     14 ms × 47808
  Acquired:     2026-06-02 13:17:16
  Metadata:     13 sections
```

## What's in a streak image

The axes and counts are plain Julia arrays, and the common instrument fields are available directly on the struct:

```julia
s.wavelength     # spectral axis (nm) — on-disk order preserved
s.time           # temporal axis (ns)
s.counts         # counts[wavelength, time], Float64
s.xunits         # "nm"
s.yunits         # "ns"
s.zunits         # "Count"
s.date           # acquisition DateTime
s.camera         # readout camera, e.g. "C11440-36U"
s.streak_device  # streak unit, e.g. "C10910"
s.time_range     # sweep window, e.g. "50 ns"
s.center_wavelength, s.grating         # spectrograph settings
s.exposure, s.n_exposures              # "14 ms", 47808
```

!!! warning "The one gotcha: wavelength order"
    HPD-TA stores the wavelength axis in instrument order, which usually *decreases* (red → blue). `StreakImage` preserves that order, so `s.wavelength[1]` is the longest wavelength and `s.counts` rows are aligned with it. The Makie extension flips display copies to ascending for you; your own index math should not assume ascending order.

## Metadata

Every key/value pair from the file's INI-style comment block is preserved in `s.metadata`, a `Dict{String, Dict{String, String}}` keyed by `[Section]` name, then key:

```julia
s.metadata["Streak camera"]["Time Range"]   # "50 ns"
s.metadata["Acquisition"]["NrExposure"]     # "47808"
s.metadata["Spectrograph"]["Grating"]       # "50 g/mm"
```

Values are stored as raw strings — the hoisted struct fields above cover the common ones, and `metadata` keeps everything else (trigger settings, LUT state, plug-in fields, …).

Fields missing from a file get sentinel values (`""`, `0`, `0.0`, or `DateTime(1)` for the date); inspect `s.metadata` for strict present-vs-missing checks.

## Plotting

With Makie loaded, `plot(s)` gives a quick-look heatmap with unit-labelled axes and a colorbar:

```julia
using HamamatsuStreakFiles, GLMakie

s = StreakImage("measurement.img")
fig, ax, hm = plot(s)
fig, ax, hm = plot(s; colormap = :inferno)
```

The extension also hooks `Makie.convert_arguments`, so `heatmap(s)`, `heatmap!(ax, s)`, and `contourf(s)` work directly. Display copies are flipped to ascending wavelength (Makie requires sorted axes); the struct itself is untouched.

## Spectra and decays

A streak image is a wavelength × time matrix, so the two standard lineouts are sums along each axis:

```julia
spectrum = vec(sum(s.counts, dims = 2))   # counts vs wavelength
decay    = vec(sum(s.counts, dims = 1))   # counts vs time
```

Single rows and columns work too — `s.counts[:, 100]` is the spectrum at the 100th time bin — but photon-counting data is noisy bin-by-bin, so sum a band instead. Remember the wavelength axis decreases:

```julia
i = findfirst(<=(450), s.wavelength)      # first pixel at or below 450 nm
band = vec(sum(s.counts[i-20:i+20, :], dims = 1))
```

## Issues and contributions

If you run into a `.img` file this package mis-parses — especially one from an HPD-TA/HiPic version or camera not yet covered — please open an issue at [github.com/garrekstemo/HamamatsuStreakFiles.jl/issues](https://github.com/garrekstemo/HamamatsuStreakFiles.jl/issues). The header and comment block (first few kB of the file) are the most helpful thing to attach.
