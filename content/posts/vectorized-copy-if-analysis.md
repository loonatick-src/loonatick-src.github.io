---
date: '2026-05-25T10:03:34+02:00'
draft: false
title: 'Accelerating copy_if using SIMD'
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
adjacent_difference etc are out, as [they are very autovectorizable](https://godbolt.org/#g:!((g:!((g:!((h:codeEditor,i:(filename:'1',fontScale:14,fontUsePx:'0',j:1,lang:c%2B%2B,selection:(endColumn:2,endLineNumber:11,positionColumn:2,positionLineNumber:11,selectionStartColumn:2,selectionStartLineNumber:11,startColumn:2,startLineNumber:11),source:'%23include+%3Calgorithm%3E%0A%23include+%3Cnumeric%3E%0A%23include+%3Cvector%3E%0A%0Aint+reduce(std::vector%3Cint%3E+const%26+input)+%7B%0A++++return+std::reduce(input.begin(),+input.end(),+0)%3B%0A%7D%0A%0Avoid+adjacent_difference(std::vector%3Cint%3E+const%26+input,+std::vector%3Cint%3E%26+output)+%7B%0A++++std::adjacent_difference(input.cbegin(),+input.cend(),+output.begin())%3B%0A%7D'),l:'5',n:'0',o:'C%2B%2B+source+%231',t:'0')),k:43.29460179133382,l:'4',n:'0',o:'',s:0,t:'0'),(g:!((h:compiler,i:(compiler:clang2210,filters:(b:'0',binary:'1',binaryObject:'1',commentOnly:'0',debugCalls:'1',demangle:'0',directives:'0',execute:'1',intel:'0',libraryCode:'0',trim:'1',verboseDemangling:'0'),flagsViewOpen:'1',fontScale:14,fontUsePx:'0',j:3,lang:c%2B%2B,libs:!(),options:'-std%3Dc%2B%2B23+-march%3Dznver4+-O3+-Wall+-Wextra',overrides:!(),selection:(endColumn:1,endLineNumber:1,positionColumn:1,positionLineNumber:1,selectionStartColumn:1,selectionStartLineNumber:1,startColumn:1,startLineNumber:1),source:1),l:'5',n:'0',o:'+x86-64+clang+22.1.0+(Editor+%231)',t:'0'),(h:cfg,i:(centerparents:'1',compilerName:'x86-64+clang+22.1.0',editorid:1,j:3,narrowtreelayout:'0',selectedFunction:'foo(std::vector%3Cint,+std::allocator%3Cint%3E%3E+const%26,+std::vector%3Cint,+std::allocator%3Cint%3E%3E%26):',treeid:0),l:'5',n:'0',o:'CFG+x86-64+clang+22.1.0+(Editor+%231,+Compiler+%233)',t:'0'),(h:output,i:(compilerName:'x86-64+clang+22.1.0',editorid:1,fontScale:14,fontUsePx:'0',j:3,wrap:'1'),l:'5',n:'0',o:'Output+of+x86-64+clang+22.1.0+(Compiler+%233)',t:'0')),header:(),k:56.70539820866619,l:'4',n:'0',o:'',s:0,t:'0')),l:'2',n:'0',o:'',t:'0')),version:4). Even 2D stencils are out because [look at this](https://godbolt.org/#z:OYLghAFBqd5QCxAYwPYBMCmBRdBLAF1QCcAaPECAMzwBtMA7AQwFtMQByARg9KtQYEAysib0QXACx8BBAKoBnTAAUAHpwAMvAFYTStJg1DIApACYAQuYukl9ZATwDKjdAGFUtAK4sGIM6SuADJ4DJgAcj4ARpjE/lykAA6oCoRODB7evv5JKWkCIWGRLDFxZgl2mA7pQgRMxASZPn4BldUCtfUEhRHRsfG2dQ1N2a1D3aG9Jf3lAJS2qF7EyOwc5gDMocjeWADUJutuAG5VRMQH2CYaAIIbWzuY%2B4fICgToWFQXV7c3APS/uzMABFdgBWAC0yVCBF2r0YyDouwA1rEwrRdhAgkxEgYEYZdgCEJgmDDMABHLwk9KwggAT3os2%2B/12iwIJlBFjw7KB7Is2m5TxBoV5XNBPI52nBXAF1l2wo5ovFfOs0rF%2B0scoYIql3N5/LVsvlnJVuolAvBu0kACojYq9bqbkdUHh0DT4XRQRA0AxXrsqLRUCSrbsAPoh4iYV7EPAOMOa0jfXZJ5Mp1Op/2BgjBsMRqMxghx1kJm5p0ul17oEAgVIAL0wIZh4WL1zLreTFartfrMIAsoybiYAOxWEvJ/jEDEd6t4OsNuWC3bS9YWecHNy7cK7C1LlfWax4Wb7YeJ0vjydvTsz7u7bQLnc3p7rntbxcHXeWazaQ9Dkcttssrw2QVXZg2fWV9RBA4eVHf9kyNCA8BfLhD1A9UVwg5NmQYEgCAQE9YMNLUOQQtDFxQ3YwI1DCk2ZBRWTwmD/0IkUQIo0iIFvbdGTVGiAQAd0jNlGLbZjgNQ2UONI5CBV43ZiVefD/wtSQADoNCoVjbVYyj0N1ZcCQBFZBFiRSUyHaC/yTczvnMjh5loThQV4PwOC0UhUE4Nw9w1OilhWdV1h4UgCE0Oz5iREB1lUgBOLgzAADlBSQNHWDRQQ0LgNGi/ROEkZzQvczheAUEANGC0L5jgWAkDQFhEjoWJyEoWr6voOJtkMYAzHKMqaFoAhYhKiAogKqJQnqWlOCCsbmGIWkAHkom0U4pt4Wq2EEeaGFoSbXN4LAoi8YA3DEWgSu4fbMBYTrxD20h8AjaoTnOtzMFUKpANWILoUwBy7toPAomICaPCwAqCGjFhVtIE5iCiFJMCBK6btCUA9vmf0mGABQADU8EwPj5sSRhof4QQRDEdgpBkQRFBUdQ7t0dZ9E6lBvJsAGohKyB5lQRJHAEc7wQrKDTA/SwzHWLdruWPD1iBGsGFhyQt3m9ZeFQWHoywbmIHmNoBb8CBXBGPwEmCSZilKPRklSQ3TZtvJDZ6K3%2BgqX7ThqcYHfd%2BxDc6BoXb6OIKm9zxmj0V4uiD6YQ/1xZlip%2BzHPyu6PI4XZVHigA2cFs5VjqjEBMwVK4NSMVwQgSAC5DeBC9HSAgGqqGAJqvUYAbiESeoO/OoKWoa4hwlYVYs9z/PdkL4Bi9LtTeEwfAzhdPQmdIWbiFQPiIcwX6mFpVloYNheADEvAYdoXLhc%2BPWoAMSUnwWs1IP076f3Yz9SYAwldAMjGfj%2B8BfwXrsX%2BwBZicGChGTAy8NDJw4E5NeBV05uGPgAcUzjnPOBcDBF26rPDQFdF7Vw2AkXYHg6qDwCusWYdcKrzCJEwLAcQ9akAitnUEal4qDikKCaK2doqSGivFaKAQ/p5UQWnIqtg9D1y0LMOBZhU5uXTrQ9G8xYapGcJIIAA%3D%3D%3D "2D five-point stencil on Compiler Explorer"). So, I
settled on `std::copy_if`.

Implementing a SIMD implementation is the easy part. Figuring its perforamnce
out ended up being less trivial than I anticipated. I already knew the tools
that I will need.

1. [Google benchmark](https://github.com/google/benchmark) for writing microbenchmarks
2. [likwid-bench](https://github.com/RRZE-HPC/likwid/wiki/Likwid-Bench) for determining performance upper bound on my machine
3. [llvm-mca](https://llvm.org/docs/CommandGuide/llvm-mca.html "llvm-mca documentation") for simulating the kernel on its model of Zen 4
4. [perf-stat](https://www.brendangregg.com/perf.html#OneLiners#CountingEvents:~:text=Counting%20Events "perf-stat one liners") for drill-down performance analysis by counting events


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

The codegen is also very clean ([compiler explorer link](https://godbolt.org/#g:!((g:!((g:!((h:codeEditor,i:(filename:'1',fontScale:14,fontUsePx:'0',j:1,lang:c%2B%2B,selection:(endColumn:61,endLineNumber:5,positionColumn:61,positionLineNumber:5,selectionStartColumn:61,selectionStartLineNumber:5,startColumn:61,startLineNumber:5),source:'%23include+%3Calgorithm%3E%0A%23include+%3Cvector%3E%0A%0Avoid+foo(std::vector%3Cint%3E+const%26+input,+std::vector%3Cint%3E%26+output)+%7B%0A++++std::copy_if(input.cbegin(),+input.cend(),+output.begin(),+%5B%5D(auto+const%26+n)+%7B+return+n+%3E+0%3B+%7D)%3B%0A%7D'),l:'5',n:'0',o:'C%2B%2B+source+%231',t:'0')),k:43.29460179133382,l:'4',n:'0',o:'',s:0,t:'0'),(g:!((h:compiler,i:(compiler:clang2210,filters:(b:'0',binary:'1',binaryObject:'1',commentOnly:'0',debugCalls:'1',demangle:'0',directives:'0',execute:'1',intel:'0',libraryCode:'0',trim:'1',verboseDemangling:'0'),flagsViewOpen:'1',fontScale:14,fontUsePx:'0',j:3,lang:c%2B%2B,libs:!(),options:'-std%3Dc%2B%2B23+-march%3Dznver4+-O3+-Wall+-Wextra',overrides:!(),selection:(endColumn:1,endLineNumber:1,positionColumn:1,positionLineNumber:1,selectionStartColumn:1,selectionStartLineNumber:1,startColumn:1,startLineNumber:1),source:1),l:'5',n:'0',o:'+x86-64+clang+22.1.0+(Editor+%231)',t:'0'),(h:cfg,i:(centerparents:'1',compilerName:'x86-64+clang+22.1.0',editorid:1,j:3,narrowtreelayout:'0',selectedFunction:'foo(std::vector%3Cint,+std::allocator%3Cint%3E%3E+const%26,+std::vector%3Cint,+std::allocator%3Cint%3E%3E%26):',treeid:0),l:'5',n:'0',o:'CFG+x86-64+clang+22.1.0+(Editor+%231,+Compiler+%233)',t:'0'),(h:output,i:(compilerName:'x86-64+clang+22.1.0',editorid:1,fontScale:14,fontUsePx:'0',j:3,wrap:'1'),l:'5',n:'0',o:'Output+of+x86-64+clang+22.1.0+(Compiler+%233)',t:'0')),header:(),k:56.70539820866619,l:'4',n:'0',o:'',s:0,t:'0')),l:'2',n:'0',o:'',t:'0')),version:4)). It
is however non-trivial to vectorize because of a loop-carried dependency: the
value of `d_first` in iteration `i+1` depends on the value of `pred(*first)` in
iteration `i`. Let us measure our baseline before we go about vectorizing.

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
logic. E.g. if the CPU frontend (FE) finds a conditional jump instruction, it will
not wait for its operand to be ready and will instead speculatively jump to a
target address. Misspeculation reults in a large penalty requiring a complete
pipeline flush and restarting execution. The same predicate and distribution
combination as above can make it difficult for most branch predictors to have a
high branch-miss-rate, thereby adversely affecting throughput.

In the interest of brevity, we fix the predicate (`x > 0`) and distribution
(uniform in (-1000,1000)), and sweep over the problem size. The performance
analysis methods that we shall use here generalize well for tuning the
implementation for inputs along other dimensions.

We use likwid-bench

{{<fig key="likwid-bench-copy" src="/images/likwid-bench.png"
   caption="Speed (MB/s) achieved by the `copy` and `copy_avx512` benchmarks in likwid-bench"
   Align="center">}}

Reproduce using the following commands:
```
$ for size in 16kB 64kB 256kB 1MB 4MB 16MB 64MB 256MB 1GB 4GB; do
	bw=$(likwid-pin -c 1 likwid-bench -t copy_avx512 -w S0:${size}:1 2>/dev/null |
	grep "MByte/s" |
	awk '{print $NF}'); \
	echo "$size $bw";
  done


$ for size in 16kB 64kB 256kB 1MB 4MB 16MB 64MB 256MB 1GB 4GB; do
	bw=$(likwid-pin -c 1 likwid-bench -t copy -w S0:${size}:1 2>/dev/null |
	grep "MByte/s" |
	awk '{print $NF}');
	echo "$size $bw";
  done
```

## First SIMD Attempt
There are three parts to the loop body.
1. Load from `&input[i]`
2. Evaluate predicate to get a `bool` value
3. Conditionally store the loaded value to destination based on the previous
   result and update output counter/pointer.
   
1 and 2 are straightforward in most SIMD implementations. Let `N` be the width
of the SIMD registers. E.g. in
AVX-512 for loading 32-bit values, `N = 512/32 = 16`.

1. Load into a SIMD register from `&input[i]`
   - `_mm512_loadu_epi32` and friends (TODO: add link to Intel intrinsics reference)
2. Evalute predicate on SIMD register to get a SIMD mask value (TODO: add
   footnote about masks)
   - For our predicate (`>(0)`), `const auto zero = _mm512_setzero_epi32();
      return _mm512_cmpgt_epi32_mask(a, zero);`
3. Contiguously store the SIMD lanes for whom the corresponding mask bit is 1.
   - Turns out that there is an instruction that does just that:
     `_mm512_mask_compressstoreu_epi32`[^1].
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

{{<rawhtml>}}
<iframe width="800px" height="800px" src="https://godbolt.org/e?readOnly=true&hideEditorToolbars=true#z:OYLghAFBqd5QCxAYwPYBMCmBRdBLAF1QCcAaPECAMzwBtMA7AQwFtMQByARg9KtQYEAysib0QXACx8BBAKoBnTAAUAHpwAMvAFYTStJg1DIApACYAQuYukl9ZATwDKjdAGFUtAK4sGIM6SuADJ4DJgAcj4ARpjEIABs8aQADqgKhE4MHt6%2B/ilpGQIhYZEsMXGJtpj2jgJCBEzEBNk%2BfgF2mA6Z9Y0ExRHRsQlJCg1NLbntY32hA2VDiQCUtqhexMjsHOYAzKHI3lgA1CbbbngsLKEExKEAdAgn2CYaAILPL8xsCslMG4fIAGtjgB2Kyvd4ETAsZIGSHHU4EACeyUYrEwhxexGAj3eo2IXgch1S6UcADd0SZQe9DocoqhPIdUCjiEwiMQIIsIGgGKMMVjzPFDo1gIt/gJRgKQWCXjSacRMAQ1gwhVj4dhDhoTtKaZSACLU46vGl0hlM2Kskgcrnigh87FmeKS4Wi7kSh1Sg1yhVKlXANUarUGvXvYPbaUQqEw1kU044154gm24kZcknNwAfXTLAArFwzHhHh6jYdMxcmAoAVxBWaWWyra7baXc/mnS6bZLKdrZTSG0KvERDgAvWKoeG6ksXZvppQEYfEVDpzDJPDbMwcwPF7vyxXEZVZnN59PIaHAAiL5errPlgEQJikIcjxYbmWy4Pgzcl/fXquM5kW9mcr2TZ5gWDqtmKPIEB2VIfj2Np9gOc6jic477lOM5IeeK5rk%2BYaerK24%2Bmhh7Hskp5YZeLDXre95IbhXY6sC%2BrFqGXYRtCsIxm4kIcdG8LcciqJsIW%2BzlgohzKPK%2BCiJCcYvFchwAFRoMkiLpngVAQApvaKaEyT9veCmKasBD6QQ97pMO6a2gw969pJmDSdGaZXIWArJKKnYGr2TD9qOpLJGOElSXgMmYGmwEtts2DrnhxYNpgqjJMQCH%2BfQyooYcVZajSAD0uWHBAzaHAVAAcooFZZmCoJpVz0d5NqJclqWHF4DDzrQtBBWYz5wZBTUpb5A54ngRyZaS6VKa17WeLQvUtQoGXbOOyoALSFRlZjZocI1YPVxZGSZQUmWZ838ClEBVdZhx4EFmphjd/E7QwOW3dYmW7ZgnkwS%2BeUFVwtyHLQqBMOghxUPOLCHGwLAkIiN2CKOg4XIc8rAHgoyxPhPl%2BYcpLqQwXBBcRZjpsDoNeBRa56f2xyWDd%2B2/RBvJDf5BNmMTk6HuT6CU0u2FaQwZl0xYj3WHj6WM88ACc%2BWHGYgOYKSYheHxyWOaFfEDsACpEiFYXQ9e2PwaWVEVj%2BLBE%2BNyQQPjoRcIz3ZAV%2B5uCiwHPW7b7NSxossFdstxEx4gh4MAXirAotDw6MJDosr3iYOJEOoFDyNQ2jGOQilADuCCxOiZtAlEhA3eJXD4XLWAogwWAMMgeCJ4cwBiLHYBgPhJNXhWR4p%2BrCj92ymB8xea4mfelv3nbhOO7KOMDugVvLROLDpqkyTIII6ZeKuECWzPNKd4XPfQvK/cx/Kw8C0d4sL%2BPAR497819SzuPoB7S8LyLy%2Br0yG9ntva53Y%2Bz9ocAOHMvDJHQHxE6tNUhXCxh%2Ba%2BlhMpv3mm%2BF8csECGHQPQVGUImChCwMQA051CqszFkvRar0novQeqBKwlhvoMRulQQqNsaZQWzBYAs2ZdSLCYUGX2NJjK00yhwkwXCeH6jim8IRjJ%2BzvWQTI7s6DGLMRfIRXc8ioIyPQXo14pJUCjXBvSQWtodIcMMoIJSMDzI7TwFZGyAiPyAhACgJkakNKCzMveWx95bL/ABG45MZJwqnFctFLyTEpZMQ4MsWgnBsy8D8BwLQpBUCcDcIo0WChVjrApGYbYPBSAEE0HE5YQTJBgOlpIeIGguDAmllwbYLTSoBASRwSQySynpM4LwBQIANAlLKcsOAsAkBoGhHQWI5BKCTOXPQOIokjBmDMFwIZNBaBZwGRAKIPTi7MGIIiTgxSDmNERAAeSiNoTopTuC8EmWwQQFyGBRx6VgKIXhgBuDELQAZ9zSBYCokYcQqTeD4HlF0ck/y0mJU6P2TYxT4EdLSbQPAUQWRHI8FgHp1xzgnN4OSYgdIlC6nwSC0IoAwXLCoAYYACgABqDds4XOrgSmQggRBiHYFIDl8glBqB6bobY%2BhDDGGyfodFAzIDLCZLUHknBVqjHQChUwyDLCFMOKtKi6wHjLUHAwIlkgtUXO2FqgA6r8i1iVrhMF4KgIlNwsDSo5FUGomQXA1wmH4LggQa79FKOUPQITMjeuDQUeVAbBhxF9R0LodRphhtjdUW53RphRvmDG2wibPCtD0KMXoGag0OxWGsDYEh4mJO6WC3pHBDiqFKvEVa8RjXLL9KswOtwNCFVwIQEgdMimLF4HcrQoyJlUGALMrkjAs4/HlIIf5xT5nTOIOENEnAG1Npbf8AwRh5YKwBrC/AbJRp6GFaQQ585s7XEwNUJgiITI9LjZCdAAAxNq8aUn8FQGY5mBBFJWP/feNq6RgBhDBsDIwixOAlPlJgU9GhK0cCSRenpGSOBuFfQAcXrY25trbd3toPV2ntx7%2B07F9YcDwUzFkDu2EO4Z1LSAQCQH4ig1oaOxDXWwDdeHt1tv3Z2o9fanV6H4Jy0Q4heXif5SodQNbz3ZxZMkAlSGUMpLSehi5/ZhY1Vw1ugjYrBOHsKtRhZsQ6MMZHeU0gedQZDFdUE7M8RbjAg0NmbY0s2kaEbYkLg0t9CcC6ahmt6H%2Bl6Gs/wwLHAzDVs030xjo7lhEvSM4SQQA"></iframe>
{{</rawhtml>}}

A few observations:
1. The loop body is now branchless - I expected this to have virtually no bad
   speculation
2. I need to move the mask to a general purpose register (GPR) in order to get
   its popcount.

## First Moment of (Bitter) Truth
{{<fig key="basealine-throughput" src="/images/baseline-throughput.png"
   caption="Throughput (MB/s) achieved by the `std::copy_if` and the AVX-512 implementation."
   Align="center">}}
   
{{<fig key="baseline-walltime" src="/images/baseline-walltime.png"
   caption="Wall Time (ns) for `std::copy_if` and the AVX-512 implementation."
   Align="center">}}

We hebben een serieus probleem; the achieved throughput
~4 GB per second *for all input sizes*, which means:
1. It's *slow as shit* since the memory subsystem is capable of sustaining ~26.5 GB/s
   for a 4GB working set, and ~300GB/s for a 4KB working set, as shown in
   [by the throughput upper bound for copying data](#how-fast-is-fast).
2. It's invariant with respect to problem size, and most likely not experiencing
   memory hierarchy effects.

At this point my first guess was that one of the AVX-512 instructions has a much
longer latency or much lower throughput than I expected. We have three AVX-512
instructions.
1. SIMD load `vmovdqu64 {mem} {zmmr}`
2. SIMD comparison `vpcmpnled {zmmr} {zmmr}`
3. Compress mask store `vpcompressd {zmmr} {mem} {mask}`

Experience says that 1 and 2 should not be the problem (I will eat thumb tacks
if they are). So, I could investigate `vpcompressd` register to memory directly.

BUT, (IMO) it is much more fun and illuminating to systematically drill-down
using the generally applicable top-down approach that also gives us a brief tour
of CPU microarchitecture. If that sounds interesting to you, keep reading,
otherwise skip to the [end](#the-fix-and-final-moment-of-truth).  This exact
approach is outlined in the paper "A Top-Down Method for Performance Analysis
and Counters Architecture" [^top-down-pmc-paper] and has been written about by
other bloggers as well [^easy-perf-tmam].

[Performance
counters](https://en.wikipedia.org/wiki/Hardware_performance_counter "Hardware
performance counters - Wikipedia") (a.k.a performance monitoring counters (PMCs)) can take us a long way after it is determined
where a bottlneck lies. We will not even reach for a profiler and just use
`perf list` and `perf stat`. Making sense of the information that a PMC system can provide us demands
at least a high-level understanding of CPU microarchitecture[^cpu-uarch], and having some numbers for your specific microarchitecture on the back of your hand.
If you already understand the terms frontend, backend, uops, branch prediction, instruction decoding, op cache etc, then you can jump straight to [the drill-down](#a-performance-analysis-methodology-using-performance-counters).

## A Crash Course on CPU Microarchitecture and PMCs
This is going to be _very brief_ as far as expositions on this topic go. There
is better exposition out there, both approachable [^cpu-uarch] and dense
[^hennessy-patterson]. This section simply gets you up to speed with what you
need for grokking the top-down analysis approach using PMCs.

{{<fig key="zen4-block-diagram" src="/images/zen4-block-diagram-chips-and-cheese.webp"
   caption="Zen 4 microarchitecture block diagram (source: [Chips and Cheese](https://chipsandcheese.com/p/amds-zen-4-part-1-frontend-and-execution-engine))"
   align="center">}}
   
   
{{<figref "zen4-block-diagram">}} is a high-level block diagram for a typical
Zen 4 CPU that shows the two main parts of a CPU: the frontend (FE) and the
backend (BE). The FE is responsible for fetching instructions from memory and
decoding them into micro-operations (uops) and hand those over to the backend.
The backend is responsible for scheduling, executing, and retiring these uops
while ensuring that the program semantics do not change, i.e. only certain re-orderings
between instructions are permissible.

Decoded uops are stored in ~the balls~ a uop queue, which is fed by the decoder
and the uop cache [^zen4-loop-buffer-disabled]. The backend receives uops from
the uop queue whenever it has resources available to begin executing an
instruction.

A piece of code is said to be **fronted bound** if during a good majority of
cycles the backend is ready to receive uops, but the FE has placed any
uops in the uop queue. Typical causes of FE boundedness include high iTLB
and L1i-cache miss rates, high uop cache miss rates etc.

Similarly, a piece of code is **backend bound** if the FE has made uops
available in the uop queue, but the backend is not ready to receive and begin
scheduling. This can happen due to e.g. L1d cache and dTLB misses (read stalls),
bad instruction mix resulting in [structural and data hazards](https://en.wikipedia.org/wiki/Hazard_(computer_architecture)) (e.g. heavy use of
dividers, which are typically small in number and unpipelined) etc.

While branch prediction is part of the FE, **bad speculation** requires
its own classification for reasons that will be discussed later.

Ideally, 100% of cycles would fall under the final category - **retiring**.
This reflects pipeline slots utilized by good uops - issued uops that eventually
get retired. Hitting 100% retired corresponds to hitting the maximal uops
retired per cycle for a given microarchitecture. But, a high retiring fraction
DOES NOT necessarily mean no room for more performance. Microcode[^microcode]
sequences can hurt performance and should be isolated separately.

## The Top-Down Analysis using Performance Counters
This method, along with a performance monitoring unit (PMU) architecture
recommendation, is described in Yasin's paper [^top-down-pmc-paper]. The main
idea is to start by categorizing CPU execution time at a high level first. This
flags (reports a high fraction value) specific domains (FE bound, BE bound, bad
speculation, and retiring) that should then be investigated further while
ignoring other domains. Recurse.

{{<fig key="pmc-hierarchy" src="/images/top-down-pmc-hierarchy.png"
   caption="The top-down hardware event groups hierarchy"
   align="center">}}
   
{{<figref pmc-hierarchy>}} shows the top-down hierarchy of hardware event
groups.  We start at the top, flag one of the three domains bad domains
(frontend, backend, bad speculation), and recurse into the flagged one(s) while
ignoring the rest. An inner node should be considered if and only if all its
ancestors have been flagged. Fraction values of non-sibling nodes are not comparable.

Note that at level 1, bad speculation must be ruled out first, because
oftentimes the values of counters are updated during speculative execution, but
they are not reverted if it turned out to be a misspeculation. Let's just dive
right in and see what this looks like.

### Level 1
Yasin also proposes a performance counter architecture that is motivated is
designed in a top-down manner in order to facilitate diagnosis of realistic
bottlenecks (TODO: use the paper's language). And would you look at that, Zen 4
already has the nececessary hardware events and groups corresponding level 1 of the
hierarchy ({{<figref pmc-hierarchy>}}) groups defined for us. From `perf list`:


```
...
PipelineL1:
  backend_bound
       [Fraction of dispatch slots that remained unused because of backend stalls]
  bad_speculation
       [Fraction of dispatched ops that did not retire]
  frontend_bound
       [Fraction of dispatch slots that remained unused because the frontend did not
        supply enough instructions/ops]
  retiring
       [Fraction of dispatch slots used by ops that retired]
  smt_contention
       [Fraction of dispatch slots that remained unused because the other thread was
        selected]
...
```

`smt_contention` can be excluded because I disabled it for the core to which I pin my benchmark thread.

Let's look at the level 1 results for a 16MB input.

```
sudo perf stat -M backend_bound,bad_speculation,frontend_bound,retiring -- chrt -f 50 taskset -c 0 ./build/benchmarks/ckl_algorithm_bench --benchmark_filter='BM_CopyIf_Ckl/16777216' --benchmark_min_time=3s
2026-05-11T22:33:04+02:00
Running ./build/benchmarks/ckl_algorithm_bench
Run on (15 X 4966.64 MHz CPU s)
CPU Caches:
  L1 Data 32 KiB (x15)
  L1 Instruction 32 KiB (x15)
  L2 Unified 1024 KiB (x15)
  L3 Unified 16384 KiB (x1)
Load Average: 0.21, 0.48, 0.50
***WARNING*** CPU scaling is enabled, the benchmark real time measurements may be noisy and will incur extra overhead.
---------------------------------------------------------------------------------
Benchmark                       Time             CPU   Iterations UserCounters...
---------------------------------------------------------------------------------
BM_CopyIf_Ckl/16777216   16692437 ns     16500477 ns          254 bytes_per_second=3.78777Gi/s items_per_second=1.01677G/s

 Performance counter stats for 'chrt -f 50 taskset -c 0 ./build/benchmarks/ckl_algorithm_bench --benchmark_filter=BM_CopyIf_Ckl/16777216 --benchmark_min_time=3s':

    62,366,721,033      de_src_op_disp.all               #      0.0 %  bad_speculation          (66.67%)
    30,857,165,236      ls_not_halted_cyc                                                       (66.67%)
    62,341,441,785      ex_ret_ops                       #     33.7 %  retiring                 (66.67%)
   120,535,278,946      de_no_dispatch_per_slot.no_ops_from_frontend #     65.1 %  frontend_bound           (66.67%)
    30,882,682,226      ls_not_halted_cyc                                                       (66.67%)
     2,266,091,111      de_no_dispatch_per_slot.backend_stalls #      1.2 %  backend_bound            (66.67%)
    30,840,562,367      ls_not_halted_cyc                                                       (66.67%)

       6.306886961 seconds time elapsed

       6.213639000 seconds user
       0.021762000 seconds sys
```

Here it is plotted as a stacked column chart of ratios for 4 problem sizes.
{{<fig key="level1" src="/images/level1.png"
   caption="Level 1 breakdown for four problem sizes. There is zero bad speculation and virtually no backend bound."
   Align="center">}}

When these event groups are selected, perf automatically calculates the
fractions that we are looking for. Let's find out if the fractions make sense.
What events do the individual counters represent?

1. `ex_ret_ops` - retiring macro ops
2. `de_src_op_disp.all` - Ops dispatched from any source
	- We can see that ops dispatched from all sources is almost equal to the
      number of retiring ops. Hence the 0.0% bad speculation. Good that we can
      rule this out immediately and the other counter numbers are already
      reliable.
3. `ls_not_halted_cyc` - Core cycles not in halt
4. `de_no_dispatch_per_slot.no_ops_from_frontend` - In each cycle counts
        dispatch slots left empty because the front-end did not supply ops.
		- I.e. cycles that are frontend bound. Very convenient, innit? 
5. `de_no_dispatch_per_slot.backend_stalls` - In each cycle counts ops unable to
        dispatch because of back-end stalls.
		- Also very convenient

So this kernel for a 16M input size has
1. 0.0% bad speculation
2. 1.2% backend bound cycles
3. 65.1% frontend bound cycles
4. 33.7% retiring cycles

Note that (0.0 + 1.2 + 65.1 + 33.7)% = 100.0%. Each level in the hierarchy
partitions the pipeline into different event classes. So, our kernel is _very
frontend bound_ for some reason. {{<figref pmc-hierarchy>}} tells us we can now
safely ignore backend boundedness and start investigating whether the kernel is
_frontend bandwidth bound_ or _frontend latency bound_. We also need to look
check if any retiring uops come from the microcode sequencer.

### Level 2
Would you look at that, level 2 of the hierarchy has also been neatly organized for us
into a group. Yay!

```
$ perf list
...
PipelineL2
  backend_bound_cpu
       [Fraction of dispatch slots that remained unused because of stalls not
        related to the memory subsystem]
  backend_bound_memory
       [Fraction of dispatch slots that remained unused because of stalls due
        to the memory subsystem]
  bad_speculation_mispredicts
       [Fraction of dispatched ops that were flushed due to branch mispredicts]
  bad_speculation_pipeline_restarts
       [Fraction of dispatched ops that were flushed due to pipeline restarts
        (resyncs)]
  frontend_bound_bandwidth
       [Fraction of dispatch slots that remained unused because of a bandwidth
        bottleneck in the frontend (such as decode or op cache fetch
        bandwidth)]
  frontend_bound_latency
       [Fraction of dispatch slots that remained unused because of a latency
        bottleneck in the frontend (such as instruction cache or TLB misses)]
  retiring_fastpath
       [Fraction of dispatch slots used by fastpath ops that retired]
  retiring_microcode
       [Fraction of dispatch slots used by microcode ops that retired]
...
```

Here's the output of perf stat 

```
sudo perf stat -M backend_bound_memory,backend_bound_cpu,frontend_bound_bandwidth,frontend_bound_latency,retiring_fastpath,retiring_microcode \
	-- chrt -f 50 taskset -c 1 \
	./build/benchmarks/ckl_algorithm_bench \
	--benchmark_filter='BM_CopyIf_Ckl/16777216' \
	--benchmark_min_time=3s
...	
---------------------------------------------------------------------------------
Benchmark                       Time             CPU   Iterations UserCounters...
---------------------------------------------------------------------------------
BM_CopyIf_Ckl/16777216   16788004 ns     16616390 ns          253 bytes_per_second=3.76135Gi/s items_per_second=1.00968G/s

 Performance counter stats for 'chrt -f 50 taskset -c 1 ./build/benchmarks/ckl_algorithm_bench --benchmark_filter=BM_CopyIf_Ckl/16777216 --benchmark_min_time=3s':

     8,279,342,938      ex_no_retire.load_not_complete   #      0.8 %  backend_bound_memory
                                                         #      0.4 %  backend_bound_cpu        (33.34%)
     2,193,400,952      de_no_dispatch_per_slot.backend_stalls                                        (33.34%)
    12,580,467,726      ex_no_retire.not_complete                                               (33.34%)
    30,990,815,464      ls_not_halted_cyc                                                       (33.34%)
    54,989,538,537      ex_ret_ucode_ops                 #      3.9 %  retiring_fastpath
                                                         #     29.7 %  retiring_microcode       (33.34%)
    30,905,255,222      ls_not_halted_cyc                                                       (33.34%)
    62,204,599,288      ex_ret_ops                                                              (33.34%)
   120,942,499,051      de_no_dispatch_per_slot.no_ops_from_frontend #     25.0 %  frontend_bound_bandwidth  (33.32%)
    12,443,310,206      cpu/de_no_dispatch_per_slot.no_ops_from_frontend,cmask=0x6/ #     40.3 %  frontend_bound_latency   (33.32%)
    30,880,935,531      ls_not_halted_cyc                                                       (33.32%)

       6.325126529 seconds time elapsed

       6.231692000 seconds user
       0.029639000 seconds sys	
```

{{<fig key="level2" src="/images/level2.png"
   caption="Level 2 breakdown for four problem sizes. While the super heavy frontend bound exists, most of it is frontend latency bounded, meaning that no uops are delivered at all to the backend in a good 40% of cycles. However, the more alarming statistic is the 29.7% retiring microcode and only 3.9% retiring fastpath; a good 88% of microcode uops!"
   Align="center">}}

We hebben een serieus probleem.
- `ex_ret_ucode_ops` (retired microcode ops) - Of the 33.8% or so retiring ops,
  the vast majority are microcode ops.
- `cpu/de_no_dispatch_per_slot.no_ops_from_frontend,cmask=0x6` - For 39.8%
  cycles, 0 upos are being dispatched to the BE, hence the FE latency bound


We have already seen `de_no_dispatch_per_slot.no_ops_from_frontend`, but what is
the other event that is used to determine FE latency bound cycles?
`de_no_dispatch_per_slot.no_ops_from_frontend,cmask=0x6` is the same counter as
`de_no_dispatch_per_slot.no_ops_from_frontend` but with a counter mask (cmask) of `0x6`.
A footnote in the paper [^top-down-pmc-paper] explains this.

> For example, the FetchBubbles[≥ MIW] notation tells to count cycles in
> which number of fetch bubbles exceed Machine Issue Width (MIW). This
> capability is called Counter Mask ever available in x86 PMU [10]

From the Intel 64 and IA-32 Architectures Software Development Manual:

> Counter mask (CMASK) field (bits 24 through 31) — When this field is not zero,
> a logical processor compares this mask to the events count of the detected
> microarchitectural condition during a single cycle. If the event count is
> greater than or equal to this mask, the counter is incremented by
> one. Otherwise the counter is not incremented.

So, this increments the counter when the _per-cycle_ value of
`de_no_dispatch_per_slot.no_ops_from_frontend` is >= 6. {{<figref
zen4-block-diagram>}} shows that Zen 4 has a 6-wide uop dispatch (the boundary
between FE and BE). Therefore, the event derived using this counter mask counts
the number of cycles where the number of fetch bubbles is equal to the uop
dispatch width, thereby counting stall cycles due to high 2FE latency.

So, at this point we are at
1. 25.0 % FE bandwidth bound + 40.2% FE latency bound = 65.2% FE bound
2. 1.2% BE bound
3. Most of the retiring uops come from microcode. 

So, at this point we have narrowed down three things to investigate in the next
level of the hierarchy, in decreasing order of priority:
1. The microsequencer under the retiring category
2. FE frontend bound
3. FE latency bound

### Retiring Microcode
Based on the level 2 counters, at least one of the instructions is heavily
microcoded; it's almost certainly one of the three AVX-512 instructions.

1. SIMD load `vmovdqu64 {mem} {zmmr}`
2. SIMD comparison `vpcmpnled {zmmr} {zmmr}`
3. Compress mask store `vpcompressd {zmmr} {mem} {mask}`

As it turns out, this specific pathology is very well-charted territory [^lemire-zen4-gotcha] [^mersenne-zen4-teardown].
From the the official [Zen4 microarchitecture optimization guide](https://www.amd.com/content/dam/amd/en/documents/processor-tech-docs/software-optimization-guides/57647.zip):

> Avoid the memory destination form of COMPRESS instructions. These forms are implemented
> using microcode and achieve a lower store bandwidth than their register destination forms which
> use fastpath macro ops

😬

Measurements using [nanoBench](https://github.com/andreas-abel/nanoBench) show that this
instruction can result in a staggering 144 uops ([link to table](https://uops.info/table.html?search=vpcompressd%20(M512&cb_lat=on&cb_tp=on&cb_uops=on&cb_ports=on&cb_ZEN4=on&cb_measurements=on&cb_avx512=on))).

uops.info - Table

| Instruction                              | Lat       | TP           | Uops | Ports                        |
|------------------------------------------|-----------|--------------|------|------------------------------|
| VPCOMPRESSD (M512, K, ZMM)	AVX512EVEX | [≤40;≤52] | 9.00 / 72.50 | 144  | 1*FP01+1*FP12+2*FP23+18*FP45 |
| VPCOMPRESSD (M512, ZMM)	AVX512EVEX     | [≤40;≤52] | 9.00 / 72.50 | 144  | 1*FP01+1*FP12+2*FP23+18*FP45 |
	
There are a few ways to verify this ourselves.
1. Using the [nanobench command](https://uops.info/html-tp/ZEN4/VPCOMPRESSD_M512_K_ZMM-Measurements.html) provided with the uops.info table
   - `sudo ./kernel-nanoBench.sh -f -unroll 500 -warm_up_count 10 -asm "VPCOMPRESSD zmmword ptr [R14]  {K1}, ZMM0" -asm_init "MOV R15, 10000; L: VADDPS ZMM0, ZMM1, ZMM1; VADDPS ZMM0, ZMM1, ZMM1; DEC R15; JNZ L; VZEROALL; VXORPS ZMM0, ZMM0, ZMM0"`
2. Similar to nanoBench - using [llvm-exegesis](https://llvm.org/docs/CommandGuide/llvm-exegesis.html).
3. Profiling the benchmark itself using `perf record`.

### Profiling with AMD IBS
Using a sampling profiler along with performance counters on a microbenchmark,
particularly when we care about per-instruction attribution, can result in
inaccuracies like [_skid_](https://easyperf.net/blog/2018/08/29/Understanding-performance-events-skid), i.e.  a sample gets attributed to a nearby instruction
instead of the hot instruction actually causing trouble.

AMD introduced hardware for instruction based sampling (IBS)[^amd-ibs] in their
CPUs.  IBS hardware periodically selects an operation based on a precondigured
sampling period.  The tagged operation is then monitored as it proceeds through
the pipeline, and events triggered by the tagged operation are recorded. On
completion of the operation, its event information is reported to the profiler.
This results in zero skid by construction, and it does not impose any overhead
to instruction execution. Because of its sampling nature, it is mostly useful in
hot loops.

As an example, if we directly try to profile `ex_ret_ucode_ops`, i.e. number of
retired microcode uops using: we get the following from `perf annotate`

```sh
sudo perf record -F 3977 --call-graph fp -e ex_ret_ucode_ops \
	-- chrt -f 50 taskset -c 1 \
	./build/benchmarks/ckl_algorithm_bench \
    --benchmark_filter=BM_CopyIf_Ckl/16777216 --benchmark_min_time=3s
```

```
Percent │2b8:   mov         %rbx,%rsi
        │       mov         %r12,%rax
        │       xchg        %ax,%ax
        │2c0:┌─→vmovdqu64   (%rsi),%zmm1
   0.03 │    │  vmovdqu64   0x40(%rsi),%zmm0
   0.15 │    │  sub         $0xffffffffffffff80,%rsi
        │    │  vpcmpnled   %zmm2,%zmm1,%k1
   0.13 │    │  vpcmpnled   %zmm2,%zmm0,%k2
   2.07 │    │  vpcompressd %zmm1,(%rax){%k1}
  48.09 │    │  kmovw       %k1,%ecx
   0.00 │    │  popcnt      %cx,%dx
   0.01 │    │  kmovw       %k2,%ecx
        │    │  mov         %rdx,%rdi
        │    │  and         $0x1f,%edi
        │    │  vpcompressd %zmm0,(%rax,%rdi,4){%k2}
  49.52 │    │  popcnt      %cx,%di
        │    │  add         %rdi,%rdx
        │    │  and         $0x3f,%edx
        │    │  lea         (%rax,%rdx,4),%rax
        │    ├──cmp         %rsi,%r11
        │    └──jne         2c0
```

i.e. its attributing around 97% of retired microcode uops to a mask register to
general purpose register move (`kmovw`) and `popcnt`, which is egregious.

Instead, we sample IBS op events.

```
sudo perf record -F 3977 --call-graph fp -e ibs_op/cnt_ctl=1/pp \
	-- chrt -f 50 taskset -c 1 \
	./build/benchmarks/ckl_algorithm_bench \
    --benchmark_filter=BM_CopyIf_Ckl/16777216 --benchmark_min_time=3s
```

```
Percent │2b8:   mov         %rbx,%rsi
        │       mov         %r12,%rax
        │       xchg        %ax,%ax
   0.33 │2c0:┌─→vmovdqu64   (%rsi),%zmm1
   0.27 │    │  vmovdqu64   0x40(%rsi),%zmm0
   0.31 │    │  sub         $0xffffffffffffff80,%rsi
   0.27 │    │  vpcmpnled   %zmm2,%zmm1,%k1
   0.30 │    │  vpcmpnled   %zmm2,%zmm0,%k2
  47.03 │    │  vpcompressd %zmm1,(%rax){%k1}
   0.24 │    │  kmovw       %k1,%ecx
   0.32 │    │  popcnt      %cx,%dx
   0.32 │    │  kmovw       %k2,%ecx
   0.34 │    │  mov         %rdx,%rdi
   0.37 │    │  and         $0x1f,%edi
  48.17 │    │  vpcompressd %zmm0,(%rax,%rdi,4){%k2}
   0.33 │    │  popcnt      %cx,%di
   0.32 │    │  add         %rdi,%rdx
   0.34 │    │  and         $0x3f,%edx
   0.36 │    │  lea         (%rax,%rdx,4),%rax
   0.36 │    ├──cmp         %rsi,%r11
        │    └──jne         2c0
```

There we have it, 95.20% retired uops correspond to `vpcompressd`.

## The Fix and Final Moment of Truth
So, there are a few ways to fix this.

In his article[^lemire-zen4-gotcha], Daniel Lemire suggests rewriting the single
masked store to use the register form of masked compress, followed by a regular
SIMD store.

```
 __m512i compressed = _mm512_maskz_compress_epi8(mask, input);
 _mm512_storeu_si512(output, compressed);
```

This of course stores additional null bytes since the store is no longer compressed.
E.g.

```
             +-------------------------------+
input      : | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
             |---+---+---+---+---+---+---+---|
mask       : | 0 | 1 | 0 | 1 | 0 | 0 | 0 | 1 |
             |---+---+---+---+---+---+---+---|
compressed : | 2 | 4 | 8 | 0 | 0 | 0 | 0 | 0 |
             +-------------------------------+
                           ^___^___^___^___^_____ these zeroes also get stored
```

For copy_if, these will be overwritten by loop iterations writes anyway, but
care will have to be taken to allocate extra bytes to destination.

Another suggestion by Mysticial on mersenneforum [^mersenne-zen4-teardown] is the following:

```
vpcompressd zmm0{k1}{z}, zmm0
kmovd       eax, k1
pext        eax, -1, eax     (the -1 in a register of course)
kmovd       k1, eax
vmovdqu32   [mem]{k1}, zmm0
```

or

```
vpcompressd zmm0{k1}{z}, zmm0
vpcompressd zmm1{k1}{z}, [-1]      (constant of all 1s)
vpcmpd      k1, zmm1, [-1], 0      (constant of all 1s), compare for equality
vmovdqu32   [mem]{k1}, zmm0
```

These use a masked store, so additional space should not be required, and the masked store decodes
down to 2 uops on Zen4 ([uops.info table link](https://uops.info/table.html?search=vmovdqu32%20(M512&cb_lat=on&cb_tp=on&cb_uops=on&cb_ports=on&cb_ZEN4=on&cb_measurements=on&cb_doc=on&cb_base=on&cb_avx512=on))).

Let's try the maskless store variant.

```c++
template <template <typename> class Predicate>
int *copy_if(int const *input, int *output, ssize_t n, const Predicate<int> &p) {
  const auto vp = Predicate<__m512i>();
  constexpr auto vlen = 16;  // (512 / 8) / sizeof(int);
  constexpr auto unroll = 2;
  constexpr auto stride = vlen * unroll;
  auto sn = n - (n % stride);
  int *out = output;
  for (ssize_t i = 0; i < sn; i += stride) {
    const auto v_in1 = _mm512_loadu_epi32(input + i);
    const auto v_in2 = _mm512_loadu_epi32(input + i + vlen);
    const __mmask16 m1 = vp(v_in1);
    const __mmask16 m2 = vp(v_in2);
    const auto v_out1 = _mm512_maskz_compress_epi32(m1, v_in1);
    const auto v_out2 = _mm512_maskz_compress_epi32(m2, v_in2);
    _mm512_storeu_epi32(out, v_out1);
    out += _mm_popcnt_u32(m1);
    // writes some garbage bytes unfortunately
    _mm512_storeu_epi32(out, v_out2);
    out += _mm_popcnt_u32(m2);
  }

  for (auto i = std::max(sn, 0l); i < n; i++) {
    if (p(input[i])) {
      *out = input[i];
      out++;
    }
  }
  return out;
}
```

Where do we stand now?

{{<fig key="optimized-throughput" src="/images/optimized-throughput.png"
   caption="Throughput of std::copy_if and fixed AVX512 implementation"
   align="center">}}

{{<fig key="optimized-speedup" src="/images/optimized-speedup.png"
   caption="Throughput of std::copy_if and fixed AVX512 implementation"
   align="center">}}
   
Much better, {{<figref optimized-speedup>}} shows that we finally have
 substantial speedups ranging from ~10x to ~40x.  over `std::copy_if`

## What's Left
Of course this implementation is still _very_ crude - lots of parameters are
hardcoded:
1. Loop unrooll count
2. SIMD width
3. Element type
4. Implementation of compressed store
5. The overall implementation of `copy_if` in general

There are multiple ways of implementing a SIMD version of `copy_if`,
specifically the implementation of `compress_store` at two of them. The former
is incredibly shit on Zen 4, but it should hold up just fine on comparable Intel
microarchitectures and on Zen 5. Other implementations, that were mentioned a
CppCon talk [^cppcon-advanced-simd-algos] by one of the co-authors of EVE,
include:

1. [Tiny lookup
   tables](https://stackoverflow.com/questions/45506309/efficient-sse-shuffle-mask-generation-for-left-packing-byte-elements/45515947#45515947)
   by aqrit on stackoverflow.
2. [Using BMI2 intrinsics](https://stackoverflow.com/questions/36932240/avx2-what-is-the-most-efficient-way-to-pack-left-based-on-a-mask) (by Peter Cordes, prolific stackoverflow user)
3. Switch + shuffle by @Z Boson on stackoverflow [^zboson-pending]

Some of these will be faster than others depending on the platform, predicate,
and the input distribution. Some, including the straightforward AVX512
implementations, will be straight up impossible on some platforms because the
requisite instructions might not be available.

There are also several possible ways of providing higher-level hardware agnostic
abstractions on top of SIMD intrinsics in order to present a generic interface
that exposes such configuration options. C++26 includes such a foundational SIMD library
in the form of [data-parallel types](https://en.cppreference.com/cpp/numeric/simd).
 C++ compiler release has implemented this.

There are also SIMD library like [highway](https://github.com/google/highway), [xsimd](https://github.com/xtensor-stack/xsimd), [vectorclass](https://github.com/vectorclass/version2), [EVE](https://github.com/jfalcou/eve) etc, which handle a
lot of these implementations and configurations for you. Here's a zoo of
`eve::algo::copy_if` configurations on [compiler
explorer](https://godbolt.org/#z:OYLghAFBqd5QCxAYwPYBMCmBRdBLAF1QCcAaPECAMzwBtMA7AQwFtMQByARg9KtQYEAysib0QXACx8BBAKoBnTAAUAHpwAMvAFYTStJg1DIApACYAQuYukl9ZATwDKjdAGFUtAK4sGIM6SuADJ4DJgAcj4ARpjEIACcAOykAA6oCoRODB7evv6p6ZkCIWGRLDFxSbaY9o4CQgRMxAQ5Pn4BdpgOWQ1NBCUR0bEJyQqNza15HeP9oYPlw0kAlLaoXsTI7BwA9NsA1CYAzAAiR6cnZ5cX1%2Be3V3c390%2BPLw9vz%2B%2BvH99fv5//PwBf2%2BGgAgrs9somGNMHtQkQ9ggCAQUgoQLtgBgop4CAA6EjAfZ7ADuhCQJjBEL2ew8LBSdFiexAe1UAA4AGwAWnZkj2yAMRj2XFZ1mpEBIe2AyGQQsO1iWFPBRL2ADEDMAFNTqczOWN0GdTJZrGYNHtOQB5Q5mlhMABuqjMZuO4WO2AscgA4oqqXsQlFiE0AJ7avZMdDoA5mMyYW2YcyO214Jh7AgIWF%2BgPEPCYTVRLzIgR7CAGAg5ggKynbb37ABqTSTgk1qCoexj7BAYkxIBQqBSgYA%2BngWwoEKhiQw9jFaGPcdXq3twqhS3tC/GFEwqLDbZqvAx15v48y293O6hu2g%2B4OW2JiUxAzulJrU7CAFS7/eYF/z/jEFgrlvHj2dLEDmCj9hewa7lgxApmmiKoBgRZKLCEFXriCApCkIDztSJjshoIEEOsE6AWgwGgeBvaBiYACsFiAe%2BG5xjRpx0Vge6ENRLFHFY%2BF7Esk5dEwXhKLBcaVqGtCYlmqZ/oQdgtgQAbIAA1k%2BcFrCi%2BacgGRiwtiUGaomyZ4RoKmYJgKT9jQxBjKZs4SUIqBiXsH7bIxm6hqoeCaj5K4MLQwaYKoaRKBGhbPns07Epy9CxrQ86kag5EKGBEF8mIBhRPQpB7AwS7%2BS5p4yQgLC4nsADqCBMAQewvj5L4pruTDZeJSqFahQ7YZWOFCuVWBUMJtC1Vqo1jeNE2ckc2B7OxSj9ppKT5pGFihvmzm7sQni0Cta0ImIeDAAwvVmOVgGnt2c2YAt%2BZLSNE1mtNrYhbQeDIIQs2MKJEDrmwoaagNQ3lr1hxnbGJ5SWeIAKCkTTzYty0PVNhwzURYQRj%2BeyxsQwabsSiLyXs%2BwgcAPmlsQvWSGD7YXSA%2BX9pt22hMAD3UsjM2M7QCWHG4XDTb1NHUxDXZ06g/YHUdzOs2zT0KCpeApEVr1HZyKQWTtKRbdOwBeG1PrskLHaQ92wVqxxsbgZlLX0KN7N5WLEsMFLor05zr2CqKGRGPQ/aw6lvWJIbtP4ImGStf2UQDqIxD4MwO12zUeBYC5Npy5g6Cco0dCuaWKS9dLBeF%2BNEBhOnmr047UsIlEhCYBW7XUqyQfGyAP6bJbMehGIRxuCKKNjXb9KqaGrlq%2B9NAykIACSACyxwkknqa9fE5Uw3D10I7VLsO8rTse5Y9sMwwWvuyzYxMKp6dY0mKYBvJJiJFYiSnD1EkACpwZr6dvTVsKhK2F8EBY3rIYWqflIrTznrFIcpYIyYAAI5eDwLaMQjBarNnzgcOitFjgQGEgiNAe4CDmHZHlASD9VqEWInlA4/cNA8QOM/ecgIWHAjYUCDhrDOHsK4bwnh/DuGcLBIqcwhxQj8i8MnHubZtgsAwF4eg2xTzoUwvzYRZgxEMAkVInma9jooxEWCESUsp4TlofPeEfIBBjC/IcKwRivYs3NMtM4cJBC2PsaCRUhCYQhRgvg5yoVMixnMVgqwLE8HrSsUQkhZDGGUMwERYgE4JxPXoXYxh5xPGKmCuTVJUY3Dxj2s5TqVB%2BwaC4P2QGCiCAQFMXsKguV6m0Fys49BjS9htJXLQeuFDFSjSock1s4MjYi1KRAfpE09Tdj0RQjpCVn65WmdDWGx1H7Nlyp4B%2BxxcpBMcLGBUdiRFMOEWCXJsR8lmEKVGYpVjLxDnKWYKpX1MB1InB05prTlobM6d8npxzPEDMSdQ86LdSm0XoiM4OLybpaWIREyZ41lmzMfvM7ZSyCDoBmasihPytmLL2Hs5BdceLHJfl4s5qg8mRiuUUgJdyBwPI0Icfsa9bKvPqR8icLTfntK%2Beg/5wjH6Ir2IMkiUKwVUSvBC0FIs2Xw1uvmHBEywQPWRTi1FuUFk7JzlilZhhcUdPxTqolBzSVCvJTkqlFyaXXMdPS0p5TJD9ldsfbabyGlNO5fy/8PrPC9OFaqrUYrhk00lfcqgMqJUi1dSfZmyqRWjXVQazVUV0W6uxSmiweLtW7MKPsklRyLWGNBOcoZ8Y7W3MdRoGiLqd6HQYB6rlUU/UdK6f6gFIqQ2yqhuCuiPbuwV13vGhFQakWYszWsiwaKCXJqnTm9NprC3ZJORS0t1ry0FLpVE6t7J%2Bymy%2BsSptXqW28t9WejtQrAXBuBUMgdPYI1RrDSLA95trqiC5tbZiuDE1ajnXMrV6b/3rKNbmwl%2BbiWHJXZayl1KK3boIVKpliQqnIJ8ngVqx69ifIvW2v5Abr3Um7dG3tSHI1jrGk%2B4WUMQ7ofDpHDusdu7cQo6NKjoyoZDobSOn9rGpkTv1VOmdOrgPZtA4uiDZqi1eNXVauDW6bkOrI%2BU1kjHWRYZw%2B2vDAqCNdtveK59pHH39pI92Nu76mhMe5r3fmo7QRqoEyi6dgHZ2OY1WJzZYGl1QbJSWstlzK1KYjeU%2BIrLYbsrrY7OtbsNPetw36wVMnCOiv06G6j54yPsdpkpJg99A32Ymve%2BVG9FUEFIL%2B6k96uOSyMOVvjlXTOiyPnGow2yE31bGqJ4TGK9VOYXQS7z5qZPHA4CsWgnAaK8D8BwLQpAzwcGuVYA%2BCg1gbFhKIngpACCaFGysFSIBJCgzMPESQ%2BEuCJHiFwQ413WQBHGxwSQU2dtzc4LwNEGgts7ZWHAWASAyL0noGQCgEB/sMjiPyQwwAoxcA%2BzQYasQ0QQCiM9muzAcacE26joM5oojaC6Nt7gvAyJsEEOaAKgZntYDzMANwmU0SE9IFgG03stizfwCBbosZ6ezeCl0fMWxNvwhqM916/ogweCwM9pSeAWAY94NjbEShjiYGZ8AU%2BX2%2BDqgUDWbMxJzRmzlzIQQIhUESGkPwQQigVDqBmzoEAhx9CQ5QNYaw%2BgMNolgMwNgIA2ykGxiAJSu4VJLBWL2Ooe5OC6kxQaF3lgNHWiaMgBAZwABeDBsa8gtFaTkFVMpmgqrkgMvBUDYyzFgD3EAVidG6M4CArhJh%2BC4IEBg6ABhlAqHoIlAgG%2Bd4g8UOY7fhhN%2Br%2BH3oExPBtD0CPnoMw29DDiMPmYPfF99DnwsBfVfVubAkGNibT3bcvY4CyDk3JeQQ8FFGXEXBcSmggLgQgEoNtLF4ATrQ32/tUGAOQSgmxBCxHC2gvTptqDoDuEKwFsGyFyDyHyAKCzJftfjzvgEQGXnoLoA7mjltMSEpOrHeJpM9iPunCqLuDXtNtWpUtUsNJwFtiBJgEnCABoLvhwJNqQNNrNvNm4CqB6MflAWfrAXsPATfkWPfsgZGIcE3jSMlADoyKIocM/p9rbu/iAJvN/iDpIWDmAd7hwJAafjAZDvwadAgbwN/MgXQU3hbsIB%2BuwFIEbvIEoGoM9mgaQMSAGFhITowcwawcXpwG0ndP%2BNwToefnAQYYIRALSFITBDIXIa/rtqQGmGGMMJXqQPtjRAbIkDWocPELdhoByOyOyFwPEPoJwI9iwc9vNm9noNESHoURwGYPvmwa9vIW/isNjBkM4JIEAA%3D%3D%3D).
I am planning to take all these libraries for a spin and analyze their performance and codegen in a series of subsequent blog posts.

## Conclusion
When I started this, I expected it to be much simpler. Lots of takeaways
from this whole exercise.
1. We (finally) managed to get a speedup of up to 40x with the AVX512
   intrinsics. There is most likely still room for more tuning.
2. `vpcompressd (M512, K16, ZMM)` is very poorly microcoded. In general, check
   with sources like the
   [uops.info table](https://uops.info/table.html?search=vpcompressd%20(M512&cb_lat=on&cb_tp=on&cb_uops=on&cb_ports=on&cb_ZEN4=on&cb_measurements=on&cb_avx512=on))
   before committing to a specific intrinsic when writing manual SIMD programs.
3. If you have determined that your code is CPU-bound, Yasin's top-down analysis
   using `perf stat` is a great starting point for systematically drilling down
   into root cause of the bottleneck.
4. 
5. Use IBS on AMD CPUs for high confidence sampling of CPU microbenchmarks to
   not be thrown off by skid (no pun intended).
6. Consider using cross-platform SIMD libraries like EVE, highway,
   xsimd etc for portable performance.
   
Most likely I will cover EVE in the next SIMD related article.

## Appendix

### Benchmark Setup
We would like to reduce variance as much as we can. The canonical reference
document for this is the [article on reducing
variance](https://google.github.io/benchmark/reducing_variance.html) in the
Google Benchmark docs.

#### Sources of variance
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

#### Disabling SMT
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

#### Setting Thread Affinity
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

#### Increasing scheduling priority of the benchmark thread
`chrt -f 50 <cmd>` sets the scheduling policy to first-in-first-out (FIFO) with
scheduling priority 50. The valid range of priorities is 1-99, and so the
process initiated by `<cmd>` can be preempted by any other process with a
priority >50.  By default `perf stat` includes in its output the number of
context switches incurred a process's execution.

#### Putting it all together
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

### llvm-mca
For some reason llvm-mca 22.1.5 predicts an IPC of 3.46, while the achieved
IPC was 0.11. Might be worth looking into the scheduling model.

```
$ llvm-mca
.loop:
vmovdqu64 (%rsi),%zmm1
vmovdqu64 0x40(%rsi),%zmm0
sub    $0xffffffffffffff80,%rsi
vpcmpnled %zmm2,%zmm1,%k1
vpcmpnled %zmm2,%zmm0,%k2
vpcompressd %zmm1,(%rax){%k1}
kmovw  %k1,%ecx
popcnt %cx,%dx
kmovw  %k2,%ecx
mov    %rdx,%rdi
and    $0x1f,%edi
vpcompressd %zmm0,(%rax,%rdi,4){%k2}
popcnt %cx,%di
add    %rdi,%rdx
and    $0x3f,%edx
lea    (%rax,%rdx,4),%rax
cmp    %rsi,%r11
jne    .loop
Iterations:        100
Instructions:      1800
Total Cycles:      520
Total uOps:        2100

Dispatch Width:    6
uOps Per Cycle:    4.04
IPC:               3.46
Block RThroughput: 3.5


Instruction Info:
[1]: #uOps
[2]: Latency
[3]: RThroughput
[4]: MayLoad
[5]: MayStore
[6]: HasSideEffects (U)

[1]    [2]    [3]    [4]    [5]    [6]    Instructions:
 1      8     0.50    *                   vmovdqu64     (%rsi), %zmm1
 1      8     0.50    *                   vmovdqu64     64(%rsi), %zmm0
 1      1     0.25                        subq  $-128, %rsi
 1      1     0.50                        vpcmpnled     %zmm2, %zmm1, %k1
 1      1     0.50                        vpcmpnled     %zmm2, %zmm0, %k2
 2      8     0.50           *            vpcompressd   %zmm1, (%rax) {%k1}
 1      1     0.50                        kmovw %k1, %ecx
 1      1     1.00                        popcntw       %cx, %dx
 1      1     0.50                        kmovw %k2, %ecx
 1      0     0.17                        movq  %rdx, %rdi
 1      1     0.25                        andl  $31, %edi
 2      8     0.50           *            vpcompressd   %zmm0, (%rax,%rdi,4) {%k2}
 1      1     1.00                        popcntw       %cx, %di
 1      1     0.25                        addq  %rdi, %rdx
 1      1     0.25                        andl  $63, %edx
 2      2     0.25                        leaq  (%rax,%rdx,4), %rax
 1      1     0.25                        cmpq  %rsi, %r11
 1      1     0.50                        jne   .loop
```



[^1]: Those of you already experienced with AVX-512 on Zen 4 already know where this is going.
[^cpu-uarch]: See ["Modern Microprocessors - A 90 Minute Guide!"](https://www.lighterra.com/papers/modernmicroprocessors/) for a more elaborate exposition.
[^hennessy-patterson]: Consider Appendix C and Chapter 3 of [Computer Architecture: A Quantitative Approach 7e](https://shop.elsevier.com/books/computer-architecture/hennessy/978-0-443-15406-5 "Elsevier link (not sponsored)") for a very serious exposition on CPU backends and branch prediction.
[^top-down-pmc-paper]: Yasin, A., 2014, March. [A top-down method for performance analysis and counters architecture](https://www.researchgate.net/profile/Ahmad-Yasin/publication/269302126_A_Top-Down_method_for_performance_analysis_and_counters_architecture/links/58031fc108ae6c2449f7feda/A-Top-Down-method-for-performance-analysis-and-counters-architecture.pdf). In 2014 IEEE International Symposium on Performance Analysis of Systems and Software (ISPASS) (pp. 35-44). IEEE.
[^easy-perf-tmam]: Denis Bakhvalov: [Top-Down performance analysis methodology](https://easyperf.net/blog/2019/02/09/Top-Down-performance-analysis-methodology).
[^zen4-loop-buffer-disabled]: Usually there is also a loop buffer, but it's disabled on Zen 4 as it is mostly a power usage optimization. See [AMD Disables Zen 4's Loop Buffer](https://chipsandcheese.com/p/amd-disables-zen-4s-loop-buffer "Chips and Cheese article") by Chips and Cheese.
[^microcode]: Not to be confused with micro-operations (uops), which are the production of custom hardwired decode logic, microcode is a series of simple instructions that replace custom hardware logic executed by a microcode engine. See the [Wikipedia article](https://en.wikipedia.org/wiki/Microcode).
[^instruction-length-decoding]: On variable length instruction ISAs like x86, this determines instruction boundaries and has been reported as a bottleneck sometimes. See [^top-down-pmc-paper].
[^lemire-zen4-gotcha]: [Daniel Lemire's blog: AVX-512 gotcha: avoid compressing words to memory with AMD Zen 4 processors](https://lemire.me/blog/2025/02/14/avx-512-gotcha-avoid-compressing-words-to-memory-with-amd-zen-4-processors/)
[^mersenne-zen4-teardown]: [mersenneforum - Zen4's AVX512 Teardown](https://web.archive.org/web/20241204180018/https://www.mersenneforum.org/node/21615#post614191)
[^amd-ibs]: [Instruction-Based Sampling: A New Performance
Analysis Technique for AMD Family 10h Processors](www.amd.com/content/dam/amd/en/documents/archived-tech-docs/white-papers/AMD_IBS_paper_EN.pdfgg)
[^cppcon-advanced-simd-algos]: [Advanced SIMD Algorithms in Pictures - Denis Yaroshevskiy](https://youtu.be/YolkGP-rb3U?si=0FUJ6C7-ev6Z94Vi&t=800)
[^zboson-pending]: Still looking for this one, please let me know if you know which StackOverflow answer this refers to.
