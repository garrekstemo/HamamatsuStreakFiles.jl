module HamamatsuStreakFiles

using Dates

export AbstractStreakImage, StreakImage

abstract type AbstractStreakImage end

struct StreakImage <: AbstractStreakImage end

end # module
