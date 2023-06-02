# This file was generated, do not modify it. # hide
println(">>> TYPED CODE <<<")
@show @code_typed factorial(Val(13))
println()
println(">>> BENCHMARK <<<")
@btime factorial($(Val(13)))