# This file was generated, do not modify it. # hide
using BenchmarkTools

@btime factorial($(Val(13)))
@btime factorial($(13))