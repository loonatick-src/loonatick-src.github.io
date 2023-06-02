+++
title = "[WIP] Optimizing a Ray Tracer in One Weekend: Part 1"
hascode = true
date = Date(2023, 4, 28)
rss = "RSS feed not set up yet. Apologies!"

tags = ["C++", "optimization", "profiling", "perf"]
+++

# Introduction
This series of posts describes the work that we did for a course
project in performance engineering, and can serve as an entry-level
introduction to performance optimization of programs. We start with
some code that has already been written for us, in this case Dr Peter
Shirley's [Ray Tracing in One Weekend](raytracing.github.io) series.
Some familiarity with this work is assumed. But, as such you do not
need to know specific concepts of ray tracing to follow along.

We are going to start with some small, simple optimizations and move
on to more sophisticated techniques, run into increasingly bizarre
problems, and get somewhat intimate with our hardware.

# What this is not
This post is absolutely NOT intended to be a critique of Dr. Peter
Shirley's work. The "Ray Tracing in One Weekend" series is a very
approachable and excellent resource for learning concepts in ray
tracing and physically based rendering (PBR), and we are merely
demonstrating some basic, general performance optimization principles
not specific to computer graphics or ray-tracing. To quote from the
original project's `README`:

> It is not meant to represent ideal (or optimized) C++ code.

Assume that something similar holds for the modifications that we set
out to do, the code will be "optimized" to some extent, but not
ideal. Consequently, this series is also NOT an opinion on how to make
"production-ready" ray tracers. As mentioned, we simply hunt down
performance bottlenecks (or hotspots) and get rid of them
incrementally. There is no way of getting anywhere close to the
hardware's peak performance using the hotspot-optimization approach in
_most_ baseline implementations of complex applications. A performant
ray tracer would have a completely different architecture and would
thus require a complete rewrite [^1].

# Where to begin? A bird's eye view
The scene that we optimize for is `src/TheRestOfYourLife/main.cc`.
That's a lot of source files. Before diving into benchmarking,
profiling and all that, let us just take a look at the main program.

```Cpp
/* ...
 * includes and functions definitions omitted
 * ...
 */

int main() {
    // Image
	/*** code for configuring image properties ***/

    // World

	/*** Code for setting up Cornell box ***/

    // Camera

	/*nn** Code for configuring camera ***/
	
    // Render

    std::cout << "P3\n" << image_width << ' ' << image_height << "\n255\n";

	// iterate over every pixel in row-major/width-major order
    for (int j = image_height-1; j >= 0; --j) {
        std::cerr << "\rScanlines remaining: " << j << ' ' << std::flush;
        for (int i = 0; i < image_width; ++i) {
            color pixel_color(0,0,0);
            for (int s = 0; s < samples_per_pixel; ++s) {
                auto u = (i + random_double()) / (image_width-1);
                auto v = (j + random_double()) / (image_height-1);
                ray r = cam.get_ray(u, v);
                pixel_color += ray_color(r, background, world, lights, max_depth);
            }
            write_color(std::cout, pixel_color, samples_per_pixel);
        }
    }
    std::cerr << "\nDone.\n";
}
```

Everything before the loop over the pixels is setting up the scene,
camera etc. We will not be benchmarking those things. The actual work
is done inside the loop. The final image resolution is fixed during
the image setup, and rendering involves iterating over each pixel
coordinate and calculating its colour using the subroutine/function
`ray_color`.

<!-- TODO: why is this not working? -->
<!-- In pseudocode (Julia-flavoured[^2]): -->

<!-- ```julia: -->
<!-- # given a width × height image (i.e. a color matrix -->
<!-- # with `width` columns and `height` rows -->
<!-- for j in height:-1:1 -->
<!-- 	for i in 1:width -->
<!-- 		color = Color(0,0,0)  # black is the color -->
<!-- 		for s in 1:samples_per_pixel  # beauty is the game -->
<!-- 			color += ray_color() -->
<!-- 		end -->
<!-- 		write_color(color) -->
<!-- 	end -->
<!-- end -->
<!-- ``` -->

Do you see low-hanging fruit? I see low-hanging fruit. All pixels
colours are computed independently; we have an embarrassingly parallel
problem in our hands. We paid for all cores in the processor, we will
use all the cores in our processor; parallelize the loop. The easiest
way (read: minimal short-term effort) is using [OpenMP][openmp] [^4].

Parallelizing the loop is as simple as adding a one-line directive
before the loop.

```Cpp
#pragma omp parallel for  // <------------- new compiler directive
    for (int j = image_height-1; j >= 0; --j) {
		/*** rest of the rendering ***/
	}
```

There is just one more hurdle: `write_color` writes to `stdout`. Introducing
multi-threading in the mix will interleave the outputs from all threads and
produce a completely corrupted image. So, we stage the writes to a buffer
in the loop, and write the contents to a file afterwards [^2]. So, we end
up with the following.

```Cpp
/*** create an image buffer ***/
std::vector<color> image_buffer(image_width * image_height);
	  
#pragma omp parallel for
for (int j = image_height-1; j >= 0; --j) {
    for (int i = 0; i < image_width; ++i) {
        color pixel_color(0,0,0);
        for (int s = 0; s < samples_per_pixel; ++s) {
            auto u = (i + random_double()) / (image_width-1);
            auto v = (j + random_double()) / (image_height-1);
            ray r = cam.get_ray(u, v);
            pixel_color += ray_color(r, background, world, lights, max_depth);
        }
        /*** Stage writes to image buffer ***/
        image_buffer[(image_height-1-j) * image_height + i] = pixel_color;
    }
}
// Write image to file
for (auto c: image_buffer) {
    write_color(std::cout, c, samples_per_pixel);
}
```

Of course, we also need a way to set the number of threads. One way
would be compilng with different values of the environment variable
`OMP_NUM_THREADS`. We want to run the program for different problem
sizes and different thread counts to analyze its scaling properties.
So, we accept the command line flags `-t` for thread count and `-w`
for image width. The height is determined by the aspect ratio in the
image setup.

```Cpp
int main(int argc, char *argv[]) {
    // default parameters
    int image_width = 600, thread_count = 1;

    /*** Parse command line arguments ***/
    int opt = -1;
    while ((opt = getopt(argc, argv, "w:t:")) != -1) {
        switch (opt) {
            case 'w':
                if (optarg == nullptr) break;
                image_width = std::atoi(optarg);
                if (image_width <= 0) {
                    std::cerr << "Error: image width must be a positive integer, found " << optarg;
                    return 1;
                }
                break;
            case 't':
                if (optarg == nullptr) break;
	            thread_count = std::atoi(optarg);
	            if (thread_count <= 0) {
		            std::cerr << "Error: thread count must be a positive integer, found " << optarg;
                    return 1;
                }
                break;
            default:
                std::cerr << "Error: Invalid flag" << std::endl;
	            return 1;
        }
    }

    omp_set_num_threads(thread_count);
    // Image
    /*** rest of `main` ***/
}
```

Before we get down to using precise timers in `std::chrono`, let's just get
a rough look at that sweet speedup using the `time` program on Linux.

```
$ # single threaded run
$ time build/TheRestOfYourLife > image.pgm
./build/theRestOfYourLife  76.22s user 0.51s system 99% cpu 1:16.74 total

$ # using 6 threads
$ time build/TheRestOfYourLife -t 6 > image.pgm
./build/theRestOfYourLife -t 6 > image.pgm  353.12s user 274.76s system 546% cpu 1:54.84 total
```

Dude what

Using six threads resulted in a severe slowdown instead. What went horribly wrong?

*TODO: plot weak and strong scaling results.*


[^1]: Daniel Lemire covers this general principle in more detail in [his blog][lemire-hotspot]. Therein he referes to Casey Muratori's [article on performance excuses][muratori-excuses]. Read that as well if you haven't yet.

[^2]: Alternatively, use an mmapped file.

[^3]: Don't forget to `#include <omp.h>` and add the relevant compiler flag to the build script. I [created a simple Makefile][makefile] because I did not feel like fiddling with CMake.


[lemire-hotspot]: https://lemire.me/blog/2023/04/27/hotspot-performance-engineering-fails/
[muratori-excuses]: https://www.computerenhance.com/p/performance-excuses-debunked
[openmp]: https://www.openmp.org/wp-content/uploads/openmp-examples-4.5.0.pdf
[makefile]: https://github.com/loonatick-src/raytracing.github.io/blob/optimization/Makefile
