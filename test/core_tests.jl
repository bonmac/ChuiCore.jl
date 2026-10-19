@testitem "module loads" tags = [:unit] begin
    @test ChuiCore isa Module
    @test nameof(ChuiCore) === :ChuiCore
    # Pre-release scaffold: nothing exported yet (only the module's own name).
    @test names(ChuiCore) == [:ChuiCore]
    @test !isempty(string(@doc ChuiCore))
end
