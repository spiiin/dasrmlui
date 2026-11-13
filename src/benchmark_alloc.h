#pragma once
#include <cstdint>
namespace rui_bench {
struct Allocations { uint64_t count=0, bytes=0; };
extern thread_local bool counting;
extern thread_local Allocations allocations;
bool allocation_selftest();
}
