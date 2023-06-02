# This file was generated, do not modify it. # hide
function factorial_naive(n)
	n == 0 && return 1
	return n * factorial_naive(n-1)
end

@btime factorial_naive($(13))