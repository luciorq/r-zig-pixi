/* r-zig: zig's glibc headers carry sys/single_threaded.h for every glibc
   and #error below 2.32; libstdc++ includes it when __has_include finds
   it. At the 2.17 floor there is no __libc_single_threaded: "not single
   threaded", so libstdc++ takes its atomic path. */
#pragma GCC system_header
#ifndef _SYS_SINGLE_THREADED_H
#define _SYS_SINGLE_THREADED_H
static const char __libc_single_threaded = 0;
#endif
