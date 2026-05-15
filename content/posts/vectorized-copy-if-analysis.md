---
date: '2026-05-15T10:03:34+02:00'
draft: true
title: 'Thinking in SIMD: `copy_if`'
---

## Introduction

I have a Zen 4 CPU with a bunch of AVX512 feature flags. So I thought - let's
try and use it to implement something, even if it's in the realm of
wheel-reinvention. I started with the following goals.

1. Implement an algorithm that cannot be vectorized by my optimizing compiler,
   even with a polyhedral loop model.
2. Systematically analyze its performance and answer the questions
   1. Is it as fast as it can be?
   2. If not, why? And how can we fix it?
3. Start simple, make it work.

Which means that dead simple algorithms like map/transform, reduce,
adjacent_difference etc are out, as they are very autovectorizable. (TODO:
compiler explorer link). Even 2D stencils are out because [look at this](https://godbolt.org/#z:OYLghAFBqd5QCxAYwPYBMCmBRdBLAF1QCcAaPECAMzwBtMA7AQwFtMQByARg9KtQYEAysib0QXACx8BBAKoBnTAAUAHpwAMvAFYTStJg1DIApACYAQuYukl9ZATwDKjdAGFUtAK4sGIM6SuADJ4DJgAcj4ARpjE/lykAA6oCoRODB7evv5JKWkCIWGRLDFxZgl2mA7pQgRMxASZPn4BldUCtfUEhRHRsfG2dQ1N2a1D3aG9Jf3lAJS2qF7EyOwc5gDMocjeWADUJutuAG5VRMQH2CYaAIIbWzuY%2B4fICgToWFQXV7c3APS/uzMABFdgBWAC0yVCBF2r0YyDouwA1rEwrRdhAgkxEgYEYZdgCEJgmDDMABHLwk9KwggAT3os2%2B/12iwIJlBFjw7KB7Is2m5TxBoV5XNBPI52nBXAF1l2wo5ovFfOs0rF%2B0scoYIql3N5/LVsvlnJVuolAvBu0kACojYq9bqbkdUHh0DT4XRQRA0AxXrsqLRUCSrbsAPoh4iYV7EPAOMOa0jfXZJ5Mp1Op/2BgjBsMRqMxghx1kJm5p0ul17oEAgVIAL0wIZh4WL1zLreTFartfrMIAsoybiYAOxWEvJ/jEDEd6t4OsNuWC3bS9YWecHNy7cK7C1LlfWax4Wb7YeJ0vjydvTsz7u7bQLnc3p7rntbxcHXeWazaQ9Dkcttssrw2QVXZg2fWV9RBA4eVHf9kyNCA8BfLhD1A9UVwg5NmQYEgCAQE9YMNLUOQQtDFxQ3YwI1DCk2ZBRWTwmD/0IkUQIo0iIFvbdGTVGiAQAd0jNlGLbZjgNQ2UONI5CBV43ZiVefD/wtSQADoNCoVjbVYyj0N1ZcCQBFZBFiRSUyHaC/yTczvnMjh5loThQV4PwOC0UhUE4Nw9w1OilhWdV1h4UgCE0Oz5iREB1lUgBOLgzAADlBSQNHWDRQQ0LgNGi/ROEkZzQvczheAUEANGC0L5jgWAkDQFhEjoWJyEoWr6voOJtkMYAzHKMqaFoAhYhKiAogKqJQnqWlOCCsbmGIWkAHkom0U4pt4Wq2EEeaGFoSbXN4LAoi8YA3DEWgSu4fbMBYTrxD20h8AjaoTnOtzMFUKpANWILoUwBy7toPAomICaPCwAqCGjFhVtIE5iCiFJMCBK6btCUA9vmf0mGABQADU8EwPj5sSRhof4QQRDEdgpBkQRFBUdQ7t0dZ9E6lBvJsAGohKyB5lQRJHAEc7wQrKDTA/SwzHWLdruWPD1iBGsGFhyQt3m9ZeFQWHoywbmIHmNoBb8CBXBGPwEmCSZilKPRklSQ3TZtvJDZ6K3%2BgqX7ThqcYHfd%2BxDc6BoXb6OIKm9zxmj0V4uiD6YQ/1xZlip%2BzHPyu6PI4XZVHigA2cFs5VjqjEBMwVK4NSMVwQgSAC5DeBC9HSAgGqqGAJqvUYAbiESeoO/OoKWoa4hwlYVYs9z/PdkL4Bi9LtTeEwfAzhdPQmdIWbiFQPiIcwX6mFpVloYNheADEvAYdoXLhc%2BPWoAMSUnwWs1IP076f3Yz9SYAwldAMjGfj%2B8BfwXrsX%2BwBZicGChGTAy8NDJw4E5NeBV05uGPgAcUzjnPOBcDBF26rPDQFdF7Vw2AkXYHg6qDwCusWYdcKrzCJEwLAcQ9akAitnUEal4qDikKCaK2doqSGivFaKAQ/p5UQWnIqtg9D1y0LMOBZhU5uXTrQ9G8xYapGcJIIAA%3D%3D%3D "2D five-point stencil on Compiler Explorer"). So, I
settled on `std::copy_if`.

Implementing a SIMD implementation is the easy part. Figuring its perforamnce
out ended up being less trivial than I anticipated. I already knew the tools
that I will need.

1. [Google benchmark](https://github.com/google/benchmark) for writing microbenchmarks
2. [likwid-bench](https://github.com/RRZE-HPC/likwid/wiki/Likwid-Bench) for determining performance upper bound on my machine
3. [llvm-mca](https://llvm.org/docs/CommandGuide/llvm-mca.html "llvm-mca documentation") for simulating the kernel on its model of Zen 4
4. [perf-stat](https://www.brendangregg.com/perf.html#OneLiners#CountingEvents:~:text=Counting%20Events "perf-stat one liners") for drill-down performance analysis by counting events

## The baseline
From [cppreference](https://en.cppreference.com/cpp/algorithm/copy),
`std::copy_if` is a dead-simple algorithm.

```c++
template<class InputIt, class OutputIt, class UnaryPred>
OutputIt copy_if(InputIt first, InputIt last,
                 OutputIt d_first, UnaryPred pred)
{
    for (; first != last; ++first)
        if (pred(*first))
        {
            *d_first = *first;
            ++d_first;
        }
    
    return d_first;
}
```

The codegen is also very clean (TODO: compiler explorer link and CFG image). It
is however non-trivial to vectorize because of a loop-carried dependency: the
value of `d_first` in iteration `i+1` depends on the value of `pred(*first)` in
iteration `i`. Let us measure our baseline before we go about vectorizing.

## The benchmark setup
We would like to reduce variance as much as we can. The canonical reference
document for this is the [article on reducing
variance](https://google.github.io/benchmark/reducing_variance.html) in the
Google Benchmark docs (TODO: make this a dedicated reference)

### Sources of variance
Quoted from the [article on reducing
variance](https://google.github.io/benchmark/reducing_variance.html) (emphases mine)

> 1. On multi-core machines not all CPUs/CPU cores/CPU threads run the same speed,
>    so running a benchmark one time and then again may give a different result
>    depending on which CPU it ran on.
> 2. **CPU scaling features** that run on the CPU, like Intel’s Turbo Boost and AMD
>    Turbo Core and Precision Boost, can **temporarily change the CPU frequency even
>    when the using the “performance” governor** on Linux.
> 3. **Context switching** between CPUs, or scheduling competition on the CPU the
>    benchmark is running on.
> 4. Intel **Hyperthreading** or AMD **SMT** causing the same issue as above.
> 5. **Cache effects** caused by **code running on other CPUs**.
> 6. Non-uniform memory architectures (NUMA).

1 and 6 do not apply to my machine, there are no other NUMA domains and all
cores have the same architecture (e.g. no E cores and P cores
differentiation).

### Disabling SMT
We are benchmarking a potentially memory-bound workload. SMT should be disabled
for this.  I already have [[https://github.com/RRZE-HPC/likwid/wiki/likwid-topology][likwid-topology]] installed, so I can just use its
output to determinte thread siblings.
```
  --------------------------------------------------------------------------------
  CPU name:	AMD Ryzen 7 255 w/ Radeon 780M Graphics        
  CPU type:	AMD K19 (Zen4) architecture
  CPU stepping:	2
  ,********************************************************************************
  Hardware Thread Topology
  ,********************************************************************************
  Sockets:		1
  CPU dies:		1
  Cores per socket:	8
  Threads per core:	2
  --------------------------------------------------------------------------------
  HWThread        Thread        Core        Die        Socket        Available
  0               0             0           0          0             *                
  1               0             1           0          0             *                
  2               0             2           0          0             *                
  3               0             3           0          0             *                
  4               0             4           0          0             *                
  5               0             5           0          0             *                
  6               0             6           0          0             *                
  7               0             7           0          0             *                
  8               1             0           0          0             *                
  9               1             1           0          0             *                
  10              1             2           0          0             *                
  11              1             3           0          0             *                
  12              1             4           0          0             *                
  13              1             5           0          0             *                
  14              1             6           0          0             *                
  15              1             7           0          0             *                
  --------------------------------------------------------------------------------
  Socket 0:		( 0 8 1 9 2 10 3 11 4 12 5 13 6 14 7 15 )
  --------------------------------------------------------------------------------
  ,********************************************************************************
  Cache Topology
  ,********************************************************************************
  Level:			1
  Size:			32 kB
  Cache groups:		( 0 8 ) ( 1 9 ) ( 2 10 ) ( 3 11 ) ( 4 12 ) ( 5 13 ) ( 6 14 ) ( 7 15 )
  --------------------------------------------------------------------------------
  Level:			2
  Size:			1 MB
  Cache groups:		( 0 8 ) ( 1 9 ) ( 2 10 ) ( 3 11 ) ( 4 12 ) ( 5 13 ) ( 6 14 ) ( 7 15 )
  --------------------------------------------------------------------------------
  Level:			3
  Size:			16 MB
  Cache groups:		( 0 8 1 9 2 10 3 11 4 12 5 13 6 14 7 15 )
  --------------------------------------------------------------------------------
  ,********************************************************************************
  NUMA Topology
  ,********************************************************************************
  NUMA domains:		1
  --------------------------------------------------------------------------------
  Domain:			0
  Processors:		( 0 8 1 9 2 10 3 11 4 12 5 13 6 14 7 15 )
  Distances:		10
  Free memory:		19259.5 MB
  Total memory:		27831.9 MB
  --------------------------------------------------------------------------------

```

Alternatively, we can use sysfs to e.g. query the thread siblings of CPU1. Note
that.
```sh
  cat /sys/devices/system/cpu/cpu1/topology/thread_siblings_list
```

On my system this outputs `1,9`. Therefore we need to [hot-unplug](https://blogs.oracle.com/linux/introduction-to-cpu-hotplug) CPU 9 like so
```sh
  sudo echo 0 > /sys/devices/system/cpu/cpu8/online
  # or echo 0 | sudo tee /sys/devices/system/cpu/cpu8/online
```

See also https://access.redhat.com/solutions/rhel-smt

### Setting Thread Affinity
Disable SMT first by the way.
```sh
  taskset -c 0 ./mybenchmark
```

But, how do I combine this with perf stat? From `man perf-stat`

```
  -C, --cpu=
         Count only on the list of CPUs provided. Multiple CPUs can be provided
         as a comma-separated list with no space: 0,1. Ranges of CPUs are spec‐
         ified with -: 0-2. In per-thread mode, this option is ignored. The  -a
         option  is still necessary to activate system-wide monitoring. Default
         is to count on all CPUs.
```

and
```
     --no-affinity
         Don’t change scheduler CPU affinities when iterating over  CPUs.  Dis‐
         ables an optimization aimed at minimizing interprocessor interrupts.
```

### Increasing scheduling priority of my benchmark thread
TODO:

### Putting it all together
```sh
  #---- disable SMT ----#
  cat /sys/devices/system/cpu/cpu1/topology/thread_siblings_list
  # 1,9
  echo 0 | sudo tee /sys/devices/system/cpu/cpu9/online
  #---- CPU frequency scaling ----#
  sudo cpupower --cpu 1 frequency-set --governor performance
  # NOTE: you can also set it to a specific frequency
  #---- Run the benchmark ----#
  sudo perf stat -M backend_bound\
       -- chrt -f 50 taskset -c 1\
       ./build/benchmarks/ckl_algorithm_bench\
       --benchmark_filter='BM_CopyIf_Std/16777216'\
       --benchmark_min_time=3s
```

## The baseline benchmark
These are the dimensions along with we can measure performance.
1. Input size (henceforth `n`)
2. Choice of predicate function
3. Input distribution
4. Input entropy

The problem size (1) is trivial to sweep over; varying `n` results in different interactions
with the memory subsystem (caches, hardware prefetchers, DRAM etc).

The predicate and distribution together determine the density/sparsity of the
output. E.g. the predicate `[](auto x){ return x > 0; }` along with a uniformly
distributed input in the range (-1000,1000) results in an expected 50% of the
input values being copied over.

The entropy is not orthogonal to the distribution, but it's worth mentioning
separately. Perhaps I need to think of a better name too. This deterines how
predictable the input is, because all pipelined CPUs have branch-prediction
logic. E.g. if the CPU frontend finds a conditional jump instruction, it will
not wait for its operand to be ready and will instead speculatively jump to a
target address. Misspeceulation reults in a large penalty requiring a complete
pipeline flush and restarting execution. The same predicate and distribution
combination as above can make it difficult for most branch predictors to have a
high branch-miss-rate, thereby adversely affecting throughput.

In the interest of brevity, we fix the predicate (`x > 0`) and distribution
(uniform in (-1000,1000)), and sweep over the problem size. The performance
analysis methods that we shall use here generalize well for tuning the
implementation for inputs along other dimensions.

TODO: show benchmark code, and benchmark plots

## Determining the upper bound
We use likwid-bench (TODO: add link, explain the benchmarks)

TODO: plot these numbers
TODO: redo with SMT disabled

```
$ for size in 16kB 64kB 256kB 1MB 4MB 16MB 64MB 256MB 1GB 4GB; do
    bw=$(likwid-bench -t copy -w S0:${size}:1 2>/dev/null | grep "MByte/s" | awk
	'{print $NF}'); \
	echo "$size $bw"; done
16kB 78409.12
64kB 77420.82
256kB 78184.41
1MB 76051.29
4MB 76036.79
16MB 61339.87
64MB 34870.66
256MB 29974.75
1GB 30401.51
4GB 30270.25

$ for size in 16kB 64kB 256kB 1MB 4MB 16MB 64MB 256MB 1GB 4GB; do
    bw=$(likwid-bench -t copy_avx512 -w S0:${size}:1 2>/dev/null | grep
	"MByte/s" | awk '{print $NF}'); \
	echo "$size $bw"; done
16kB 308507.49
64kB 148141.92
256kB 152178.57
1MB 130479.16
4MB 123643.21
16MB 74869.02
64MB 36020.78
256MB 27302.26
1GB 26955.80
4GB 26570.57
```


## First SIMD Attempt
There are three parts to the loop body.
1. Load from `&input[i]`
2. Evaluate predicate to get a `bool` value
3. Conditionally store the loaded value to destination based on the previous
   result and update output counter/pointer.
   
1 and 2 are straightforward in most SIMD implementations. Let `N` be the width
of the SIMD registers (TODO: add note on register width vs lanes). E.g. in
AVX-512 for loading 32-bit values, `N = 512/32 = 16`.

1. Load into a SIMD register from `&input[i]`
   - `_mm512_loadu_epi32` and friends (TODO: add link to Intel intrinsics reference)
2. Evalute predicate on SIMD register to get a SIMD mask value (TODO: add
   footnote about masks)
   - For our predicate (`>(0)`), `const auto zero = _mm512_setzero_epi32();
      return _mm512_cmpgt_epi32_mask(a, zero);`
3. Contiguously store the SIMD lanes for whom the corresponding mask bit is 1.
   - Turns out that there is an instruction that does just that:
     `_mm512_mask_compressstoreu_epi32`.
   - And the destination pointer can be updated by getting a popcount on the
     mask value that we got from step 2.
	 
	 
Of course, we also need another loop to handle the remaining elements that are
less than the size of the SIMD width. Putting everything together, and unrolling
once for the fun of it, we get this.

```c++
namespace ck {

template <typename Arg>
struct positive {
  bool operator()(const Arg& arg) const& {
    return arg > 0;
  }
  
  bool operator()(const Arg&& arg) const& {
    return arg > 0;
  }
};

template <>
struct positive<__m512i> {
  __mmask16 operator()(const __m512i& a) const& {
    const auto zero = _mm512_setzero_epi32();
    return _mm512_cmpgt_epi32_mask(a, zero);
  }

  __mmask16 operator()(const __m512i&& a) const& {
    const auto zero = _mm512_setzero_epi32();
    return _mm512_cmpgt_epi32_mask(a, zero);
  }
};
  
template <template <typename> class Predicate>
int *copy_if(int const *input, int *output, size_t n, const Predicate<int> &p) {
  const auto vp = Predicate<__m512i>();
  constexpr auto vlen = 16;  // (512 / 8) / sizeof(int);
  constexpr auto unroll = 2;
  constexpr auto stride = vlen * unroll;
  auto sn = n - (n % stride);
  int *out = output;
  for (size_t i = 0; i < sn; i += stride) {
    // 1. load from memory into zmm register
    const auto v_in1 = _mm512_loadu_epi32(input + i);
    const auto v_in2 = _mm512_loadu_epi32(input + i + vlen);
	// 2. evaluate predicate to get predicate mask
    const __mmask16 m1 = vp(v_in1);
    const __mmask16 m2 = vp(v_in2);
	// 3.1 Contiguously store values from zmm register where mask bit is 1
    // dependencies galore!
    _mm512_mask_compressstoreu_epi32(out, m1, v_in1);
    const auto d1 = _mm_popcnt_u32(m1);
    _mm512_mask_compressstoreu_epi32(out + d1, m2, v_in2);
    const auto d2 = d1 + _mm_popcnt_u32(m2);
	// 3.2 update output pointer
    out += d2;
  }
  // handle remainder
  for (auto i = sn; i < n; i++) {
    if (p(input[i])) {
  	  *out = input[i];
	  out++;
    }
  }
  return out;
}
} // namespace ck
```

[Check it out on compiler explorer](https://godbolt.org/#z:OYLghAFBqd5QCxAYwPYBMCmBRdBLAF1QCcAaPECAMzwBtMA7AQwFtMQByARg9KtQYEAysib0QXACx8BBAKoBnTAAUAHpwAMvAFYTStJg1DIApACYAQuYukl9ZATwDKjdAGFUtAK4sGIM2akrgAyeAyYAHI%2BAEaYxCAArADMpAAOqAqETgwe3r7%2BgemZjgKh4VEssfHJtpj2JQxCBEzEBLk%2BfgG19dlNLQRlkTFxiSkKza3t%2BV3j/YMVVaMAlLaoXsTI7BzmSWHI3lgA1CZJbngsLGEExGEAdAgn2CYaAILPL8xsCqlMm4fIAGtjgB2Kyvd4ETAsVIGSHHU4EACeqUYrEwhxexGAj3e42IXgchyKWQAbuiTKD3odDtFUJ5DqgUcQmERiBAlhA0AxxhiseYAGyHFrAJb/ATjAUgsEvanU4iYAjrBhCrHw7CHDQnaXUikAESpx1e1Np9MZcRZJHZnPFBF52LM/MlwtFXIlDqlBrlCqVKuAao1WoNevewaS0ohUJhLPJpxxrzxBNtxMcZJObgA%2BumWAkuGY8I8PUbDpmLkwFACuIKzczWVbXbaSzm806XTbJRTtbLqfWhV4iIcAF5xVDw3XFi5N9NKAhD4iodOYVJ4JJmdmBotd%2BWK4jKrPZ3Pp5DQ4AEBdLldZssAiBMUiD4dLdcy2XB8Eb4t7q%2BVhlMi1sjk9o2ub5g6LZityBDtpS77djavb9rOI4nGOe6TtOiFnsuq6PmGnqyluPqoQeR6pCemEXiwV43neiE4Z2OrAvqRahp2EbQrCMZuJC7HRvCXHIqibAFvsZYKIcyjyvgoiQnGLxXIcABUaCpIi6Z4FQEDyT2ClhKkfZ3vJClrAQekEHemRDumtoMHePYSZgUnRmmVwFgKqSih2Bo9kwfYjiSqSjuJkl4NJmBpkBzZJNga64UW9aYKoqTEPBfn0MqyGHJWWrUgA9DlhwQE2hz5QAHKK%2BUWZgqAaVcdFeTaCVJSlhxeAwc60LQgVmE%2BsEQY1yU%2Bf2eJ4EcGUkmliktW1ni0D1zUKOlSRjsqAC0BXpWYCSHMNWB1UWhnGYFxmmXN/DJRAlVWYceCBZqYbXXx20MNlN3WBlO2YB50HPrl%2BVcLchy0KgTDoIcVBziwhxsCwJCItdggjgOFyHPKwB4OMcR4d5vmHCSakMFwgVEWY6ZAyDXjkauul9scljXXtP3gTyg1%2BfjZhExOB5k%2BgFOLlhmkMKZtMWA91i42lDPPAAnHlhxmADmAkmIXi8UlDkhbx/bAAqRLBaFUNXljcElpR5bfiwhNjakEB42EXAM12gGfmbgosOzVs22zksaDL%2BVJLchMeIIeDAF4awKLQcPjCQ6JK94mBieDqCQ0jkOo%2BjkLJQA7ggcToqbQLRIQ11iVweGy1gKIMFgDDIHgCeHMAYgx2AYB4cTl7loeydqwofespgvPnquxl3hbd62wTDuytj/boJbS3jiw6bpKkyCCOmXgrhAFvT9SHcF930Lyn30fykP/OHWL89j4EuNe3NvXMzj6Du4v8/C0vK%2BMuvp5b6ubtva%2B0OP7dmXhUjoF4sdGm6QriY3fFfSwGVX5zVfM%2BWWCBDDoHoCjKETAwhYGIAaM6BUWai0XgtF6j1nr3RAlYSwX16LXSoAVa21NIIJAsPmBIuoliMKDD7akRkaYZXYSYTh3D9SxTeIIhkfY3pIOkV2NBDEmLPgIjuORkFpFoN0a8EkqARpgzpALW02l2EGUEIpaBZltp4EstZfh75AQgBQIyVS6kBamTvDYu8Nl/gAlccmPAqZTguSip5RiktGIcBWLQTgCReB%2BA4FoUgqBOBuAUSLBQawNjkjMEkHgpACCaFiSsQJkhQFS0kPyDQXBgRSy4EkZpJVAjxI4JIJJpS0mcF4AoEAGhimlJWHAWASA0DQjoHEcglAJlLnoPEESRgAhcEGTQWgmd%2BkQGiN0ouzBiCIk4EUvZLREQAHlojaEwA4I5vAJlsEEGchgkdulYGiF4YAbgxC0H6dwXgWBKJGHECk/5eB5QOBCQnbpCVrl9i2EUuB7TUm0DwNEZkByPBYG6dcc4tzSBkmILSJQuo8FArCKAEFKwqAGGAAoAAavXLOZyq54v4IIEQYh2BSBkIIRQKh1AgtILoFIBgjAoCyfoVF/TIArEZA0X5K1xjoGQqYJBlgCmHBWpRDYDwloDgYASyQmqzlJE1QAdW%2BeahK1wmC8FQASm4WBpXsm6NchoLhq5TD8FwII1d5jDHiD64JAgvV6GDQwf1lQRg%2BrsG63oEw2ieA6HoWNEKBB9FaJGxYMaE2hpzXMMIQwo2BpWDk9YmwJBxISV0wV6SOCHFUCVfkK1%2BRGqWX6AIAdbgaAKrgQgJBaaFKWLwEplLSAQHGVQYAMzOSMEzj8eUghflFLmVM4gEQ0ScEbc21t/xRUdvlv9VJ6tWQjT0MK0g%2By5xZ2uJgOoTBETGW6amyE6AABirU03JP4KgUxTMCAKUsQBu8rVMjAHCKDIGRglicGKfKTAZ6NBVo4Iky93S61uDfQAcQbU2ltbb91y0Pd23t%2BBWSDp9YcDwkyFmDqSMOoZY6J0gF8RQa0NG4gbrYFuvDu721Ea7cesjJAz0%2BrZcIUQ4huXib5WobpF6s7MlSLc5DqHkmpLrWcvsQtqq4Z3QRwwB7BMFWo/MuIdGGOjq0Hw0gucQYjBdYEhI/JbjAg0MkKWrSNBNv5PyLgUt9CcE6Wh2tvTbB6Cs2UwLHAzA1o02FyLNmCWZGcJIIAA%3D).
## First moment of truth
## CPU microarchitecture crash course
## Performance counters crash course
## A methodology for performance analysis using counters
##
### Level 1

### Level 2: Frontend Bound

### Level 3: Frontend Latency Bound
