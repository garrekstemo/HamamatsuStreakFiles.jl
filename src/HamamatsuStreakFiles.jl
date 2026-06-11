"""
    HamamatsuStreakFiles

Read Hamamatsu HPD-TA / HiPic `.img` (ITEX) streak-camera files.

The single entry point is [`StreakImage`](@ref)`(path)`, which returns the
wavelength axis, time axis, and `counts[wavelength, time]` matrix together
with the full instrument metadata. On-disk axis order is preserved (HPD-TA
commonly stores wavelength descending). With Makie loaded, `plot(s)` and
`heatmap(s)` give a quick-look view via a package extension.
"""
module HamamatsuStreakFiles

using Dates

export AbstractStreakImage, StreakImage

include("types.jl")
include("binary.jl")
include("parser.jl")

end # module
