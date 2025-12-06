#include <rime_api.h>
#include <filesystem>
#include <vector>
#include <mutex>

namespace fs = std::filesystem;

#ifdef _WIN32 /* Windows */
#include <windows.h>
static HMODULE librime;
#define FREE_RIME() do { if (librime) { FreeLibrary(librime); librime = nullptr; } } while(0)
#define DLO(x) LoadLibraryA(x)
#define LOAD_RIME_FUNCTION(handle) reinterpret_cast<RimeGetApi>(GetProcAddress(handle, "rime_get_api"))
#define CLEAR_RIME_ERROR() ((void)0)

static HMODULE load_librime() {
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

#else /* Linux or Mac */

#if defined(__APPLE__) || defined(__MACH__)
#define LIBNAME "librime.dylib"
#else
#define LIBNAME "librime.so"
#endif
#include <dlfcn.h>
static void *librime;
#define FREE_RIME() do { if (librime) { dlclose(librime); librime = nullptr; } } while(0)
#define DLO(x) dlopen(x, RTLD_LAZY | RTLD_LOCAL| RTLD_DEEPBIND)
#define LOAD_RIME_FUNCTION(handle) reinterpret_cast<RimeGetApi>(dlsym(handle, "rime_get_api"))
#define CLEAR_RIME_ERROR() ((void)dlerror())
static void* load_librime() {
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
#endif

typedef RIME_FLAVORED(RimeApi) *(*RimeGetApi)(void);
static RimeApi* rime_api = nullptr;

static void get_api() {
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

typedef struct {
  RimeSessionId id;
  std::string type;
  std::string value;
} RimeNotificationMsg;

static std::vector<RimeNotificationMsg> msg_queue;
static std::vector<RimeNotificationMsg> lua_queue;
static std::mutex noti_mutex;

static void on_message(void* context_object,
    RimeSessionId session_id,
    const char* msg_type,
    const char* msg_value) {
  const std::string type = std::string(msg_type ? msg_type : "");
  const std::string value = std::string(msg_value ? msg_value : "");
  {
    std::lock_guard<std::mutex> lock(noti_mutex);
    msg_queue.push_back({session_id, type, value});
  }
}

extern "C" {
  RIME_API size_t drain_notifications(
      RimeSessionId* session_ids,
      const char** message_types,
      const char** message_values,
      size_t max_messages) {
    size_t count = 0;
    {
      std::lock_guard<std::mutex> lock(noti_mutex);
      lua_queue = msg_queue;
      count = (msg_queue.size() < max_messages) ? msg_queue.size() : max_messages;
      std::vector<RimeNotificationMsg>().swap(msg_queue); // clear the queue
    }
    for (size_t i = 0; i < count; i++) {
      session_ids[i] = lua_queue[i].id;
      message_types[i] = lua_queue[i].type.c_str();
      message_values[i] = lua_queue[i].value.c_str();
    }
    return count;
  }

  RIME_API int init_bridge() {
    get_api();
    if (!rime_api) return -1;
    rime_api->set_notification_handler(on_message, nullptr);
    FREE_RIME();
    return 0;
  }

  RIME_API void finalize_bridge() {
    get_api();
    if (!rime_api) return;
    rime_api->set_notification_handler(nullptr, nullptr);
    std::vector<RimeNotificationMsg>().swap(lua_queue); // clear the lua queue
    std::lock_guard<std::mutex> lock(noti_mutex);
    std::vector<RimeNotificationMsg>().swap(msg_queue); // clear the queue
  }
}
