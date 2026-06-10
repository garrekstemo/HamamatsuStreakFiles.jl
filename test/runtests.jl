using Test
using HamamatsuStreakFiles
using Dates
using Aqua

@testset "HamamatsuStreakFiles" begin

    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(HamamatsuStreakFiles; deps_compat = (check_extras = false,))
    end

end
