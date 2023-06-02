# This file was generated, do not modify it. # hide
using Test

f(::Val{true}) = "Good"
f(::Val{false}) = "Bad"

@testset "Passing values through Val" begin
	@test f(Val(true)) == "Good"
	@test f(Val(false)) == "Bad"
end