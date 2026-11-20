/* r-zig: conda-forge's libstdc++ was configured against a glibc 2.17
   sysroot whose math.h declared the obsolete int isinf(double) and
   isnan(double); zig's glibc headers do not, so <cmath>'s
   `using ::isinf;` fails. */
#pragma GCC system_header
#include_next <bits/c++config.h>
#undef _GLIBCXX_HAVE_OBSOLETE_ISINF
#undef _GLIBCXX_HAVE_OBSOLETE_ISNAN
