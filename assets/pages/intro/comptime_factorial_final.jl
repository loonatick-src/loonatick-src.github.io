# This file was generated, do not modify it. # hide
function factorial(::Val{N}) where N
	N < 0 && throw(DomainError(N, "`factorial` expects non-zero integers."))
	N * factorial(Val(N-1))
end

@show @test_throws DomainError factorial(Val(-1))