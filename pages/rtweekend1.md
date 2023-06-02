+++
title = "Optimizing a Ray Tracer in One Weekend: Part 1"
hascode = true
date = Date(2023, 4, 28)
rss = "RSS feed not set up yet. Apologies!"

tags = ["C++", "Optimization"]
+++

# Introduction

# What this is not
This post is absolutely NOT intended to be a critique of Dr. Peter Shirley's work. The "Ray Tracing in One Weekend" series is a very approachable and excellent resource for learning concepts in ray tracing, and we are merely demonstrating some basic, general performance optimization principles not specific to computer graphics or ray-tracing. To quote from the original project's `README`:

> It is not meant to represent ideal (or optimized) C++ code.

Assume that the same holds for the modifications that we set out to do.
Consequently, this series is also NOT an opinion on how to make "production-ready"
ray tracers. As mentioned, we simply hunt down performance bottlenecks (or hotspots) and
get rid of them incrementally. There is no way of getting anywhere close to
the hardware's peak performance using the hotspot-optimization approach in
most baseline implementations. A performant ray tracer would have a
completely different architecture and would thus require a complete rewrite [^1]


[^1]: Daniel Lemire covers this general principle in more detail in [his blog][lemire-hotspot]. Therein he referes to Casey Muratori's [article on performance excuses][muratori-excuses]. Read that as well if you have not yet.


[lemire-hotspot]: https://lemire.me/blog/2023/04/27/hotspot-performance-engineering-fails/
[muratori-excuses]: https://www.computerenhance.com/p/performance-excuses-debunked
