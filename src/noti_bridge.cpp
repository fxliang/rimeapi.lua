#include <rime_api.h>
#include <filesystem>
#include <vector>
#include <mutex>
#include <cstring>

namespace fs = std::filesystem;

#ifdef _WIN32 /* Windows */
#include <windows.h>
static HMODULE librime;
#define FREE_RIME() do { if (librime) { FreeLibrary(librime); librime = nullptr; } } while(0)
#define DLO(x) LoadLibraryA(x)
#define LOAD_RIME_FUNCTION(handle) reinterpret_cast<RimeGetApi>(GetProcAddress(handle, "rime_get_api"))
#define CLEAR_RIME_ERROR() ((void)0)
#ifdef _MSC_VER
#define strdup(x) _strdup(x)
#endif

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

inline std::wstring string_to_wstring(const std::string& str,
    int code_page = CP_ACP) {
  // support CP_ACP and CP_UTF8 only
  if (code_page != 0 && code_page != CP_UTF8) return L"";
  // calc len
  int len = MultiByteToWideChar(code_page, 0, str.c_str(), (int)str.size(), NULL, 0);
  if (len <= 0) return L"";
  std::wstring res;
  wchar_t* buffer = new wchar_t[len + 1];
  MultiByteToWideChar(code_page, 0, str.c_str(), (int)str.size(), buffer, len);
  buffer[len] = L'\0';
  res.append(buffer);
  delete[] buffer;
  return res;
}

inline std::string wstring_to_string(const std::wstring& wstr,
    int code_page = CP_ACP) {
  // support CP_ACP and CP_UTF8 only
  if (code_page != 0 && code_page != CP_UTF8) return "";
  int len = WideCharToMultiByte(code_page, 0, wstr.c_str(), (int)wstr.size(), NULL, 0, NULL, NULL);
  if (len <= 0) return "";
  std::string res;
  char* buffer = new char[len + 1];
  WideCharToMultiByte(code_page, 0, wstr.c_str(), (int)wstr.size(), buffer, len, NULL, NULL);
  buffer[len] = '\0';
  res.append(buffer);
  delete[] buffer;
  return res;
}

#define TO_ASCII_STR(str) wstring_to_string(string_to_wstring(str, CP_UTF8), CP_ACP)

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
#define TO_ASCII_STR(str) (str)
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
static std::mutex noti_mutex;

static void on_message(void* context_object,
    RimeSessionId session_id,
    const char* msg_type,
    const char* msg_value) {
  const std::string type = TO_ASCII_STR(msg_type ? msg_type : "");
  const std::string value = TO_ASCII_STR(msg_value ? msg_value : "");
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
    std::lock_guard<std::mutex> lock(noti_mutex);
    size_t count = (msg_queue.size() < max_messages) ? msg_queue.size() : max_messages;
    for (size_t i = 0; i < count; i++) {
      session_ids[i] = msg_queue[i].id;
      message_types[i] = strdup(msg_queue[i].type.c_str());
      message_values[i] = strdup(msg_queue[i].value.c_str());
    }
    msg_queue.clear();
    msg_queue.shrink_to_fit();
    return count;
  }

  RIME_API void free_drain_messages(
      const char** message_types,
      const char** message_values,
      size_t count) {
    for (size_t i = 0; i < count; i++) {
      if (message_types[i]) free((void*)message_types[i]);
      if (message_values[i]) free((void*)message_values[i]);
    }
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
    std::lock_guard<std::mutex> lock(noti_mutex);
    msg_queue.clear();
  }
}
