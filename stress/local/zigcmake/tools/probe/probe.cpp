// One call into each zig-libs library the CMake configs bring; prints one
// "<name> <value>" line each, exits 1 when a result is wrong.
#include <absl/strings/str_cat.h>
#include <expat.h>
#include <geos_c.h>
#include <tbb/blocked_range.h>
#include <tbb/parallel_reduce.h>
#include <cstdio>
#include <functional>
#include <string>

int main() {
  std::string a = absl::StrCat("abseil-", 42);
  const char *g = GEOSversion();
  long sum = tbb::parallel_reduce(
      tbb::blocked_range<long>(0, 1000), 0L,
      [](const tbb::blocked_range<long> &r, long acc) {
        for (long i = r.begin(); i != r.end(); ++i) acc += i;
        return acc;
      },
      std::plus<long>());
  XML_Expat_Version e = XML_ExpatVersionInfo();
  std::printf("run_absl %s\nrun_geos %s\nrun_tbb_sum %ld\nrun_expat %d.%d.%d\n", a.c_str(), g, sum, e.major, e.minor, e.micro);
  return a == "abseil-42" && g != nullptr && sum == 499500 && e.major == 2 ? 0 : 1;
}
