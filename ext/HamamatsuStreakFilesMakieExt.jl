module HamamatsuStreakFilesMakieExt

using HamamatsuStreakFiles
using Makie

# Display copy in ascending-wavelength order. The struct preserves on-disk
# (often descending) order, so flip the axis and the matrix together; Makie's
# heatmap requires sorted axis vectors.
function _ascending(s::StreakImage)
    if length(s.wavelength) >= 2 && s.wavelength[1] > s.wavelength[end]
        x = reverse(s.wavelength)
        z = reverse(s.counts; dims=1)
    else
        x = s.wavelength
        z = s.counts
    end
    issorted(x) || @warn "HamamatsuStreakFiles: non-monotonic wavelength axis; " *
        "heatmap cell placement may be misleading"
    return x, z
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

Axis defaults: `xlabel = "Wavelength (<xunits>)"`, `ylabel = "Time (<yunits>)"`,
plus a colorbar labelled with `zunits`.
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
    fap = Makie.heatmap(x, s.time, z;
        axis = merge(default_axis, axis),
        kwargs...,
    )
    Makie.Colorbar(fap.figure[1, 2], fap.plot; label = s.zunits)
    return fap
end

end # module
