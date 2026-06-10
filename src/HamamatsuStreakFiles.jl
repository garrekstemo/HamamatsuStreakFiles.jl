module HamamatsuStreakFiles

using Dates

export AbstractStreakImage, StreakImage

include("types.jl")
include("binary.jl")
include("parser.jl")

end # module
