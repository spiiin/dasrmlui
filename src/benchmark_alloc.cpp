// Only linked into dasrmlui_bench. Counts main-thread C++ new requests, not malloc,
// GPU memory, driver allocations, or logical allocations inside daScript pools.
#include "benchmark_alloc.h"
#include <cstdlib>
#include <malloc.h>
#include <new>
// Supply the same reuse-cache implementation as the linked runtime, without its
// global operators. This object satisfies the archive symbols; upstream is unmodified.
#define DAS_NO_GLOBAL_NEW_AND_DELETE
#include "free_list.cpp"
namespace rui_bench {
thread_local bool counting=false;
thread_local Allocations allocations;
static void record(size_t size) { if(counting) { ++allocations.count; allocations.bytes+=size; } }
}
void* operator new(size_t n) {
#if DAS_FREE_LIST && !defined(__linux__) && !DAS_ENABLE_DLL && !DAS_GC_DEBUG
    auto p=das::reuse_cache_allocate(n ? n : 1);
#else
    auto p=std::malloc(n ? n : 1);
#endif
    if(p) { rui_bench::record(n); return p; } throw std::bad_alloc();
}
void* operator new[](size_t n) { return ::operator new(n); }
void operator delete(void* p) noexcept {
#if DAS_FREE_LIST && !defined(__linux__) && !DAS_ENABLE_DLL && !DAS_GC_DEBUG
    if(p) das::reuse_cache_free(p);
#else
    std::free(p);
#endif
}
void operator delete[](void* p) noexcept { ::operator delete(p); }
void operator delete(void* p,size_t) noexcept { ::operator delete(p); }
void operator delete[](void* p,size_t) noexcept { ::operator delete(p); }
void* operator new(size_t n,const std::nothrow_t&) noexcept { try { return ::operator new(n); } catch(...) { return nullptr; } }
void* operator new[](size_t n,const std::nothrow_t& t) noexcept { return ::operator new(n,t); }
void operator delete(void* p,const std::nothrow_t&) noexcept { ::operator delete(p); }
void operator delete[](void* p,const std::nothrow_t&) noexcept { ::operator delete(p); }
void* operator new(size_t n,std::align_val_t a) {
    if(auto p=_aligned_malloc(n ? n : 1,size_t(a))) { rui_bench::record(n); return p; }
    throw std::bad_alloc();
}
void* operator new[](size_t n,std::align_val_t a) { return ::operator new(n,a); }
void operator delete(void* p,std::align_val_t) noexcept { _aligned_free(p); }
void operator delete[](void* p,std::align_val_t a) noexcept { ::operator delete(p,a); }
void operator delete(void* p,size_t,std::align_val_t a) noexcept { ::operator delete(p,a); }
void operator delete[](void* p,size_t,std::align_val_t a) noexcept { ::operator delete(p,a); }
void* operator new(size_t n,std::align_val_t a,const std::nothrow_t&) noexcept { try { return ::operator new(n,a); } catch(...) { return nullptr; } }
void* operator new[](size_t n,std::align_val_t a,const std::nothrow_t& t) noexcept { return ::operator new(n,a,t); }
void operator delete(void* p,std::align_val_t a,const std::nothrow_t&) noexcept { ::operator delete(p,a); }
void operator delete[](void* p,std::align_val_t a,const std::nothrow_t&) noexcept { ::operator delete(p,a); }
bool rui_bench::allocation_selftest() {
    allocations={}; counting=true;
    void* normal=::operator new(123);
    void* aligned=::operator new(71,std::align_val_t(64));
    counting=false;
    bool ok=allocations.count==2 && allocations.bytes==194 && (uintptr_t(aligned)%64)==0;
    ::operator delete(normal); ::operator delete(aligned,std::align_val_t(64));
    allocations={}; return ok;
}
