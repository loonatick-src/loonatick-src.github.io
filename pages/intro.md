+++
title = "Introduction"
hascode = true
date = Date(2023, 4, 28)
rss = "RSS feed not set up yet. Apologies!"

tags = ["julia", "metaprogramming", "comptime"]
+++

# Computing at Compile Time in Julia -- A First Blog Post
This is a short post on the `Val` data type in Julia and using it for
computing at compile-time. Some familiarity with the Julia programming
language is assumed. This is going to be a fairly short post intended
to take this blog on a spin.

## The `Val` Type

`Val` is a very interesting type. From the docs on `Val(c)`:

> Return `Val{c}()`, which contains no run-time data. Types like this can be used to pass the information between functions through the value c, which must be an isbits value or a Symbol. The intent of this construct is to be able to dispatch on constants directly (at compile time) without having to test the value of the constant at run time.

So, `Val` is a paramteric type with one type parameter, and there can only be one possible value of each concrete `Val{T}`. 

```julia:./Val.jl
using Test

@testset "Val types" begin
	@test typeof(Val(7)) <: Val
	@test typeof(Val(0xc0ffee)) == Val{0xc0ffee}
end
```

\output{./Val.jl}

A function that takes an argument of type `::Val{N}`, where `N` is
some `isbits` value, can only be passed the value `Val(N)`.  But, when
I came across `Val` for the first time, the example in the docs did
not quite aid my understanding.

```julia:./Valex.jl
using Test

f(::Val{true}) = "Good"
f(::Val{false}) = "Bad"

@testset "Passing values through Val" begin
	@test f(Val(true)) == "Good"
	@test f(Val(false)) == "Bad"
end
```

\output{./Valex.jl}

So, I tried to check my understanding of the "no-runtime data" aspect
of this type by implementing my own example -- factorial.  Keep in
mind that factorial is just a toy example, but the principles
demonstrated here should carry over to developing more sophisticated
examples.

```julia:./val_factorial.jl
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
```

\output{./val_factorial.jl}

All right that's great and all, but how does one check whether the
`Val` variant is doing the entire calculation at compile-time?

## Verification: Inspect Lowered Code
The various macros that allow inspection of lowered forms of your
source code tell the story.

```julia:./code_inspection.jl
using InteractiveUtils  # loaded by default in the REPL

@show @code_typed factorial(Val(10))
```

\output{./code_inspection.jl}

That's right, it compiles down to `return 3628800`. In case you are
still skeptical, you can also inspect the assembly.

```julia:./asm_inspection.jl
@code_native factorial(Val(10))
```

\output{./asm_inspection.jl}

Ignore the sections and directives (the symbols starting with `.` like
`.text`, `.p2align` etc). The assembly corresponds to `movl $3628800$,
%eax` followed by `retq`, which is basically `return 3628800`.

## Verification: Benchmarking
```julia:./factorial_benchmark.jl
using BenchmarkTools

@btime factorial($(Val(13)))
@btime factorial($(13))
```
\output{./factorial_benchmark.jl}

NB: `factorial` from Julia base uses a lookup table and is quite
fast. A naive, non-tail recursive implementation would be much slower
than both of these.

```julia:./naive_factorial_bench.jl
function factorial_naive(n)
	n == 0 && return 1
	return n * factorial_naive(n-1)
end

@btime factorial_naive($(13))
```
\output{./naive_factorial_bench.jl}

## Bounds Checking

There is still a problem with this -- it does not check for negative values unlike the default factorial in Julia base. We can work around that 
as well.

```julia:./comptime_factorial_final.jl
function factorial(::Val{N}) where N
	N < 0 && throw(DomainError(N, "`factorial` expects non-zero integers."))
	N * factorial(Val(N-1))
end

@show @test_throws DomainError factorial(Val(-1))
```
\output{./comptime_factorial_final.jl}

Is it still comptime?

```julia:./comptime_lowered.jl
println(">>> TYPED CODE <<<")
@show @code_typed factorial(Val(13))
println()
println(">>> BENCHMARK <<<")
@btime factorial($(Val(13)))
```
\output{./comptime_lowered.jl}

Looks like it is.

## What is the use of all this?
We are effectively creating a compile-time lookup table in the julia
runtime. This particular example would be very useful if you are
working with something like Taylor series of many different functions,
and you are calling them repeatedly. By using this, every call to
`factorial` using `Val`s would reduce to a single register allocation
(assuming first compilation is done of course).

As a next step, one could create a macro that would take code like
`factorial(13)` and convert it to `factorial(Val(13))` for ergonomics;
think the `@view` macro that converts array slices (which would incur
overhead of allocation and copying) into views. And since we have an
analogy with `@view`, the next step would be a macro like `@views`
that would recurse into an expression and replace all constants with
their `Val` variants, and a macro that can generate `Val` variants of
structs and functions, similar to `@adapt_structure` from
[Adapt.jl](https://github.com/JuliaGPU/Adapt.jl)
