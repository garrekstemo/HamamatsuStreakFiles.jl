using Test
using HamamatsuStreakFiles
using Dates
using Aqua

@testset "HamamatsuStreakFiles" begin

    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(HamamatsuStreakFiles; deps_compat = (check_extras = false,))
    end

    @testset "StreakImage type" begin
        s = StreakImage(
            [662.4, 500.0, 395.2],          # wavelength, descending (on-disk order)
            [0.0, 1.0],                      # time
            [1.0 4.0; 2.0 5.0; 3.0 6.0],     # counts (3 wavelength × 2 time)
            "nm", "ns", "Count",
            DateTime(2026, 6, 2, 13, 17, 16),
            "HPD-TA", "C11440-36U", "C10910", "50 ns",
            554.969, "50 g/mm", "14 ms", 47808,
            Dict("Application" => Dict("Software" => "HPD-TA")),
        )

        @test s isa AbstractStreakImage
        @test StreakImage <: AbstractStreakImage
        @test size(s) == (3, 2)
        @test s.counts[1, 2] == 4.0
        @test s.wavelength[1] > s.wavelength[end]   # descending order preserved

        compact = sprint(show, s)
        @test contains(compact, "StreakImage(3×2")
        @test contains(compact, "nm")
        @test !contains(compact, '\n')

        full = sprint(show, MIME("text/plain"), s)
        @test contains(full, "StreakImage")
        @test contains(full, "C11440-36U")
        @test contains(full, "C10910")
        @test contains(full, "50 ns")
        @test contains(full, "554.969")
        @test contains(full, "50 g/mm")
        @test contains(full, "14 ms")
        @test contains(full, "47808")
        @test contains(full, "Acquired:")
        @test contains(full, "2026-06-02 13:17:16")

        # All-sentinel image: optional lines are suppressed, no year-0001 leak
        bare = StreakImage(Float64[], Float64[], zeros(0, 0),
                           "", "", "", DateTime(1),
                           "", "", "", "", 0.0, "", "", 0,
                           Dict{String, Dict{String, String}}())
        bare_show = sprint(show, MIME("text/plain"), bare)
        @test !contains(bare_show, "Acquired:")
        @test !contains(bare_show, "0001")
        @test !contains(bare_show, "Camera:")
        @test sprint(show, bare) == "StreakImage(0×0)"
    end

end
