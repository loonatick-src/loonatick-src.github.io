# This file was generated, do not modify it. # hide
using Test

import Base: factorial

factorial(::Val{0}) = 1
factorial(::Val{N}) where {N} = N * factorial(Val(N-1))

@testset "Comptime factorial" begin
    ns = 1:13
    for n in ns
        @test factorial(Val(n)) == factorial(n)
    end
end