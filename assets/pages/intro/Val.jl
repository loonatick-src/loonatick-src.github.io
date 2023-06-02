# This file was generated, do not modify it. # hide
using Test

@testset "Val types" begin
	@test typeof(Val(7)) <: Val
	@test typeof(Val(0xc0ffee)) == Val{0xc0ffee}
end