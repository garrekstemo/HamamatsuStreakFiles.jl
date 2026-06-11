```@meta
CurrentModule = HamamatsuStreakFiles
```

# Public API

Only exported types and functions are considered part of the public API. Raw instrument fields not covered by the hoisted struct fields are still available through `s.metadata`.

## Index

```@index
Pages = ["public.md"]
```

## Types

```@autodocs
Modules = [HamamatsuStreakFiles]
Pages = ["types.jl"]
Private = false
```

## Reading files

```@autodocs
Modules = [HamamatsuStreakFiles]
Pages = ["parser.jl"]
Private = false
```

## Plotting with Makie

When Makie is loaded, `plot(s)` is available via a package extension. Load a backend first (`using CairoMakie` or `using GLMakie`):

```julia
using HamamatsuStreakFiles, GLMakie

s = StreakImage("measurement.img")
fig, ax, hm = plot(s)
fig, ax, hm = plot(s; colormap = :inferno)
fig, ax, hm = plot(s; axis = (ylabel = "Delay (ns)",))
```

Axis defaults are filled from the image:

- `xlabel` from `s.xunits` (e.g. `"Wavelength (nm)"`)
- `ylabel` from `s.yunits` (e.g. `"Time (ns)"`)
- a colorbar labelled with `s.zunits`

Pass an `axis` NamedTuple to override any of these. Other keyword arguments are forwarded to `Makie.heatmap` (e.g. `colormap`, `colorrange`).

The extension also hooks `Makie.convert_arguments`, so `heatmap(s)`, `heatmap!(ax, s)`, and `contourf(s)` work directly. Display copies are flipped to ascending wavelength order (Makie's heatmap requires sorted axes); the `StreakImage` itself always keeps on-disk order.
