#pragma once
#include <rime_api.h>
#include <rime_levers_api.h>
#include <filesystem>
#include <mutex>
#include <vector>
#include <assert.h>
namespace fs = std::filesystem;
template<typename T>
using vector = std::vector<T>;
using string = std::string;

#ifdef _WIN32
#include <windows.h>
inline unsigned int SetConsoleOutputCodePage(unsigned int codepage = CP_UTF8) {
  unsigned int cp = GetConsoleOutputCP();
  SetConsoleOutputCP(codepage);
  SetConsoleCP(codepage);
  return cp;
}
static HMODULE librime;
#define FREE_RIME() do { if (librime) { FreeLibrary(librime); librime = nullptr; } } while(0)
#define DLO(x) LoadLibraryA(x)
#define LOAD_RIME_FUNCTION(handle) reinterpret_cast<RimeGetApi>(GetProcAddress(handle, "rime_get_api"))
#define CLEAR_RIME_ERROR() ((void)0)

static inline HMODULE load_librime() {
  // default load the librime dll from the same directory as this module
  HMODULE hModule = nullptr;
  char modulePath[MAX_PATH] = {0};
  if (GetModuleHandleExA(
        GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        reinterpret_cast<LPCSTR>(&load_librime), &hModule)) {
    GetModuleFileNameA(hModule, modulePath, MAX_PATH);
    fs::path moduleDir = fs::path(modulePath).parent_path();
    fs::path rimePath = moduleDir / "rime.dll";
    HMODULE handle = DLO(rimePath.string().c_str());
    if (handle) return handle;
    rimePath = moduleDir / "librime.dll";
    handle = DLO(rimePath.string().c_str());
    if (handle) return handle;
  }
  HMODULE handle = DLO("rime.dll");
  if (handle) return handle;
  handle = DLO("librime.dll");
  return handle;
}

#else

#if defined(__APPLE__) || defined(__MACH__)
#define LIBNAME "librime.dylib"
#else
#define LIBNAME "librime.so"
#endif
#include <dlfcn.h>
#define FREE_RIME() do { if (librime) { dlclose(librime); librime = nullptr; } } while(0)
#define DLO(x) dlopen(x, RTLD_LAZY | RTLD_LOCAL| RTLD_DEEPBIND)
#define LOAD_RIME_FUNCTION(handle) reinterpret_cast<RimeGetApi>(dlsym(handle, "rime_get_api"))
#define CLEAR_RIME_ERROR() ((void)dlerror())
static inline void* load_librime() {
  void* handle = nullptr;
  Dl_info dl_info;
  if (dladdr((void*)&load_librime, &dl_info) == 0)
    return nullptr;
  const fs::path modulePath = fs::path(dl_info.dli_fname).parent_path();
  const fs::path rimePath = modulePath / LIBNAME;
  handle = DLO(rimePath.string().c_str());
  if (!handle)
    handle = DLO(LIBNAME);
  return handle;
}

static void *librime;
inline unsigned int SetConsoleOutputCodePage(unsigned int codepage = 65001) { return 0; }
#endif /* _WIN32 */


typedef RIME_FLAVORED(RimeApi) *(*RimeGetApi)(void);
static RimeApi* rime_api = nullptr;

#define RIMELEVERSAPI ((RimeLeversApi*)rime_api->find_module("levers")->get_api())
#define RIMEAPI rime_api

static inline void get_api() {
  if (rime_api) return;
  librime = load_librime();
  if (!librime) {
    fprintf(stderr, "Error: failed to load librime\n");
    return;
  }
  CLEAR_RIME_ERROR();
  RimeGetApi loader = LOAD_RIME_FUNCTION(librime);
  if (!loader) {
    fprintf(stderr, "Error: failed to find rime_get_api in librime\n");
    FREE_RIME();
    return;
  }
  rime_api = loader();
  if (!rime_api) {
    fprintf(stderr, "Error: rime_get_api returned null from librime\n");
    FREE_RIME();
  }
}
static inline void ensure_rime_api() {
  if (!rime_api) get_api();
  assert(rime_api);
}
