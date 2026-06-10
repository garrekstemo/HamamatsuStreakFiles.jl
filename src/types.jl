"""
    AbstractStreakImage

Abstract supertype for Hamamatsu streak-camera images.
"""
abstract type AbstractStreakImage end

"""
    StreakImage <: AbstractStreakImage

A Hamamatsu HPD-TA/HiPic `.img` streak-camera image: wavelength × time → counts,
plus instrument metadata. Construct with `StreakImage(path)`.

# Fields
- `wavelength::Vector{Float64}` — spectral axis (typically nm). On-disk order is
  preserved; HPD-TA commonly stores wavelength descending (red → blue).
- `time::Vector{Float64}` — temporal axis (typically ns).
- `counts::Matrix{Float64}` — size `(length(wavelength), length(time))`;
  `counts[i, j]` is the signal at `wavelength[i]`, `time[j]`.
- `xunits::String`, `yunits::String`, `zunits::String` — axis unit labels
  (e.g. `"nm"`, `"ns"`, `"Count"`).
- `date::DateTime` — acquisition timestamp (`[Application]` Date + Time).
- `software::String` — acquisition software (`[Application]` Software), e.g. `"HPD-TA"`.
- `camera::String` — readout camera model (`[Camera]` CameraName).
- `streak_device::String` — streak unit model (`[Streak camera]` DeviceName).
- `time_range::String` — sweep window, raw token incl. unit (`[Streak camera]`
  "Time Range"), e.g. `"50 ns"`.
- `center_wavelength::Float64` — spectrograph center wavelength in nm
  (`[Spectrograph]` Wavelength).
- `grating::String` — spectrograph grating (`[Spectrograph]` Grating).
- `exposure::String` — exposure time, raw token incl. unit (`[Acquisition]`
  ExposureTime), e.g. `"14 ms"`.
- `n_exposures::Int` — accumulated exposure count (`[Acquisition]` NrExposure).
- `metadata::Dict{String, Dict{String, String}}` — the full raw comment block,
  keyed by `[Section]` name, then key.

# Sentinels for missing fields

| Field type | Sentinel |
|------------|----------|
| `String`   | `""` |
| `Float64`  | `0.0` |
| `Int`      | `0` |
| `DateTime` | `DateTime(1)` (year 0001) |

For strict "present vs. missing" checks, inspect the raw `metadata` dict.
"""
struct StreakImage <: AbstractStreakImage
    wavelength::Vector{Float64}
    time::Vector{Float64}
    counts::Matrix{Float64}
    xunits::String
    yunits::String
    zunits::String
    date::DateTime
    software::String
    camera::String
    streak_device::String
    time_range::String
    center_wavelength::Float64
    grating::String
    exposure::String
    n_exposures::Int
    metadata::Dict{String, Dict{String, String}}
end

Base.size(s::AbstractStreakImage) = size(s.counts)

function Base.show(io::IO, s::StreakImage)
    print(io, "StreakImage(", length(s.wavelength), "×", length(s.time))
    if !isempty(s.wavelength)
        print(io, ", ", round(s.wavelength[1], digits=1), "–",
              round(s.wavelength[end], digits=1), " ", s.xunits)
    end
    if !isempty(s.time)
        print(io, ", ", round(s.time[1], digits=2), "–",
              round(s.time[end], digits=2), " ", s.yunits)
    end
    print(io, ")")
end

function Base.show(io::IO, ::MIME"text/plain", s::StreakImage)
    println(io, "StreakImage")
    println(io, "  Size:         ", length(s.wavelength), " wavelength × ",
            length(s.time), " time")
    if !isempty(s.wavelength)
        println(io, "  Wavelength:   ", round(s.wavelength[1], digits=2), " – ",
                round(s.wavelength[end], digits=2), " ", s.xunits)
    end
    if !isempty(s.time)
        println(io, "  Time:         ", round(s.time[1], digits=3), " – ",
                round(s.time[end], digits=3), " ", s.yunits)
    end
    !isempty(s.camera) && println(io, "  Camera:       ", s.camera)
    !isempty(s.streak_device) && println(io, "  Streak unit:  ", s.streak_device)
    !isempty(s.time_range) && println(io, "  Time range:   ", s.time_range)
    if s.center_wavelength > 0
        println(io, "  Spectrograph: ", s.center_wavelength, " nm center",
                isempty(s.grating) ? "" : ", " * s.grating)
    end
    if !isempty(s.exposure)
        println(io, "  Exposure:     ", s.exposure,
                s.n_exposures > 0 ? " × " * string(s.n_exposures) : "")
    end
    if s.date != DateTime(1)
        println(io, "  Acquired:     ", Dates.format(s.date, "yyyy-mm-dd HH:MM:SS"))
    end
    print(io, "  Metadata:     ", length(s.metadata), " sections")
end
