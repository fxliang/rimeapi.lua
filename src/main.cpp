#include "lua_export_type.h"
#include <rime_api.h>
#include <rime_levers_api.h>
#include <cstring>
#include <assert.h>
#include <mutex>
#include <filesystem>
#include <unordered_set>
#include <iostream>
#ifdef __GNUC__
#include <cxxabi.h>
#endif
#ifdef _WIN32
#include <windows.h>
inline unsigned int SetConsoleOutputCodePage(unsigned int codepage = CP_UTF8) {
  unsigned int cp = GetConsoleOutputCP();
  SetConsoleOutputCP(codepage);
  return cp;
}
HMODULE librime;
#else
#include <dlfcn.h>
void *librime;
inline unsigned int SetConsoleOutputCodePage(unsigned int codepage = 65001) { return 0; }
#endif /* _WIN32 */

using namespace std;

typedef RIME_FLAVORED(RimeApi) *(*RimeGetApi)(void);
RimeApi* rime_api = nullptr;

#define RIMELEVERSAPI ((RimeLeversApi*)rime_api->find_module("levers")->get_api())
#define RIMEAPI rime_api

static std::unordered_set<RimeConfig*> cfg_borrowed_set;
static std::unordered_set<RimeSchemaList*> schemalist_borrowed_set;
static std::mutex cfg_borrowed_mutex;
static std::mutex schemalist_borrowed_mutex;

#define PUSH_VALUE_OR_NIL(L, val, cond, push_func) do {                       \
    if (cond) push_func(L, val); else lua_pushnil(L); } while(0)
// Thread-safe check wrappers
static inline bool is_config_borrowed(RimeConfig* cfg) {
  if (!cfg) return false;
  std::lock_guard<std::mutex> lk(cfg_borrowed_mutex);
  return cfg_borrowed_set.find(cfg) != cfg_borrowed_set.end();
}
static inline bool is_schemalist_borrowed(RimeSchemaList* list) {
  if (!list) return false;
  std::lock_guard<std::mutex> lk(schemalist_borrowed_mutex);
  return schemalist_borrowed_set.find(list) != schemalist_borrowed_set.end();
}

static inline void set_config_borrowed(RimeConfig* cfg, bool borrowed) {
  if (!cfg) return;
  std::lock_guard<std::mutex> lk(cfg_borrowed_mutex);
  if (borrowed)
    cfg_borrowed_set.insert(cfg);
  else
    cfg_borrowed_set.erase(cfg);
}

static std::unordered_set<void*> levers_settings_owned;
static std::mutex levers_settings_mutex;

// 为char*添加LuaType特化
template<>
struct LuaType<char*> {
  static void pushdata(lua_State *L, char* str) {
    lua_pushstring(L, (str ? str : ""));
  }

  // 简化的todata实现，主要用于setter操作
  static char* todata(lua_State *L, int i, C_State * = nullptr) {
    // 对于setter操作，我们返回lua字符串的指针
    // 注意：这个指针的生命周期由Lua管理
    return const_cast<char*>(luaL_checkstring(L, i));
  }
};
// 为const char*添加LuaType特化
template<>
struct LuaType<const char*> {
  static void pushdata(lua_State *L, const char* str) {
    lua_pushstring(L, (str ? str : ""));
  }

  static const char* todata(lua_State *L, int i, C_State * = nullptr) {
    return luaL_checkstring(L, i);
  }
};

// 为RimeStringSlice添加LuaType特化
template<>
struct LuaType<RimeStringSlice> {
  struct Owned {
    std::string s;
    RimeStringSlice slice;
    Owned(const char* str, size_t len) : s(str ? std::string(str, len) : std::string()) {
      slice.str = s.empty() ? nullptr : s.c_str();
      slice.length = s.size();
    }
    ~Owned() {}
  };

  static const LuaTypeInfo *type() {
    return &LuaTypeInfo::make<LuaType<RimeStringSlice>>();
  }

  static int gc(lua_State *L) {
    Owned *o = (Owned*)luaL_checkudata(L, 1, type()->name());
    if (o) o->~Owned();
    return 0;
  }

  static void pushdata(lua_State *L, const RimeStringSlice &o) {
    if (!o.str || o.length == 0) {
      lua_pushnil(L);
      return;
    }
    void *u = lua_newuserdata(L, sizeof(Owned));
    new(u) Owned(o.str, (size_t)o.length);

    luaL_getmetatable(L, type()->name());
    if (lua_isnil(L, -1)) {
      lua_pop(L, 1);
      luaL_newmetatable(L, type()->name());
      lua_pushlightuserdata(L, (void*)type());
      lua_setfield(L, -2, "type");
      lua_pushcfunction(L, gc);
      lua_setfield(L, -2, "__gc");
    }
    lua_setmetatable(L, -2);
  }

  static RimeStringSlice &todata(lua_State *L, int i, C_State * = NULL) {
    Owned *o = (Owned*)luaL_checkudata(L, i, type()->name());
    return o->slice;
  }
};

// 通用shared_ptr特化 - 自动内存管理
template<typename T>
struct LuaType<std::shared_ptr<T>> {
  using PtrType = std::shared_ptr<T>;
  static const LuaTypeInfo *type() {
    return &LuaTypeInfo::make<LuaType<PtrType>>();
  }
  static int gc(lua_State *L) {
#ifdef DEBUG
    std::string demangled_name = LuaType<PtrType>::type()->name();
    printf("%s::%s referenced\n", demangled_name.c_str(), __func__);
#endif
    PtrType *p = (PtrType*)luaL_checkudata(L, 1, type()->name());
    if (p && p->get()) {
#define CHECKT(t) (std::is_same<T, t>::value)
      // free the underlying resource if needed, not free the shared_ptr itself
      if constexpr CHECKT(RimeConfig){
        if (!is_config_borrowed(p->get()))
          RIMEAPI->config_close(p->get());
        {
          std::lock_guard<std::mutex> lk(cfg_borrowed_mutex);
          cfg_borrowed_set.erase(p->get());
        }
      } else if constexpr CHECKT(RimeConfigIterator) {
        RIMEAPI->config_end(p->get());
      } else if constexpr CHECKT(RimeStatus) {
        RIMEAPI->free_status(p->get());
      } else if constexpr CHECKT(RimeContext) {
        RIMEAPI->free_context(p->get());
      } else if constexpr CHECKT(RimeCommit) {
        RIMEAPI->free_commit(p->get());
      } else if constexpr CHECKT(RimeSchemaList) {
        bool borrowed = is_schemalist_borrowed(p->get());
        const auto deleter = borrowed ? RIMELEVERSAPI->schema_list_destroy : RIMEAPI->free_schema_list;
        deleter(p->get());
        {
          std::lock_guard<std::mutex> lk(schemalist_borrowed_mutex);
          schemalist_borrowed_set.erase(p->get());
        }
      }
#undef CHECKT
      p->~PtrType();
    }
    return 0;
  }
  static void pushdata(lua_State *L, PtrType &t) {
    if (!t) {
      lua_pushnil(L);
      return;
    }
    void *u = lua_newuserdata(L, sizeof(PtrType));
    new(u) PtrType(t);

    luaL_getmetatable(L, type()->name());
    if (lua_isnil(L, -1)) {
      lua_pop(L, 1);
      luaL_newmetatable(L, type()->name());
      lua_pushlightuserdata(L, (void*)type());
      lua_setfield(L, -2, "type");
      lua_pushcfunction(L, gc);
      lua_setfield(L, -2, "__gc");
    }
    lua_setmetatable(L, -2);
  }
  static PtrType &todata(lua_State *L, int i, C_State* = NULL) {
    PtrType *p = (PtrType*)luaL_checkudata(L, i, type()->name());
    return *p;
  }
};

template <typename T>
static T* smart_shared_ptr_todata(lua_State *L, int index = 1) {
  // Return nullptr if the Lua value at index is nil
  if (lua_isnil(L, index)) return nullptr;
  // If it's a std::shared_ptr<T> userdata, unwrap and return the raw pointer
  const char* sptr_type_name = LuaType<std::shared_ptr<T>>::type()->name();
  if (luaL_testudata(L, index, sptr_type_name)) {
    auto &sptr = LuaType<std::shared_ptr<T>>::todata(L, index);
    return sptr ? sptr.get() : nullptr;
  }
  // If it's a value userdata of T, return its address
  const char* val_type_name = LuaType<T>::type()->name();
  if (luaL_testudata(L, index, val_type_name)) {
    return &LuaType<T>::todata(L, index);
  }
  // If it's a lightuserdata, assume it points to T
  if (lua_islightuserdata(L, index)) {
    return static_cast<T*>(lua_touserdata(L, index));
  }
  // Not a recognized type
  return nullptr;
}

// Lua userdata wrapper for RimeSessionId so session is destroyed on GC.
struct RimeSessionStruct { RimeSessionId id{0}; };
static void RimeSession_pushdata(lua_State *L, RimeSessionId id) {
  if (!id) { lua_pushnil(L); return; }
  void *u = lua_newuserdata(L, sizeof(RimeSessionStruct));
  RimeSessionStruct *s = new(u) RimeSessionStruct();
  s->id = id;
  const auto ensure_rime_session_mt = [](lua_State *L) {
    luaL_getmetatable(L, "RimeSession");
    if (lua_isnil(L, -1)) {
      lua_pop(L, 1);
      luaL_newmetatable(L, "RimeSession");
      lua_pushcfunction(L, [](lua_State *L)->int {
          RimeSessionStruct *s = (RimeSessionStruct*)luaL_checkudata(L, 1, "RimeSession");
          if (s && s->id) {
            if (auto api = RIMEAPI) api->destroy_session(s->id);
            s->id = 0;
          }
          return 0;
          });
      lua_setfield(L, -2, "__gc");
      // push a __index function to get id by .id
      lua_pushcfunction(L, [](lua_State *L)->int {
          RimeSessionStruct *s = (RimeSessionStruct*)luaL_checkudata(L, 1, "RimeSession");
          const char* key = luaL_checkstring(L, 2);
          if (strcmp(key, "id") == 0) {
            PUSH_VALUE_OR_NIL(L, (lua_Integer)s->id, s && s->id, lua_pushinteger);
            return 1;
          } else if (!strcmp(key, "str")) {
            char buf[32];
            auto format = sizeof(void*) == 4 ? ("%08X") : ("%016llX");
            snprintf(buf, sizeof(buf), format, (RimeSessionId)s->id);
            lua_pushstring(L, buf);
            return 1;
          }
          lua_pushnil(L);
          return 1;
        });
      lua_setfield(L, -2, "__index");
      lua_pushlightuserdata(L, (void*)"RimeSession");
      lua_setfield(L, -2, "type");
    }
    lua_pop(L, 1);
  };
  ensure_rime_session_mt(L);
  luaL_setmetatable(L, "RimeSession");
}
static RimeSessionId RimeSession_todata(lua_State *L, int idx) {
  if (lua_isnil(L, idx)) return 0;
  if (lua_isnumber(L, idx)) {
    lua_Number n = lua_tonumber(L, idx);
    if (n == (lua_Number)(RimeSessionId)n) return (RimeSessionId)n;
  }
  if (luaL_testudata(L, idx, "RimeSession")) {
    RimeSessionStruct *s = (RimeSessionStruct*)luaL_checkudata(L, idx, "RimeSession");
    return s ? s->id : 0;
  }
  if (lua_isnumber(L, idx)) return (RimeSessionId)lua_tointeger(L, idx);
  luaL_error(L, "Expected RimeSessionId (userdata or integer) at arg %d", idx);
  return 0;
}

template<typename T, typename MemberType, MemberType T::*member>
static int unified_get(lua_State *L) {
  T* t = smart_shared_ptr_todata<T>(L, 1);
  if (!t) {
    lua_pushnil(L);
    return 1;
  }
  // push data
  LuaType<MemberType>::pushdata(L, t->*member);
  return 1;
}

template<typename T, typename MemberType, MemberType T::*member>
static int unified_set(lua_State *L) {
  T* t = smart_shared_ptr_todata<T>(L, 1);
  if (!t) {
    luaL_error(L, "Invalid userdata type for setting member");
    return 0;
  }
  // 设置成员值
  t->*member = LuaType<MemberType>::todata(L, 2);
  return 0;
}

#define SMART_GET(T, member) unified_get<T, decltype(T::member), &T::member>
#define SMART_SET(T, member) unified_set<T, decltype(T::member), &T::member>

// Specialized getter for boolean-like members where the C type may be int/Bool
template<typename T, typename MemberType, MemberType T::*member>
static int unified_get_bool(lua_State *L) {
  T* t = smart_shared_ptr_todata<T>(L, 1);
  PUSH_VALUE_OR_NIL(L, !!(t->*member), t != nullptr, lua_pushboolean);
  return 1;
}
#define SMART_GET_BOOL(T, member) unified_get_bool<T, decltype(T::member), &T::member>

template <typename T, typename = std::void_t<>>
struct has_data_size : std::false_type {};

template <typename T>
struct has_data_size<T, std::void_t<decltype(std::declval<T>().data_size)>> : std::true_type {};

template <typename T>
static int raw_make(lua_State *L) {
  auto t = std::make_shared<T>();
  if constexpr (has_data_size<T>::value)
    RIME_STRUCT_INIT(T, *t);
  LuaType<std::shared_ptr<T>>::pushdata(L, t);
  return 1;
}
template <typename T>
static int raw_make_struct(lua_State *L) {
  T t;
  LuaType<T>::pushdata(L, t);
  return 1;
}

template <typename T>
static int type(lua_State* L) {
#ifdef __GNUC__
    const char* mangled = LuaType<T>::type()->name();
    int status = 0;
    char* demangled = abi::__cxa_demangle(mangled, nullptr, nullptr, &status);
    if (status == 0 && demangled) {
      lua_pushstring(L, demangled);
      free(demangled);
      return 1;
    }
#endif
    lua_pushstring(L, LuaType<std::shared_ptr<T>>::type()->name());
    return 1;
  }

namespace RimeCompositionReg {
  using T = RimeComposition;
  static int tostring(lua_State* L) {
    auto t = LuaType<T>::todata(L, 1);
    std::string repr = "{\n";
    if (t.preedit)
      repr += "  preedit=\"" + std::string(t.preedit) + "\",\n";
    repr += "  length=" + std::to_string(t.length) + ",\n";
    repr += "  cursor_pos=" + std::to_string(t.cursor_pos) + ",\n";
    repr += "  sel_start=" + std::to_string(t.sel_start) + ",\n";
    repr += "  sel_end=" + std::to_string(t.sel_end) + "\n}";
    lua_pushstring(L, repr.c_str());
    return 1;
  }
  static const luaL_Reg funcs[] = {
    {"RimeComposition", raw_make_struct<T>},
    {nullptr, nullptr}
  };
  static const luaL_Reg methods[] = {
    {"__tostring", tostring},
    {nullptr, nullptr}
  };
  static const luaL_Reg vars_get[] = {
    {"length", SMART_GET(T, length)},
    {"cursor_pos", SMART_GET(T, cursor_pos)},
    {"sel_start", SMART_GET(T, sel_start)},
    {"sel_end", SMART_GET(T, sel_end)},
    {"preedit", SMART_GET(T, preedit)},
    {"type", type<T>},
    {nullptr, nullptr}
  };
  static const luaL_Reg vars_set[] = { {nullptr, nullptr} };
}

namespace RimeCandidateReg {
  using T = RimeCandidate;
  static int tostring(lua_State* L) {
    T* t = smart_shared_ptr_todata<T>(L);
    std::string repr = "{";
    if (t->text)
      repr += "  text=\"" + std::string(t->text);
    if (t->comment)
      repr += "\",  comment=\"" + std::string(t->comment);
    repr +=  + "\"  }";
    lua_pushstring(L, repr.c_str());
    return 1;
  }
  static const luaL_Reg funcs[] = {
    {"RimeCandidate", raw_make<T>},
    {nullptr, nullptr}
  };
  static const luaL_Reg methods[] = {
    {"__tostring", tostring},
    {nullptr, nullptr}
  };
  static const luaL_Reg vars_get[] = {
    {"text", SMART_GET(T, text)},
    {"comment", SMART_GET(T, comment)},
    {"type", type<std::shared_ptr<T>>},
    {nullptr, nullptr}
  };
  static const luaL_Reg vars_set[] = { {nullptr, nullptr} };
}

static std::string strzbool(bool b) { return b ? "true" : "false"; }

namespace RimeMenuReg {
  using T = RimeMenu;
  static int tostring(lua_State* L) {
    T t = LuaType<T>::todata(L, 1);  // 直接使用值类型
    std::string repr = "{\n";
    repr += "  page_size=" + std::to_string(t.page_size) + ", \n";
    repr += "  page_no=" + std::to_string(t.page_no) + ", \n";
    repr += "  is_last_page=" + strzbool(t.is_last_page) + ", \n";
    repr += "  highlighted_candidate_index=" + std::to_string(t.highlighted_candidate_index) + ", \n";
    repr += "  num_candidates=" + std::to_string(t.num_candidates) + ", \n";
    repr += "  select_keys=\"" + std::string(t.select_keys ? t.select_keys : "") + std::string(", \n");
    // get candidates info
    repr += "  candidates=[";
    for (int i = 0; i < t.num_candidates; ++i) {
      if (i > 0) repr += ", ";
      if (t.candidates && t.candidates[i].text) {
        repr += "\"" + std::string(t.candidates[i].text) + "\"";
        if (t.candidates[i].comment)
          repr += "(\"" + std::string(t.candidates[i].comment) + "\")";
      } else {
        repr += "nil";
      }
    }
    repr += "]\n";
    repr += "}";
    lua_pushstring(L, repr.c_str());
    return 1;
  }
  // get candidates as a table of RimeCandidate
  static int get_candidates(lua_State* L) {
    T menu = LuaType<T>::todata(L, 1);  // 直接使用值类型
    lua_newtable(L);
    for (int i = 0; i < menu.num_candidates; ++i) {
      LuaType<RimeCandidate>::pushdata(L, menu.candidates[i]);  // 直接推送RimeCandidate
      lua_rawseti(L, -2, i+1);  // 使用1-based索引，匹配C数组
    }
    return 1;
  }
  static const luaL_Reg funcs[] = {
    {"RimeMenu", raw_make_struct<T>},
    {nullptr, nullptr}
  };
  static const luaL_Reg methods[] = {
    {"__tostring", tostring},
    {nullptr, nullptr}
  };
  static const luaL_Reg vars_get[] = {
    {"page_size", SMART_GET(T, page_size)},
    {"page_no", SMART_GET(T, page_no)},
    {"is_last_page", SMART_GET_BOOL(T, is_last_page)},
    {"highlighted_candidate_index", SMART_GET(T, highlighted_candidate_index)},
    {"num_candidates", SMART_GET(T, num_candidates)},
    {"candidates", get_candidates},
    {"select_keys", SMART_GET(T, select_keys)},
    {"type", type<T>},
    {nullptr, nullptr}
  };
  static const luaL_Reg vars_set[] = { {nullptr, nullptr} };
}

namespace RimeCommitReg {
  using T = RimeCommit;
  static int tostring(lua_State* L) {
    T* t = smart_shared_ptr_todata<T>(L);
    std::string repr = "";
    if (t->text)
      repr += std::string(t->text);
    lua_pushstring(L, repr.c_str());
    return 1;
  }
  static const luaL_Reg funcs[] = {
    {"RimeCommit", raw_make<T>},
    {nullptr, nullptr}
  };
  static const luaL_Reg methods[] = {
    {"__tostring", tostring},
    {nullptr, nullptr}
  };
  static const luaL_Reg vars_get[] = {
    {"text", SMART_GET(T, text)},
    {"type", type<std::shared_ptr<T>>},
    {nullptr, nullptr}
  };
  static const luaL_Reg vars_set[] = { {nullptr, nullptr} };
}

namespace RimeContextReg {
  using T = RimeContext;

  static const luaL_Reg funcs[] = {
    {"RimeContext", raw_make<T>},
    {nullptr, nullptr}
  };
  static const luaL_Reg methods[] = { {nullptr, nullptr} };
  static const luaL_Reg vars_get[] = {
    {"composition", SMART_GET(T, composition)},
    {"menu", SMART_GET(T, menu)},
    {"commit_text_preview", SMART_GET(T, commit_text_preview)},
    {"select_labels", SMART_GET(T, select_labels)},
    {"type", type<std::shared_ptr<T>>},
    {nullptr, nullptr}
  };
  static const luaL_Reg vars_set[] = { {nullptr, nullptr} };
}

namespace RimeStatusReg {
  using T = RimeStatus;
  static int tostring(lua_State* L) {
    T* t = smart_shared_ptr_todata<T>(L);
    std::string repr = "{\n";
    if (t->schema_id)
      repr += "  schema_id=\"" + std::string(t->schema_id) + "\", \n";
    if (t->schema_name)
      repr += "  schema_name=\"" + std::string(t->schema_name) + "\", \n";
    repr += "  is_disabled=" + strzbool(t->is_disabled) + ", \n";
    repr += "  is_composing=" + strzbool(t->is_composing) + ", \n";
    repr += "  is_ascii_mode=" + strzbool(t->is_ascii_mode) + ", \n";
    repr += "  is_full_shape=" + strzbool(t->is_full_shape) + ", \n";
    repr += "  is_simplified=" + strzbool(t->is_simplified) + ", \n";
    repr += "  is_traditional=" + strzbool(t->is_traditional) + ", \n";
    repr += "  is_ascii_punct=" + strzbool(t->is_ascii_punct) + " \n}";
    lua_pushstring(L, repr.c_str());
    return 1;
  }
  static const luaL_Reg funcs[] = {
    {"RimeStatus", raw_make<T>},
    {nullptr, nullptr}
  };
  static const luaL_Reg methods[] = {
    {"__tostring", tostring},
    {nullptr, nullptr}
  };
  static const luaL_Reg vars_get[] = {
    {"schema_id", SMART_GET(T, schema_id)},
    {"schema_name", SMART_GET(T, schema_name)},
    {"is_disabled", SMART_GET_BOOL(T, is_disabled)},
    {"is_composing", SMART_GET_BOOL(T, is_composing)},
    {"is_ascii_mode", SMART_GET_BOOL(T, is_ascii_mode)},
    {"is_full_shape", SMART_GET_BOOL(T, is_full_shape)},
    {"is_simplified", SMART_GET_BOOL(T, is_simplified)},
    {"is_traditional", SMART_GET_BOOL(T, is_traditional)},
    {"is_ascii_punct", SMART_GET_BOOL(T, is_ascii_punct)},
    {"type", type<std::shared_ptr<T>>},
    {nullptr, nullptr}
  };
  static const luaL_Reg vars_set[] = { {nullptr, nullptr} };
}

namespace RimeCandidateListIteratorReg {
  using T = RimeCandidateListIterator;
  static const luaL_Reg funcs[] = {
    {"RimeCandidateListIterator", raw_make<T>},
    {nullptr, nullptr}
  };
  static const luaL_Reg methods[] = { {nullptr, nullptr} };
  static const luaL_Reg vars_get[] = {
    {"ptr", SMART_GET(T, ptr)},
    {"index", SMART_GET(T, index)},
    {"candidate", SMART_GET(T, candidate)},
    {"type", type<std::shared_ptr<T>>},
    {nullptr, nullptr}
  };
  static const luaL_Reg vars_set[] = { {nullptr, nullptr} };
}

namespace RimeConfigReg {
  using T = RimeConfig;
#define DEFINE_GET_METHOD(name, value_type, pushfunc) \
  static int name(lua_State* L) { \
    T* t = smart_shared_ptr_todata<T>(L); \
    const char* key = luaL_checkstring(L, 2); \
    value_type value; \
    PUSH_VALUE_OR_NIL(L, value, RIMEAPI->config_##name(t, key, &value), pushfunc); \
    return 1; \
  }
#define DEFINE_SET_METHOD(name, value_type, checkfunc) \
  static int name(lua_State* L) { \
    T* t = smart_shared_ptr_todata<T>(L); \
    const char* key = luaL_checkstring(L, 2); \
    value_type value = checkfunc(L, 3); \
    bool ret = RIMEAPI->config_##name(t, key, value); \
    lua_pushboolean(L, ret); \
    return 1; \
  }
  static int reload(lua_State* L) {
    T* t = smart_shared_ptr_todata<T>(L);
    // 方法调用时 Lua 堆栈: 1=self (config), 2=new_config_id
    if (!t || !lua_isstring(L, 2)) {
      lua_pushboolean(L, false);
    } else {
      const char *new_config_id = lua_tostring(L, 2);
      if (RimeApi *api = RIMEAPI) {
        bool was_borrowed = is_config_borrowed(t);
        if (!was_borrowed)
          api->config_close(t);
        Bool ok = api->config_open(new_config_id, t);
        set_config_borrowed(t, was_borrowed && !ok);
        lua_pushboolean(L, !!ok);
      } else
        lua_pushboolean(L, false);
    }
    return 1;
  }
  static int close(lua_State* L) {
    T* t = smart_shared_ptr_todata<T>(L);
    bool ret = false;
    if (t) {
      if (is_config_borrowed(t)) {
        ret = false;
      } else {
        ret = RIMEAPI->config_close(t);
        set_config_borrowed(t, false);
      }
    }
    lua_pushboolean(L, ret);
    return 1;
  }
  static int get_string(lua_State* L) {
    T* t = smart_shared_ptr_todata<T>(L);
    const char* key = luaL_checkstring(L, 2);
    int buffer_size = 256;
    if (lua_gettop(L) > 2)
      buffer_size = luaL_checkinteger(L, 3);
    std::unique_ptr<char[]> buffer = std::make_unique<char[]>(buffer_size);
    PUSH_VALUE_OR_NIL(L, buffer.get(), RIMEAPI->config_get_string(t, key, buffer.get(), buffer_size), lua_pushstring);
    return 1;
  }
  static int get_cstring(lua_State* L) {
    T* t = smart_shared_ptr_todata<T>(L);
    const char* key = luaL_checkstring(L, 2);
    const char* value = RIMEAPI->config_get_cstring(t, key);
    PUSH_VALUE_OR_NIL(L, value, value != nullptr, lua_pushstring);
    return 1;
  }
  DEFINE_GET_METHOD(get_int, int, lua_pushinteger)
  DEFINE_GET_METHOD(get_bool, int, lua_pushboolean)
  DEFINE_GET_METHOD(get_double, double, lua_pushnumber)
  DEFINE_SET_METHOD(set_int, int, luaL_checkinteger)
  DEFINE_SET_METHOD(set_string, const char*, luaL_checkstring)
  DEFINE_SET_METHOD(set_bool, int, lua_toboolean)
  DEFINE_SET_METHOD(set_double, double, luaL_checknumber)
  static const luaL_Reg funcs[] = {
    {"RimeConfig", raw_make<T>},
    {nullptr, nullptr}
  };
  static const luaL_Reg methods[] = {
    {"open", reload},
    {"reload", reload},
    {"close", close},
    {"get_int", get_int},
    {"get_string", get_string},
    {"get_bool", get_bool},
    {"get_double", get_double},
    {"get_cstring", get_cstring},
    {"set_int", set_int},
    {"set_string", set_string},
    {"set_bool", set_bool},
    {"set_double", set_double},
    {nullptr, nullptr}
  };
  static const luaL_Reg vars_get[] = {
    {"ptr", SMART_GET(T, ptr)},
    {"type", type<std::shared_ptr<T>>},
    {nullptr, nullptr}
  };
  static const luaL_Reg vars_set[] = { {nullptr, nullptr} };
}

namespace RimeConfigIteratorReg {
  using T = RimeConfigIterator;
  static const luaL_Reg funcs[] = {
    {"RimeConfigIterator", raw_make<T>},
    {nullptr, nullptr}
  };
  static const luaL_Reg methods[] = { {nullptr, nullptr} };
  static const luaL_Reg vars_get[] = {
    {"list", SMART_GET(T, list)},
    {"map", SMART_GET(T, map)},
    {"index", SMART_GET(T, index)},
    {"key", SMART_GET(T, key)},
    {"path", SMART_GET(T, path)},
    {"type", type<std::shared_ptr<T>>},
    {nullptr, nullptr}
  };
  static const luaL_Reg vars_set[] = { {nullptr, nullptr} };
}

namespace RimeSchemaListItemReg {
  using T = RimeSchemaListItem;
  static int tostring(lua_State* L) {
    T t = LuaType<T>::todata(L, 1);  // 直接使用值类型
    std::string repr = "";
    if (t.schema_id)
      repr += "  schema_id=\"" + std::string(t.schema_id) + "\",\t";
    if (t.name)
      repr += "  name=\"" + std::string(t.name) + "\"";
    {
      std::string info_txt = "";
      RimeSchemaInfo* info = (RimeSchemaInfo*)(t.reserved);
      RimeLeversApi* api = RIMELEVERSAPI;
      if (info && api) {
        if (const char* name = api->get_schema_name(info))
          info_txt += "  name = \"" + std::string(name) + "\"";
        if (const char* author = api->get_schema_author(info))
          info_txt += "\n  author = \"" + std::string(author) + "\"";
        if (const char* desc = api->get_schema_description(info))
          info_txt += "\n  description = \"" + std::string(desc) + "\"";
      }
      if (!info_txt.empty())
        repr += std::string(",\n  schema_info = {\n") + info_txt + std::string("\n}");
    }
    lua_pushstring(L, repr.c_str());
    return 1;
  }
  static int get_reserved(lua_State* L) {
    T* t = smart_shared_ptr_todata<T>(L, 1);
    auto sptr = std::shared_ptr<RimeSchemaInfo>((RimeSchemaInfo*)(t->reserved), [](RimeSchemaInfo* p){});
    LuaType<std::shared_ptr<RimeSchemaInfo>>::pushdata(L, sptr);
    return 1;
  }
  static const luaL_Reg funcs[] = {
    {"RimeSchemaListItem", raw_make_struct<T>},
    {nullptr, nullptr}
  };
  static const luaL_Reg methods[] = {
    {"__tostring", tostring},
    {nullptr, nullptr}
  };
  static const luaL_Reg vars_get[] = {
    {"schema_id", SMART_GET(T, schema_id)},
    {"name", SMART_GET(T, name)},
    {"schema_info", get_reserved},
    {"type", type<T>},
    {nullptr, nullptr}
  };
  static const luaL_Reg vars_set[] = { {nullptr, nullptr} };
}

namespace RimeSchemaListReg {
  using T = RimeSchemaList;

  // get a table of LuaType<RimeSchemaListItem>
  static int list(lua_State* L) {
    // return a table of RimeSchemaListItem
    // Accept either value userdata or shared_ptr userdata
    T* tp = smart_shared_ptr_todata<T>(L, 1);
    lua_newtable(L);
    if (tp && tp->list) {
      for (size_t i = 0; i < tp->size; ++i) {
        LuaType<RimeSchemaListItem>::pushdata(L, tp->list[i]);
        lua_rawseti(L, -2, (lua_Integer)(i + 1));  // 使用1-based索引给 Lua
      }
    }
    return 1;
  }

  static const luaL_Reg funcs[] = {
    {"RimeSchemaList", raw_make<T>},
    {nullptr, nullptr}
  };
  static const luaL_Reg methods[] = { {nullptr, nullptr} };
  static const luaL_Reg vars_get[] = {
    {"size", SMART_GET(T, size)},
    {"list", list},
    {"type", type<std::shared_ptr<T>>},
    {nullptr, nullptr}
  };
  static const luaL_Reg vars_set[] = { {nullptr, nullptr} };
}

namespace RimeStringSliceReg {
  using T = RimeStringSlice;
  static const luaL_Reg funcs[] = { {nullptr, nullptr} };
  static const luaL_Reg methods[] = { {nullptr, nullptr} };
  static int str(lua_State* L) {
    T t = LuaType<T>::todata(L, 1);
    auto str = std::string(t.str, t.length);
    lua_pushstring(L, str.c_str());
    return 1;
  }
  static const luaL_Reg vars_get[] = {
    {"str", str},
    {"length", SMART_GET(T, length)},
    {"type", type<T>},
    {nullptr, nullptr}
  };
  static const luaL_Reg vars_set[] = { {nullptr, nullptr} };
}

// Macro to declare function name variable
#define DECLARE_FUNC_NAME_VAR(name) \
  static constexpr const char name##_func_name[] = #name;
// Macro to create function pointer wrappers, with function name info
#define WRAP_API_FUNC(func) call_function_pointer<&T::func, func##_func_name>
// Macro to check function signature
#define SIGNATURE_CHECK(ret, ...) (std::is_same_v<FuncType, ret(*)(__VA_ARGS__)>)

namespace RimeCustomApiReg {
  using T = RimeCustomApi;
  static const luaL_Reg funcs[] = {
    {"RimeCustomApi", raw_make<T>},
    {nullptr, nullptr}
  };
  static const luaL_Reg methods[] = { {nullptr, nullptr} };
  static const luaL_Reg vars_get[] = {
    {"type", type<std::shared_ptr<T>>},
    {nullptr, nullptr} };
  static const luaL_Reg vars_set[] = { {nullptr, nullptr} };
}

namespace RimeModuleReg {
  using T = RimeModule;
  DECLARE_FUNC_NAME_VAR(initialize)
  DECLARE_FUNC_NAME_VAR(finalize)
  DECLARE_FUNC_NAME_VAR(get_api)
  static const luaL_Reg funcs[] = {
    {"RimeModule", raw_make<T>},
    {nullptr, nullptr}
  };
  // c function pointer caller
  template<auto member_ptr, const char* func_name = nullptr>
  static int call_function_pointer(lua_State* L) {
    T* api = smart_shared_ptr_todata<T>(L, 1);
    if (!api) {
      luaL_error(L, "RimeModule is not initialized");
      return 0;
    }
    auto func_ptr = api->*member_ptr;
    assert(func_name);
    using FuncType = decltype(func_ptr);
    if (!func_ptr) {
      luaL_error(L, "Function pointer for %s is null", func_name);
      return 0;
    }
    if constexpr SIGNATURE_CHECK(void) {
      func_ptr();
      lua_pushnil(L);
      return 1;
    } else if constexpr SIGNATURE_CHECK(RimeCustomApi*) {
      RimeCustomApi* result = func_ptr();
      if (!result)
        lua_pushnil(L);
      else {
        auto sptr = std::shared_ptr<RimeCustomApi>(result, [](RimeCustomApi* p){});
        LuaType<std::shared_ptr<RimeCustomApi>>::pushdata(L, sptr);
      }
      return 1;
    } else {
      luaL_error(L, "Unsupported function signature for %s", func_name);
      return 0;
    }
  }
  static const luaL_Reg methods[] = {
    // wrap function pointers as lightuserdata
    {"initialize", WRAP_API_FUNC(initialize)},
    {"finalize", WRAP_API_FUNC(finalize)},
    {"get_api", WRAP_API_FUNC(get_api)},
    {nullptr, nullptr}
  };
  static const luaL_Reg vars_get[] = {
    {"module_name", SMART_GET(T, module_name)},
    {"type", type<std::shared_ptr<T>>},
    {nullptr, nullptr}
  };
  static const luaL_Reg vars_set[] = {
    {"module_name", WRAPMEM_SET(T::module_name)},
    {nullptr, nullptr}
  };
}

namespace RimeTraitsReg {
  using T = RimeTraits;
  static int tostring(lua_State *L) {
    T* t = smart_shared_ptr_todata<T>(L);
    std::string repr = "{\n";
    if (t->app_name)
      repr += "  app_name=\"" + std::string(t->app_name) + "\", \n";
    if (t->distribution_name)
      repr += "  distribution_name=\"" + std::string(t->distribution_name) + "\", \n";
    if (t->distribution_code_name)
      repr += "  distribution_code_name=\"" + std::string(t->distribution_code_name) + "\", \n";
    if (t->distribution_version)
      repr += "  distribution_version=\"" + std::string(t->distribution_version) + "\", \n";
    if (t->shared_data_dir)
      repr += "  shared_data_dir=\"" + std::string(t->shared_data_dir) + "\", \n";
    if (t->user_data_dir)
      repr += "  user_data_dir=\"" + std::string(t->user_data_dir) + "\", \n";
    if (t->log_dir)
      repr += "  log_dir=\"" + std::string(t->log_dir) + "\", \n";
    if (t->prebuilt_data_dir)
      repr += "  prebuilt_data_dir=\"" + std::string(t->prebuilt_data_dir) + "\", \n";
    if (t->staging_dir)
      repr += "  staging_dir=\"" + std::string(t->staging_dir) + "\", \n";
    repr += "  min_log_level=" + std::to_string(t->min_log_level) + " \n}";

    lua_pushstring(L, repr.c_str());
    return 1;
  }

  static const luaL_Reg funcs[] = {
    {"RimeTraits", raw_make<T>},
    {nullptr, nullptr}
  };
  static const luaL_Reg methods[] = {
    {"__tostring", tostring},
    {nullptr, nullptr}
  };

  static const luaL_Reg vars_get[] = {
    {"shared_data_dir", SMART_GET(T, shared_data_dir)},
    {"user_data_dir", SMART_GET(T, user_data_dir)},
    {"distribution_name", SMART_GET(T, distribution_name)},
    {"distribution_code_name", SMART_GET(T, distribution_code_name)},
    {"distribution_version", SMART_GET(T, distribution_version)},
    {"app_name", SMART_GET(T, app_name)},
    //{"modules", SMART_GET(T, modules)},
    {"min_log_level", SMART_GET(T, min_log_level)},
    {"log_dir", SMART_GET(T, log_dir)},
    {"prebuilt_data_dir", SMART_GET(T, prebuilt_data_dir)},
    {"staging_dir", SMART_GET(T, staging_dir)},
    {"type", type<std::shared_ptr<T>>},
    {nullptr, nullptr}
  };
  static const luaL_Reg vars_set[] = {
    {"shared_data_dir", SMART_SET(T, shared_data_dir)},
    {"user_data_dir", SMART_SET(T, user_data_dir)},
    {"distribution_name", SMART_SET(T, distribution_name)},
    {"distribution_code_name", SMART_SET(T, distribution_code_name)},
    {"distribution_version", SMART_SET(T, distribution_version)},
    {"app_name", SMART_SET(T, app_name)},
    //{"modules", SMART_SET(T, modules)},
    {"min_log_level", SMART_SET(T, min_log_level)},
    {"log_dir", SMART_SET(T, log_dir)},
    {"prebuilt_data_dir", SMART_SET(T, prebuilt_data_dir)},
    {"staging_dir", SMART_SET(T, staging_dir)},
    {nullptr, nullptr}
  };
}

namespace RimeApiReg {
  using T = RimeApi;

  // 为所有RIME API函数声明名称变量
  // Basic API functions
  DECLARE_FUNC_NAME_VAR(setup)
  DECLARE_FUNC_NAME_VAR(set_notification_handler)
  DECLARE_FUNC_NAME_VAR(initialize)
  DECLARE_FUNC_NAME_VAR(finalize)
  DECLARE_FUNC_NAME_VAR(start_maintenance)
  DECLARE_FUNC_NAME_VAR(is_maintenance_mode)
  DECLARE_FUNC_NAME_VAR(join_maintenance_thread)

  // Deployment
  DECLARE_FUNC_NAME_VAR(deployer_initialize)
  DECLARE_FUNC_NAME_VAR(prebuild)
  DECLARE_FUNC_NAME_VAR(deploy)
  DECLARE_FUNC_NAME_VAR(deploy_schema)
  DECLARE_FUNC_NAME_VAR(deploy_config_file)
  DECLARE_FUNC_NAME_VAR(sync_user_data)

  // Session management
  DECLARE_FUNC_NAME_VAR(create_session)
  DECLARE_FUNC_NAME_VAR(find_session)
  DECLARE_FUNC_NAME_VAR(destroy_session)
  DECLARE_FUNC_NAME_VAR(cleanup_stale_sessions)
  DECLARE_FUNC_NAME_VAR(cleanup_all_sessions)

  // Input
  DECLARE_FUNC_NAME_VAR(process_key)
  DECLARE_FUNC_NAME_VAR(commit_composition)
  DECLARE_FUNC_NAME_VAR(clear_composition)

  // Output
  DECLARE_FUNC_NAME_VAR(get_commit)
  DECLARE_FUNC_NAME_VAR(free_commit)
  DECLARE_FUNC_NAME_VAR(get_context)
  DECLARE_FUNC_NAME_VAR(free_context)
  DECLARE_FUNC_NAME_VAR(get_status)
  DECLARE_FUNC_NAME_VAR(free_status)

  // Runtime options
  DECLARE_FUNC_NAME_VAR(set_option)
  DECLARE_FUNC_NAME_VAR(get_option)
  DECLARE_FUNC_NAME_VAR(set_property)
  DECLARE_FUNC_NAME_VAR(get_property)

  // Schema management
  DECLARE_FUNC_NAME_VAR(get_schema_list)
  DECLARE_FUNC_NAME_VAR(free_schema_list)
  DECLARE_FUNC_NAME_VAR(get_current_schema)
  DECLARE_FUNC_NAME_VAR(select_schema)

  // Configuration
  DECLARE_FUNC_NAME_VAR(schema_open)
  DECLARE_FUNC_NAME_VAR(config_open)
  DECLARE_FUNC_NAME_VAR(config_close)
  DECLARE_FUNC_NAME_VAR(config_get_bool)
  DECLARE_FUNC_NAME_VAR(config_get_int)
  DECLARE_FUNC_NAME_VAR(config_get_double)
  DECLARE_FUNC_NAME_VAR(config_get_string)
  DECLARE_FUNC_NAME_VAR(config_get_cstring)
  DECLARE_FUNC_NAME_VAR(config_update_signature)
  DECLARE_FUNC_NAME_VAR(config_begin_map)
  DECLARE_FUNC_NAME_VAR(config_next)
  DECLARE_FUNC_NAME_VAR(config_end)
  DECLARE_FUNC_NAME_VAR(config_init)
  DECLARE_FUNC_NAME_VAR(config_load_string)
  DECLARE_FUNC_NAME_VAR(config_set_bool)
  DECLARE_FUNC_NAME_VAR(config_set_int)
  DECLARE_FUNC_NAME_VAR(config_set_double)
  DECLARE_FUNC_NAME_VAR(config_set_string)
  DECLARE_FUNC_NAME_VAR(config_get_item)
  DECLARE_FUNC_NAME_VAR(config_set_item)
  DECLARE_FUNC_NAME_VAR(config_clear)
  DECLARE_FUNC_NAME_VAR(config_create_list)
  DECLARE_FUNC_NAME_VAR(config_create_map)
  DECLARE_FUNC_NAME_VAR(config_list_size)
  DECLARE_FUNC_NAME_VAR(config_begin_list)

  // Testing
  DECLARE_FUNC_NAME_VAR(simulate_key_sequence)

  // Module
  DECLARE_FUNC_NAME_VAR(register_module)
  DECLARE_FUNC_NAME_VAR(find_module)
  DECLARE_FUNC_NAME_VAR(run_task)

  // Directory functions
  DECLARE_FUNC_NAME_VAR(get_shared_data_dir)
  DECLARE_FUNC_NAME_VAR(get_user_data_dir)
  DECLARE_FUNC_NAME_VAR(get_sync_dir)
  DECLARE_FUNC_NAME_VAR(get_user_id)
  DECLARE_FUNC_NAME_VAR(get_user_data_sync_dir)
  DECLARE_FUNC_NAME_VAR(get_prebuilt_data_dir)
  DECLARE_FUNC_NAME_VAR(get_staging_dir)

  // User config
  DECLARE_FUNC_NAME_VAR(user_config_open)

  // Input/Output operations
  DECLARE_FUNC_NAME_VAR(get_input)
  DECLARE_FUNC_NAME_VAR(get_caret_pos)
  DECLARE_FUNC_NAME_VAR(set_caret_pos)
  DECLARE_FUNC_NAME_VAR(select_candidate)
  DECLARE_FUNC_NAME_VAR(select_candidate_on_current_page)
  DECLARE_FUNC_NAME_VAR(get_version)

  // Candidate operations
  DECLARE_FUNC_NAME_VAR(candidate_list_begin)
  DECLARE_FUNC_NAME_VAR(candidate_list_next)
  DECLARE_FUNC_NAME_VAR(candidate_list_end)
  DECLARE_FUNC_NAME_VAR(candidate_list_from_index)
  DECLARE_FUNC_NAME_VAR(delete_candidate)
  DECLARE_FUNC_NAME_VAR(delete_candidate_on_current_page)
  DECLARE_FUNC_NAME_VAR(highlight_candidate)
  DECLARE_FUNC_NAME_VAR(highlight_candidate_on_current_page)
  DECLARE_FUNC_NAME_VAR(change_page)

  // State and label functions
  DECLARE_FUNC_NAME_VAR(get_state_label)
  DECLARE_FUNC_NAME_VAR(get_state_label_abbreviated)
  DECLARE_FUNC_NAME_VAR(set_input)

  // Directory functions (with buffer)
  DECLARE_FUNC_NAME_VAR(get_shared_data_dir_s)
  DECLARE_FUNC_NAME_VAR(get_user_data_dir_s)
  DECLARE_FUNC_NAME_VAR(get_prebuilt_data_dir_s)
  DECLARE_FUNC_NAME_VAR(get_staging_dir_s)
  DECLARE_FUNC_NAME_VAR(get_sync_dir_s)

  // Thread-safe storage for notification callbacks keyed by context pointer.
  // Each entry stores the lua_State* where the Lua callback lives and the
  // registry reference for the function.
  static std::mutex g_notification_mutex;
  static std::unordered_map<void*, std::pair<lua_State*, int>> g_notification_map;
  // Key used to store per-state userdata in registry
  static const char notification_registry_key_sentinel = 'n';

  // Helper: called when a Lua state is being closed / its userdata GCed.
  // It will remove all entries in g_notification_map that reference this lua_State.
  static int notification_state_gc(lua_State *L) {
    // Find entries with this lua_State and unref them
    std::lock_guard<std::mutex> lk(g_notification_mutex);
    for (auto it = g_notification_map.begin(); it != g_notification_map.end(); ) {
      if (it->second.first == L) {
        // safe to unref because L is valid here
        luaL_unref(L, LUA_REGISTRYINDEX, it->second.second);
        it = g_notification_map.erase(it);
      } else {
        ++it;
      }
    }
    return 0;
  }

  static void store_notification_handler_internal(lua_State *L, void* context, int ref) {
    std::lock_guard<std::mutex> lk(g_notification_mutex);
    auto it = g_notification_map.find(context);
    if (it != g_notification_map.end()) {
      // unref previous
      luaL_unref(it->second.first, LUA_REGISTRYINDEX, it->second.second);
      it->second = {L, ref};
    } else {
      g_notification_map.emplace(context, std::make_pair(L, ref));
    }
  }

  static void remove_notification_handler_internal(void* context) {
    std::lock_guard<std::mutex> lk(g_notification_mutex);
    auto it = g_notification_map.find(context);
    if (it != g_notification_map.end()) {
      luaL_unref(it->second.first, LUA_REGISTRYINDEX, it->second.second);
      g_notification_map.erase(it);
    }
  }

  static void clear_all_notification_handlers_internal() {
    std::lock_guard<std::mutex> lk(g_notification_mutex);
    for (auto &kv : g_notification_map) {
      luaL_unref(kv.second.first, LUA_REGISTRYINDEX, kv.second.second);
    }
    g_notification_map.clear();
  }

  // C callback function that bridges to Lua. It looks up the lua_State and
  // registry ref for the given context object and invokes the stored Lua
  // callback. Note: calling Lua from arbitrary threads may be unsafe; this
  // preserves prior behavior but centralizes lifecycle management.
  static void notification_handler_bridge(void* context_object,
                                          RimeSessionId session_id,
                                          const char* message_type,
                                          const char* message_value) {
    std::pair<lua_State*, int> entry{nullptr, LUA_NOREF};
    {
      std::lock_guard<std::mutex> lk(g_notification_mutex);
      auto it = g_notification_map.find(context_object);
      if (it != g_notification_map.end()) entry = it->second;
    }
    if (entry.first && entry.second != LUA_NOREF) {
      lua_State *L = entry.first;
      // push the function
      lua_rawgeti(L, LUA_REGISTRYINDEX, entry.second);
      if (!lua_isfunction(L, -1)) {
        lua_pop(L, 1);
        return;
      }
      // push arguments
      lua_pushlightuserdata(L, context_object);
      lua_pushinteger(L, session_id);
      lua_pushstring(L, message_type);
      lua_pushstring(L, message_value);

      if (lua_pcall(L, 4, 0, 0) != LUA_OK) {
        const char* error = lua_tostring(L, -1);
        fprintf(stderr, "Error in notification handler: %s\n", error);
        lua_pop(L, 1); // pop error message
      }
    }
  }

  // Lua wrapper for set_notification_handler
  static int lua_set_notification_handler(lua_State *L) {
    T* api = smart_shared_ptr_todata<T>(L, 1);
    if (lua_isfunction(L, 2)) {
      // Ensure per-state userdata exists in registry to run GC when state closes
      lua_pushlightuserdata(L, (void*)&notification_registry_key_sentinel);
      lua_gettable(L, LUA_REGISTRYINDEX);
      if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        // create userdata
        void* u = lua_newuserdata(L, sizeof(void*));
        *(void**)u = nullptr;
        // create metatable with __gc
        if (luaL_newmetatable(L, "__notification_state_mt")) {
          lua_pushcfunction(L, notification_state_gc);
          lua_setfield(L, -2, "__gc");
        }
        lua_setmetatable(L, -2);
        // store in registry at key
        lua_pushlightuserdata(L, (void*)&notification_registry_key_sentinel);
        lua_pushvalue(L, -2);
        lua_settable(L, LUA_REGISTRYINDEX);
        lua_pop(L, 1); // pop the userdata we left on stack
      } else {
        lua_pop(L, 1);
      }

      // Store the Lua function in registry for this lua_State
      lua_pushvalue(L, 2); // copy function
      int ref = luaL_ref(L, LUA_REGISTRYINDEX);

      // Get context object (optional 3rd parameter)
      void* context = nullptr;
      if (lua_gettop(L) >= 3) {
        context = lua_touserdata(L, 3);
      }

      // register internally
      store_notification_handler_internal(L, context, ref);

      // Set the notification handler in Rime API (context is passed through)
      api->set_notification_handler(notification_handler_bridge, context);
    } else if (lua_isnil(L, 2)) {
      void* context = nullptr;
      if (lua_gettop(L) >= 3) {
        context = lua_touserdata(L, 3);
      }
      // Disable notification handler in Rime API for this context
      api->set_notification_handler(nullptr, nullptr);
      // remove stored callback (unref)
      remove_notification_handler_internal(context);
    } else {
      luaL_error(L, "Expected function or nil for notification handler");
    }
    return 0;
  }

  // Lua-visible cleanup function to clear all stored handlers
  static int lua_clear_notification_handlers(lua_State *L) {
    (void)L;
    clear_all_notification_handlers_internal();
    return 0;
  }

  // Generic template for calling function pointers in RimeApi struct
  template<auto member_ptr, const char* func_name = nullptr>
  static int call_function_pointer(lua_State *L) {
    T* api = smart_shared_ptr_todata<T>(L);
    if (!api) {
      luaL_error(L, "RimeApi is not initialized");
      return 0;
    }
    auto func_ptr = api->*member_ptr;
    assert(func_name);
    // Deduce function signature from member pointer type
    using FuncType = decltype(func_ptr);
    // 1st is the return type, rest are argument types
    if constexpr SIGNATURE_CHECK(void) {
      func_ptr();
      return 0;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeModule*) {
      RimeModule* m = smart_shared_ptr_todata<RimeModule>(L, 2);
      Bool result = func_ptr(m);
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(RimeModule*, const char*) {
      // find_module
      const char* module_name = luaL_checkstring(L, 2);
      RimeModule* module = func_ptr(module_name);
      if (module) {
        auto sptr = std::shared_ptr<RimeModule>(module, [](RimeModule*){});
        LuaType<std::shared_ptr<RimeModule>>::pushdata(L, sptr);
      } else {
        lua_pushnil(L);
      }
      return 1;
    } else if constexpr SIGNATURE_CHECK(void, RimeTraits*) {
      RimeTraits* traits = smart_shared_ptr_todata<RimeTraits>(L, 2);
      func_ptr(traits);
      return 0;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeSessionId) {
      RimeSessionId session_id = RimeSession_todata(L, 2);
      Bool result = func_ptr(session_id);
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(RimeSessionId) {
      RimeSessionId result = func_ptr();
      RimeSession_pushdata(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeSessionId, const char*) {
      RimeSessionId session_id = RimeSession_todata(L, 2);
      const char* schema_id = luaL_checkstring(L, 3);
      Bool result = func_ptr(session_id, schema_id);
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, Bool) {
      Bool arg = lua_toboolean(L, 2);
      Bool result = func_ptr(arg);
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeSessionId, RimeCommit*) {
      RimeSessionId session_id = RimeSession_todata(L, 2);
      RimeCommit* commit = smart_shared_ptr_todata<RimeCommit>(L, 3);
      Bool result = func_ptr(session_id, commit);
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeSessionId, RimeStatus*) {
      RimeSessionId session_id = RimeSession_todata(L, 2);
      RimeStatus* status = smart_shared_ptr_todata<RimeStatus>(L, 3);
      if (status) RIMEAPI->free_status(status); // ensure no leak
      Bool result = func_ptr(session_id, status);
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, const char*, RimeConfig*) {
      // schema_open / config_open / user_config_open
      const char* config_name = luaL_checkstring(L, 2);
      RimeConfig* config = smart_shared_ptr_todata<RimeConfig>(L, 3);
      Bool result = false;
      if (config) {
        bool was_borrowed = is_config_borrowed(config);
        if (!was_borrowed)
          api->config_close(config);
        result = func_ptr(config_name, config);
        set_config_borrowed(config, was_borrowed && !result);
      } else {
        result = func_ptr(config_name, config);
      }
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeConfig*, const char*, int*) {
      // config_get_int or config_get_bool
      RimeConfig* config = smart_shared_ptr_todata<RimeConfig>(L, 2);
      const char* key = luaL_checkstring(L, 3);
      int value = 0;
      Bool result = func_ptr(config, key, &value);
      if (!result)
        lua_pushnil(L);
      else if (strcmp(func_name, "config_get_int") == 0)
        lua_pushinteger(L, value);
      else
        lua_pushboolean(L, !!value);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeConfig*, const char*, double*) {
      // config_get_double
      RimeConfig* config = smart_shared_ptr_todata<RimeConfig>(L, 2);
      const char* key = luaL_checkstring(L, 3);
      std::unique_ptr<double> value = std::make_unique<double>();
      Bool result = func_ptr(config, key, value.get());
      PUSH_VALUE_OR_NIL(L, *value, result, lua_pushnumber);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeConfig*, const char*, char*, size_t) {
      // config_get_string
      if (lua_gettop(L) < 3) {
        // 1st param is function pointer
        luaL_error(L,
            "Expected 3 arguments for \"%s\", (%s, string, integer) is required",
            func_name, LuaType<std::shared_ptr<RimeConfig>>::type()->name());
        return 0;
      }
      RimeConfig* config = smart_shared_ptr_todata<RimeConfig>(L, 2);
      const char* key = luaL_checkstring(L, 3);
      size_t buffer_size = 256;
      if (lua_gettop(L) == 4) buffer_size = luaL_checkinteger(L, 4);
      std::unique_ptr<char[]> buffer = std::make_unique<char[]>(buffer_size);
      Bool result = func_ptr(config, key, buffer.get(), buffer_size);
      PUSH_VALUE_OR_NIL(L, buffer.get(), result, lua_pushstring);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeCommit*) {
      RimeCommit* commit = smart_shared_ptr_todata<RimeCommit>(L, 2);
      if (commit) RIMEAPI->free_commit(commit); // ensure no leak
      Bool result = func_ptr(commit);
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeSessionId, RimeContext*) {
      RimeSessionId session_id = RimeSession_todata(L, 2);
      RimeContext* context = smart_shared_ptr_todata<RimeContext>(L, 3);
      if (context) RIMEAPI->free_context(context); // ensure no leak
      Bool result = func_ptr(session_id, context);
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeConfig*) {
      RimeConfig* config = smart_shared_ptr_todata<RimeConfig>(L, 2);
      Bool ret = false;
      if (strcmp(func_name, "config_close") == 0) {
        if (config) {
          if (!is_config_borrowed(config)) {
            ret = func_ptr(config);
            cfg_borrowed_set.erase(config);
          }
        }
      } else {
        ret = func_ptr(config);
      }
      lua_pushboolean(L, ret);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool) {
      // Bool returning no-arg functions (e.g. is_maintenance_mode, prebuild, deploy)
      Bool result = func_ptr();
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(const char*) {
      // functions returning const char* with no args (e.g. get_version, get_user_id)
      const char* s = func_ptr();
      PUSH_VALUE_OR_NIL(L, s, s != nullptr, lua_pushstring);
      return 1;
    } else if constexpr SIGNATURE_CHECK(const char*, RimeConfig*, const char*) {
      // config_get_cstring
      RimeConfig* config = smart_shared_ptr_todata<RimeConfig>(L, 2);
      const char* key = luaL_checkstring(L, 3);
      const char* value = func_ptr(config, key);
      PUSH_VALUE_OR_NIL(L, value, value != nullptr, lua_pushstring);
      return 1;
    } else if constexpr SIGNATURE_CHECK(const char*, RimeSessionId) {
      // get_input
      RimeSessionId session_id = RimeSession_todata(L, 2);
      const char* s = func_ptr(session_id);
      PUSH_VALUE_OR_NIL(L, s, s != nullptr, lua_pushstring);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, const char*) {
      // run_task(const char*) -> Bool
      const char* task_name = luaL_checkstring(L, 2);
      Bool result = func_ptr(task_name);
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, const char*, const char*) {
      // deploy_config_file(file_name, version_key)
      const char* file_name = luaL_checkstring(L, 2);
      const char* version_key = luaL_checkstring(L, 3);
      Bool result = func_ptr(file_name, version_key);
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(void, RimeSessionId) {
      // clear_composition(session_id)
      RimeSessionId session_id = RimeSession_todata(L, 2);
      func_ptr(session_id);
      return 0;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeContext*) {
      // free_context(RimeContext*)
      RimeContext* ctx = smart_shared_ptr_todata<RimeContext>(L, 2);
      Bool result = func_ptr(ctx);
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeStatus*) {
      // free_status(RimeStatus*)
      RimeStatus* st = smart_shared_ptr_todata<RimeStatus>(L, 2);
      Bool result = func_ptr(st);
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(void, RimeSessionId, const char*, Bool) {
      // set_option(session_id, option, Bool)
      RimeSessionId session_id = RimeSession_todata(L, 2);
      const char* option = luaL_checkstring(L, 3);
      Bool val = lua_toboolean(L, 4);
      func_ptr(session_id, option, val);
      return 0;
    } else if constexpr SIGNATURE_CHECK(void, RimeSessionId, const char*, const char*) {
      // set_property(session_id, prop, value)
      RimeSessionId session_id = RimeSession_todata(L, 2);
      const char* prop = luaL_checkstring(L, 3);
      const char* value = luaL_checkstring(L, 4);
      func_ptr(session_id, prop, value);
      return 0;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeSchemaList*) {
      // get_schema_list
      RimeSchemaList* list = smart_shared_ptr_todata<RimeSchemaList>(L, 2);
      if (list) RIMEAPI->free_schema_list(list); // ensure no leak
      Bool result = list ? func_ptr(list) : false;
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(void, RimeSchemaList*) {
      // free_schema_list
      RimeSchemaList* list = smart_shared_ptr_todata<RimeSchemaList>(L, 2);
      if (list) func_ptr(list);
      return 0;
  } else if constexpr SIGNATURE_CHECK(Bool, RimeSessionId, char*, size_t) {
      // get_current_schema(session_id, buffer, buffer_size)
      if (lua_gettop(L) < 2) {
        luaL_error(L, "Expected 2 arguments for \"%s\", (%s, %s) is required\
            \nor (%s) with default buffer size 256"
            , func_name, "RimeSessionId", "buffer_size(integer)", "RimeSessionId");
        return 0;
      }
      RimeSessionId session_id = RimeSession_todata(L, 2);
      size_t buffer_size = 256;
      if (lua_gettop(L) >= 3)
        buffer_size = luaL_checkinteger(L, 3);
      std::unique_ptr<char[]> buffer = std::make_unique<char[]>(buffer_size);
      Bool result = func_ptr(session_id, buffer.get(), buffer_size);
      if (result) {
        lua_pushstring(L, buffer.get());
      } else {
        lua_pushboolean(L, false);
      }
      return 1;
    } else if constexpr SIGNATURE_CHECK(size_t, RimeSessionId) {
      // get_caret_pos(session_id)
      RimeSessionId session_id = RimeSession_todata(L, 2);
      size_t pos = func_ptr(session_id);
      lua_pushinteger(L, (lua_Integer)pos);
      return 1;
    } else if constexpr SIGNATURE_CHECK(void, RimeSessionId, size_t) {
      // set_caret_pos(session_id, caret_pos)
      RimeSessionId session_id = RimeSession_todata(L, 2);
      size_t caret = (size_t)luaL_checkinteger(L, 3);
      func_ptr(session_id, caret);
      return 0;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeSessionId, RimeCandidateListIterator*) {
      // candidate_list_begin(session_id, iterator)
      RimeSessionId session_id = RimeSession_todata(L, 2);
      RimeCandidateListIterator* it = smart_shared_ptr_todata<RimeCandidateListIterator>(L, 3);
      Bool result = func_ptr(session_id, it);
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeCandidateListIterator*) {
      // candidate_list_next(iterator)
      RimeCandidateListIterator* it = smart_shared_ptr_todata<RimeCandidateListIterator>(L, 2);
      Bool result = func_ptr(it);
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(void, RimeCandidateListIterator*) {
      // candidate_list_end(iterator)
      RimeCandidateListIterator* it = smart_shared_ptr_todata<RimeCandidateListIterator>(L, 2);
      func_ptr(it);
      return 0;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeSessionId, RimeCandidateListIterator*, int) {
      // candidate_list_from_index(session_id, iterator, index)
      RimeSessionId session_id = RimeSession_todata(L, 2);
      RimeCandidateListIterator* it = smart_shared_ptr_todata<RimeCandidateListIterator>(L, 3);
      int index = luaL_checkinteger(L, 4);
      Bool result = func_ptr(session_id, it, index);
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeConfig*, const char*) {
      // config_update_signature / config_load_string / config_clear / create_list / create_map
      RimeConfig* config = smart_shared_ptr_todata<RimeConfig>(L, 2);
      const char* arg = luaL_checkstring(L, 3);
      Bool result = func_ptr(config, arg);
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeConfigIterator*, RimeConfig*, const char*) {
      // config_begin_map(iterator, config, key)
      RimeConfigIterator* it = smart_shared_ptr_todata<RimeConfigIterator>(L, 2);
      RimeConfig* config = smart_shared_ptr_todata<RimeConfig>(L, 3);
      const char* key = luaL_checkstring(L, 4);
      Bool result = func_ptr(it, config, key);
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeConfigIterator*) {
      // config_next(iterator)
      RimeConfigIterator* it = smart_shared_ptr_todata<RimeConfigIterator>(L, 2);
      Bool result = func_ptr(it);
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(void, RimeConfigIterator*) {
      // config_end(iterator)
      RimeConfigIterator* it = smart_shared_ptr_todata<RimeConfigIterator>(L, 2);
      func_ptr(it);
      return 0;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeConfig*, const char*, int) {
      // config_set_int
      RimeConfig* config = smart_shared_ptr_todata<RimeConfig>(L, 2);
      const char* key = luaL_checkstring(L, 3);
      auto v = (strcmp(func_name, "config_set_int") == 0) ?
        luaL_checkinteger(L, 4) : lua_toboolean(L, 4);
      Bool result = func_ptr(config, key, v);
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeConfig*, const char*, double) {
      // config_set_double
      RimeConfig* config = smart_shared_ptr_todata<RimeConfig>(L, 2);
      const char* key = luaL_checkstring(L, 3);
      double v = luaL_checknumber(L, 4);
      Bool result = func_ptr(config, key, v);
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeConfig*, const char*, const char*) {
      // config_set_string
      RimeConfig* config = smart_shared_ptr_todata<RimeConfig>(L, 2);
      const char* key = luaL_checkstring(L, 3);
      const char* v = luaL_checkstring(L, 4);
      Bool result = func_ptr(config, key, v);
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeConfig*, const char*, RimeConfig*) {
      // config_get_item / config_set_item (depending on func_name)
      RimeConfig* config = smart_shared_ptr_todata<RimeConfig>(L, 2);
      const char* key = luaL_checkstring(L, 3);
      RimeConfig* value = smart_shared_ptr_todata<RimeConfig>(L, 4);
      Bool result = func_ptr(config, key, value);
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(size_t, RimeConfig*, const char*) {
      // config_list_size and similar
      RimeConfig* config = smart_shared_ptr_todata<RimeConfig>(L, 2);
      const char* key = luaL_checkstring(L, 3);
      size_t val = func_ptr(config, key);
      lua_pushinteger(L, (lua_Integer)val);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeSessionId, size_t) {
      // candidate selection using size_t
      RimeSessionId session_id = RimeSession_todata(L, 2);
      size_t index = (size_t)luaL_checkinteger(L, 3);
      Bool result = func_ptr(session_id, index);
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeSessionId, int, int) {
      // process_key(session_id, keycode, mask)
      RimeSessionId session_id = RimeSession_todata(L, 2);
      int keycode = luaL_checkinteger(L, 3);
      int mask = luaL_checkinteger(L, 4);
      Bool result = func_ptr(session_id, keycode, mask);
      lua_pushboolean(L, result);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeSessionId, const char*, char*, size_t) {
      // get_property(session_id, prop, buffer, buffer_size)
      if (lua_gettop(L) != 4) {
        luaL_error(L, "Expected 3 arguments for \"%s\", (%s, %s, %s) is required", func_name, "RimeSessionId", "string", "buffer_size(integer)");
        return 0;
      }
      RimeSessionId session_id = RimeSession_todata(L, 2);
      const char* prop = luaL_checkstring(L, 3);
      size_t buffer_size = luaL_checkinteger(L, 4);
      std::unique_ptr<char[]> buffer = std::make_unique<char[]>(buffer_size);
      Bool result = func_ptr(session_id, prop, buffer.get(), buffer_size);
      if (result) {
        lua_pushboolean(L, true);
        lua_pushstring(L, buffer.get());
        return 2;
      } else {
        lua_pushboolean(L, false);
        return 1;
      }
    } else if constexpr SIGNATURE_CHECK(void, char*, size_t) {
      // functions that fill a char* buffer (get_*_dir_s etc.)
      if (lua_gettop(L) != 2) {
        luaL_error(L, "Expected 1 argument for \"%s\", (%s) is required", func_name, "buffer_size(integer)");
        return 0;
      }
      size_t buffer_size = luaL_checkinteger(L, 2);
      std::unique_ptr<char[]> buffer = std::make_unique<char[]>(buffer_size);
      func_ptr(buffer.get(), buffer_size);
      lua_pushstring(L, buffer.get());
      return 1;
    } else if constexpr SIGNATURE_CHECK(const char*, RimeSessionId, const char*, Bool) {
      // const char* get_state_label(RimeSessionId, const char*, Bool)
      RimeSessionId session_id = RimeSession_todata(L, 2);
      const char* option_name = luaL_checkstring(L, 3);
      Bool state = lua_toboolean(L, 4);
      const char* s = func_ptr(session_id, option_name, state);
      PUSH_VALUE_OR_NIL(L, s, s != nullptr, lua_pushstring);
      return 1;
    } else if constexpr SIGNATURE_CHECK(RimeStringSlice, RimeSessionId, const char*, Bool, Bool) {
      // RimeStringSlice get_state_label_abbreviated(RimeSessionId, const char*, Bool, Bool)
      RimeSessionId session_id = RimeSession_todata(L, 2);
      const char* option_name = luaL_checkstring(L, 3);
      Bool state = lua_toboolean(L, 4);
      Bool abbreviated = lua_toboolean(L, 5);
      RimeStringSlice slice = func_ptr(session_id, option_name, state, abbreviated);
      LuaType<RimeStringSlice>::pushdata(L, slice);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeSessionId, Bool) {
      // change_page(session_id, Bool)
      RimeSessionId session_id = RimeSession_todata(L, 2);
      Bool val = lua_tointeger(L, 3);
      Bool result = func_ptr(session_id, (Bool)val);
      lua_pushboolean(L, result);
      return 1;
    } else {
      luaL_error(L, "Unsupported function signature for function: %s", func_name);
      return 0;
    }
  }

  static int raw_make(lua_State *L) {
    auto api_ptr = std::shared_ptr<T>(RIMEAPI,
        [](T* t){
        clear_all_notification_handlers_internal();
        t->cleanup_all_sessions();
        t->finalize();
        });
    LuaType<std::shared_ptr<T>>::pushdata(L, api_ptr);
    return 1;
  }
  static int tostring(lua_State *L) {
    T* api = smart_shared_ptr_todata<T>(L);
    std::string demangled_name = LuaType<std::shared_ptr<T>>::type()->name();
    lua_pushfstring(L, "LuaType<std::shared_ptr<rime_api_t> >: %p", api);
    return 1;
  }
  static const luaL_Reg funcs[] = {
    {"RimeApi", raw_make},
    {nullptr, nullptr}
  };
  static const luaL_Reg methods[] = {
    // Basic API functions
    {"setup", WRAP_API_FUNC(setup)},
    {"initialize", WRAP_API_FUNC(initialize)},
    {"finalize", WRAP_API_FUNC(finalize)},
    {"set_notification_handler", lua_set_notification_handler},

    // Maintenance
    {"start_maintenance", WRAP_API_FUNC(start_maintenance)},
    {"is_maintenance_mode", WRAP_API_FUNC(is_maintenance_mode)},
    {"join_maintenance_thread", WRAP_API_FUNC(join_maintenance_thread)},

    // Deployment
    {"deployer_initialize", WRAP_API_FUNC(deployer_initialize)},
    {"prebuild", WRAP_API_FUNC(prebuild)},
    {"deploy", WRAP_API_FUNC(deploy)},
    {"deploy_schema", WRAP_API_FUNC(deploy_schema)},
    {"deploy_config_file", WRAP_API_FUNC(deploy_config_file)},
    {"sync_user_data", WRAP_API_FUNC(sync_user_data)},

    // Session management
    {"create_session", WRAP_API_FUNC(create_session)},
    {"find_session", WRAP_API_FUNC(find_session)},
    {"destroy_session", WRAP_API_FUNC(destroy_session)},
    {"cleanup_stale_sessions", WRAP_API_FUNC(cleanup_stale_sessions)},
    {"cleanup_all_sessions", WRAP_API_FUNC(cleanup_all_sessions)},

    // Input
    {"process_key", WRAP_API_FUNC(process_key)},
    {"commit_composition", WRAP_API_FUNC(commit_composition)},
    {"clear_composition", WRAP_API_FUNC(clear_composition)},

    // Output
    {"get_commit", WRAP_API_FUNC(get_commit)},
    {"free_commit", WRAP_API_FUNC(free_commit)},
    {"get_context", WRAP_API_FUNC(get_context)},
    {"free_context", WRAP_API_FUNC(free_context)},
    {"get_status", WRAP_API_FUNC(get_status)},
    {"free_status", WRAP_API_FUNC(free_status)},

    // Runtime options
    {"set_option", WRAP_API_FUNC(set_option)},
    {"get_option", WRAP_API_FUNC(get_option)},
    {"set_property", WRAP_API_FUNC(set_property)},
    {"get_property", WRAP_API_FUNC(get_property)},

    // Schema management
    {"get_schema_list", WRAP_API_FUNC(get_schema_list)},
    {"free_schema_list", WRAP_API_FUNC(free_schema_list)},
    {"get_current_schema", WRAP_API_FUNC(get_current_schema)},
    {"select_schema", WRAP_API_FUNC(select_schema)},

    // Configuration
    {"schema_open", WRAP_API_FUNC(schema_open)},
    {"config_open", WRAP_API_FUNC(config_open)},
    {"config_close", WRAP_API_FUNC(config_close)},
    {"config_get_bool", WRAP_API_FUNC(config_get_bool)},
    {"config_get_int", WRAP_API_FUNC(config_get_int)},
    {"config_get_double", WRAP_API_FUNC(config_get_double)},
    {"config_get_string", WRAP_API_FUNC(config_get_string)},
    {"config_get_cstring", WRAP_API_FUNC(config_get_cstring)},
    {"config_update_signature", WRAP_API_FUNC(config_update_signature)},
    {"config_begin_map", WRAP_API_FUNC(config_begin_map)},
    {"config_next", WRAP_API_FUNC(config_next)},
    {"config_end", WRAP_API_FUNC(config_end)},
    {"config_init", WRAP_API_FUNC(config_init)},
    {"config_load_string", WRAP_API_FUNC(config_load_string)},
    {"config_set_bool", WRAP_API_FUNC(config_set_bool)},
    {"config_set_int", WRAP_API_FUNC(config_set_int)},
    {"config_set_double", WRAP_API_FUNC(config_set_double)},
    {"config_set_string", WRAP_API_FUNC(config_set_string)},
    {"config_get_item", WRAP_API_FUNC(config_get_item)},
    {"config_set_item", WRAP_API_FUNC(config_set_item)},
    {"config_clear", WRAP_API_FUNC(config_clear)},
    {"config_create_list", WRAP_API_FUNC(config_create_list)},
    {"config_create_map", WRAP_API_FUNC(config_create_map)},
    {"config_list_size", WRAP_API_FUNC(config_list_size)},
    {"config_begin_list", WRAP_API_FUNC(config_begin_list)},

    // Input/Output operations
    {"get_input", WRAP_API_FUNC(get_input)},
    {"get_caret_pos", WRAP_API_FUNC(get_caret_pos)},
    {"set_caret_pos", WRAP_API_FUNC(set_caret_pos)},
    {"set_input", WRAP_API_FUNC(set_input)},

    // Candidate operations
    {"select_candidate", WRAP_API_FUNC(select_candidate)},
    {"select_candidate_on_current_page", WRAP_API_FUNC(select_candidate_on_current_page)},
    {"candidate_list_begin", WRAP_API_FUNC(candidate_list_begin)},
    {"candidate_list_next", WRAP_API_FUNC(candidate_list_next)},
    {"candidate_list_end", WRAP_API_FUNC(candidate_list_end)},
    {"candidate_list_from_index", WRAP_API_FUNC(candidate_list_from_index)},
    {"delete_candidate", WRAP_API_FUNC(delete_candidate)},
    {"delete_candidate_on_current_page", WRAP_API_FUNC(delete_candidate_on_current_page)},
    {"highlight_candidate", WRAP_API_FUNC(highlight_candidate)},
    {"highlight_candidate_on_current_page", WRAP_API_FUNC(highlight_candidate_on_current_page)},
    {"change_page", WRAP_API_FUNC(change_page)},

    // Testing
    {"simulate_key_sequence", WRAP_API_FUNC(simulate_key_sequence)},

    // Module management
    {"register_module", WRAP_API_FUNC(register_module)},
    {"find_module", WRAP_API_FUNC(find_module)},
    {"run_task", WRAP_API_FUNC(run_task)},

    // Directory paths (deprecated versions)
    {"get_shared_data_dir", WRAP_API_FUNC(get_shared_data_dir)},
    {"get_user_data_dir", WRAP_API_FUNC(get_user_data_dir)},
    {"get_sync_dir", WRAP_API_FUNC(get_sync_dir)},
    {"get_prebuilt_data_dir", WRAP_API_FUNC(get_prebuilt_data_dir)},
    {"get_staging_dir", WRAP_API_FUNC(get_staging_dir)},

    // Directory paths (new versions)
    {"get_shared_data_dir_s", WRAP_API_FUNC(get_shared_data_dir_s)},
    {"get_user_data_dir_s", WRAP_API_FUNC(get_user_data_dir_s)},
    {"get_prebuilt_data_dir_s", WRAP_API_FUNC(get_prebuilt_data_dir_s)},
    {"get_staging_dir_s", WRAP_API_FUNC(get_staging_dir_s)},
    {"get_sync_dir_s", WRAP_API_FUNC(get_sync_dir_s)},
    {"get_user_id", WRAP_API_FUNC(get_user_id)},
    {"get_user_data_sync_dir", WRAP_API_FUNC(get_user_data_sync_dir)},

    // User configuration
    {"user_config_open", WRAP_API_FUNC(user_config_open)},

    // Proto API (deprecated)

    // State and version
    {"get_state_label", WRAP_API_FUNC(get_state_label)},
    {"get_state_label_abbreviated", WRAP_API_FUNC(get_state_label_abbreviated)},
    {"get_version", WRAP_API_FUNC(get_version)},
    {"__tostring", tostring},

    {nullptr, nullptr}
  };
  static const luaL_Reg vars_get[] = {
    {"type", type<std::shared_ptr<T>>},
    {nullptr, nullptr} };
  static const luaL_Reg vars_set[] = { {nullptr, nullptr} };
}

namespace RimeCustomSettingsReg {
  using T = RimeCustomSettings;
  static const luaL_Reg funcs[] = {
    {"RimeCustomSettings", raw_make<T>},
    {nullptr, nullptr}
  };
  static const luaL_Reg methods[] = { {nullptr, nullptr} };
  static const luaL_Reg vars_get[] = {
    {"type", type<std::shared_ptr<T>>},
    {nullptr, nullptr} };
  static const luaL_Reg vars_set[] = { {nullptr, nullptr} };
}

namespace RimeSwitcherSettingsReg {
  using T = RimeSwitcherSettings;
  static const luaL_Reg funcs[] = {
    {"RimeSwitcherSettings", raw_make<T>},
    {nullptr, nullptr}
  };
  static const luaL_Reg methods[] = { {nullptr, nullptr} };
  static const luaL_Reg vars_get[] = {
    {"type", type<std::shared_ptr<T>>},
    {nullptr, nullptr} };
  static const luaL_Reg vars_set[] = { {nullptr, nullptr} };
}

namespace RimeSchemaInfoReg {
  using T = RimeSchemaInfo;
#define DEFINE_GETTER(prop) \
  static int get_##prop(lua_State* L) { \
    T* si = smart_shared_ptr_todata<T>(L); \
    if (!si) lua_pushnil(L); \
    else { \
      RimeLeversApi* api = RIMELEVERSAPI; \
      if (api) { \
        const char* s = api->get_schema_##prop(si); \
        if (s) lua_pushstring(L, s); else lua_pushnil(L); \
      } else lua_pushnil(L); \
    } \
    return 1; \
  }
  DEFINE_GETTER(name)
  DEFINE_GETTER(author)
  DEFINE_GETTER(description)
  DEFINE_GETTER(id)
  DEFINE_GETTER(version)
  DEFINE_GETTER(file_path)
  static const luaL_Reg funcs[] = { {nullptr, nullptr} };
  static const luaL_Reg methods[] = {
    {"get_schema_id", get_id},
    {"get_schema_name", get_name},
    {"get_schema_version", get_version},
    {"get_schema_author", get_author},
    {"get_schema_description", get_description},
    {"get_schema_file_path", get_file_path},
    {nullptr, nullptr}
  };
  static const luaL_Reg vars_get[] = {
    {"name", get_name},
    {"author", get_author},
    {"description", get_description},
    {"schema_id", get_id},
    {"version", get_version},
    {"file_path", get_file_path},
    {"type", type<std::shared_ptr<T>>},
    {nullptr, nullptr}
  };
  static const luaL_Reg vars_set[] = { {nullptr, nullptr} };
#undef DEFINE_GETTER
}

namespace RimeUserDictIteratorReg {
  using T = RimeUserDictIterator;
  static const luaL_Reg funcs[] = {
    {"RimeUserDictIterator", raw_make<T>},
    {nullptr, nullptr}
  };
  static const luaL_Reg methods[] = { {nullptr, nullptr} };
  static const luaL_Reg vars_get[] = {
    {"type", type<std::shared_ptr<T>>},
    {nullptr, nullptr} };
  static const luaL_Reg vars_set[] = { {nullptr, nullptr} };
}

namespace RimeLeversApiReg {
  using T = RimeLeversApi;
  DECLARE_FUNC_NAME_VAR(custom_settings_init)
  DECLARE_FUNC_NAME_VAR(custom_settings_destroy)
  DECLARE_FUNC_NAME_VAR(load_settings)
  DECLARE_FUNC_NAME_VAR(save_settings)
  DECLARE_FUNC_NAME_VAR(customize_bool)
  DECLARE_FUNC_NAME_VAR(customize_int)
  DECLARE_FUNC_NAME_VAR(customize_string)
  DECLARE_FUNC_NAME_VAR(customize_double)
  DECLARE_FUNC_NAME_VAR(is_first_run)
  DECLARE_FUNC_NAME_VAR(settings_is_modified)
  DECLARE_FUNC_NAME_VAR(settings_get_config)
  DECLARE_FUNC_NAME_VAR(switcher_settings_init)
  DECLARE_FUNC_NAME_VAR(get_available_schema_list)
  DECLARE_FUNC_NAME_VAR(get_selected_schema_list)
  DECLARE_FUNC_NAME_VAR(schema_list_destroy)
  DECLARE_FUNC_NAME_VAR(get_schema_id)
  DECLARE_FUNC_NAME_VAR(get_schema_name)
  DECLARE_FUNC_NAME_VAR(get_schema_version)
  DECLARE_FUNC_NAME_VAR(get_schema_author)
  DECLARE_FUNC_NAME_VAR(get_schema_description)
  DECLARE_FUNC_NAME_VAR(get_schema_file_path)
  DECLARE_FUNC_NAME_VAR(select_schemas)
  DECLARE_FUNC_NAME_VAR(get_hotkeys)
  DECLARE_FUNC_NAME_VAR(set_hotkeys)
  DECLARE_FUNC_NAME_VAR(user_dict_iterator_init)
  DECLARE_FUNC_NAME_VAR(user_dict_iterator_destroy)
  DECLARE_FUNC_NAME_VAR(next_user_dict)
  DECLARE_FUNC_NAME_VAR(backup_user_dict)
  DECLARE_FUNC_NAME_VAR(restore_user_dict)
  DECLARE_FUNC_NAME_VAR(export_user_dict)
  DECLARE_FUNC_NAME_VAR(import_user_dict)
  DECLARE_FUNC_NAME_VAR(customize_item)

  // Helper available to multiple call sites: try to obtain a RimeCustomSettings*
  static RimeCustomSettings* lua_to_custom_settings(lua_State* L, int idx) {
#define TRY_RETURN(type) do{type *t = smart_shared_ptr_todata<type>(L, idx); \
  if (t) return reinterpret_cast<RimeCustomSettings*>(t);} while(0)
    TRY_RETURN(RimeCustomSettings);
    TRY_RETURN(RimeSwitcherSettings);
    TRY_RETURN(RimeSchemaInfo);
    if (lua_islightuserdata(L, idx))
      return static_cast<RimeCustomSettings*>(lua_touserdata(L, idx));
    return nullptr;
  }
  static inline void mark_levers_settings_destroyed(void* ptr) {
    if (!ptr) return;
    std::lock_guard<std::mutex> lk(levers_settings_mutex);
    levers_settings_owned.erase(ptr);
  }
  // Generic helper: wrap a levers-owned raw pointer into a shared_ptr with
  // a deleter that calls destroy_levers_settings, then push to Lua.
  template<typename U>
  static void push_from_raw(lua_State* L, U* ptr) {
    if (!ptr) { lua_pushnil(L); return; }
    std::lock_guard<std::mutex> lk(levers_settings_mutex);
    levers_settings_owned.insert(ptr);
    const auto destroy_levers_settings = [](void* ptr) {
      if (!ptr) return;
      bool should_destroy = false;
      std::lock_guard<std::mutex> lk(levers_settings_mutex);
      auto it = levers_settings_owned.find(ptr);
      if (it != levers_settings_owned.end()) {
        levers_settings_owned.erase(it);
        should_destroy = true;
      }
      if (should_destroy)
        if (auto api = RIMELEVERSAPI) api->custom_settings_destroy(reinterpret_cast<RimeCustomSettings*>(ptr));
    };
    auto sptr = std::shared_ptr<U>(ptr, [&](U* p) { destroy_levers_settings(reinterpret_cast<void*>(p)); });
    LuaType<std::shared_ptr<U>>::pushdata(L, sptr);
  }
  template<auto member_ptr, const char* func_name = nullptr>
  static int call_function_pointer(lua_State *L) {
    T* api = smart_shared_ptr_todata<T>(L);
    if (!api) {
      luaL_error(L, "RimeLeversApi is not initialized");
      return 0;
    }
    auto func_ptr = api->*member_ptr;
    assert(func_name);
    using FuncType = decltype(func_ptr);
    if constexpr SIGNATURE_CHECK(RimeCustomSettings*, const char*, const char*) {
      const char* param1 = luaL_checkstring(L, 2);
      const char* param2 = luaL_checkstring(L, 3);
      RimeCustomSettings* settings = func_ptr(param1, param2);
      push_from_raw<RimeCustomSettings>(L, settings);
      return 1;
    } else if constexpr SIGNATURE_CHECK(void, RimeCustomSettings*) {
      RimeCustomSettings* settings = lua_to_custom_settings(L, 2);
      func_ptr(settings);
      if (settings && strcmp(func_name, "custom_settings_destroy") == 0) {
        mark_levers_settings_destroyed(settings);
        if (luaL_testudata(L, 2, LuaType<std::shared_ptr<RimeCustomSettings>>::type()->name())) {
          auto &sp = LuaType<std::shared_ptr<RimeCustomSettings>>::todata(L, 2);
          sp.reset();
        } else if (luaL_testudata(L, 2, LuaType<std::shared_ptr<RimeSwitcherSettings>>::type()->name())) {
          auto &sp = LuaType<std::shared_ptr<RimeSwitcherSettings>>::todata(L, 2);
          sp.reset();
        }
      }
      return 0;
    } else if constexpr SIGNATURE_CHECK(RimeSwitcherSettings*, ) {
      // switcher_settings_init()
      RimeSwitcherSettings* settings = func_ptr();
      push_from_raw<RimeSwitcherSettings>(L, settings);
      return 1;
    } else if constexpr SIGNATURE_CHECK(void, RimeSwitcherSettings*) {
      RimeSwitcherSettings* settings = smart_shared_ptr_todata<RimeSwitcherSettings>(L, 2);
      func_ptr(settings);
      return 0;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeSwitcherSettings*) {
      RimeSwitcherSettings* settings = smart_shared_ptr_todata<RimeSwitcherSettings>(L, 2);
      auto ret = func_ptr(settings);
      lua_pushboolean(L, ret);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeCustomSettings*) {
      // load_settings / save_settings / is_first_run / settings_is_modified
      RimeCustomSettings* settings = lua_to_custom_settings(L, 2);
      if (!settings) {
        printf("Error: null RimeCustomSettings pointer passed to %s\n", func_name);
        return 0;
      }
      Bool ret = func_ptr(settings);
      lua_pushboolean(L, ret);
      return 1;
  } else if constexpr ( SIGNATURE_CHECK(Bool, RimeCustomSettings*, const char*, Bool) || SIGNATURE_CHECK(Bool, RimeCustomSettings*, const char*, int) ) {
      // rime_api.h typedefs Bool to int on some platforms, so at compile-time
      // Bool and int can be the same type. Disambiguate at runtime using
      // func_name: for "customize_bool" treat the 3rd arg as boolean,
      // for "customize_int" treat it as integer. This covers both cases.
      RimeCustomSettings* settings = lua_to_custom_settings(L, 2);
      const char* key = luaL_checkstring(L, 3);
      Bool ret = false;
      if (strcmp(func_name, "customize_bool") == 0) {
        Bool val = lua_toboolean(L, 4);
        ret = reinterpret_cast<Bool(*)(RimeCustomSettings*, const char*, Bool)>(func_ptr)(settings, key, val);
      } else if (strcmp(func_name, "customize_int") == 0) {
        int val = luaL_checkinteger(L, 4);
        ret = reinterpret_cast<Bool(*)(RimeCustomSettings*, const char*, int)>(func_ptr)(settings, key, val);
      } else {
        // fallback: try boolean first
        Bool val = lua_toboolean(L, 4);
        ret = reinterpret_cast<Bool(*)(RimeCustomSettings*, const char*, Bool)>(func_ptr)(settings, key, val);
      }
      lua_pushboolean(L, ret);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeCustomSettings*, const char*, double) {
      // customize_double(settings, key, value)
      RimeCustomSettings* settings = lua_to_custom_settings(L, 2);
      const char* key = luaL_checkstring(L, 3);
      double val = luaL_checknumber(L, 4);
      Bool ret = func_ptr(settings, key, val);
      lua_pushboolean(L, ret);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeCustomSettings*, const char*, const char*) {
      // customize_string(settings, key, value)
      RimeCustomSettings* settings = lua_to_custom_settings(L, 2);
      const char* key = luaL_checkstring(L, 3);
      const char* val = luaL_checkstring(L, 4);
      Bool ret = func_ptr(settings, key, val);
      lua_pushboolean(L, ret);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeCustomSettings*, RimeConfig*) {
      // settings_get_config(settings, config)
      RimeCustomSettings* settings = lua_to_custom_settings(L, 2);
      RimeConfig* cfg = smart_shared_ptr_todata<RimeConfig>(L, 3);
      Bool ret = func_ptr(settings, cfg);
      if (ret) set_config_borrowed(cfg, true);
      lua_pushboolean(L, ret);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeSwitcherSettings*, RimeSchemaList*) {
      // get_available_schema_list / get_selected_schema_list
      RimeSwitcherSettings* settings = smart_shared_ptr_todata<RimeSwitcherSettings>(L, 2);
      RimeSchemaList* list = smart_shared_ptr_todata<RimeSchemaList>(L, 3);
      Bool ret = func_ptr(settings, list);
      if (ret)
        schemalist_borrowed_set.insert(list);
      lua_pushboolean(L, ret);
      return 1;
    } else if constexpr SIGNATURE_CHECK(void, RimeSchemaList*) {
      // schema_list_destroy
      RimeSchemaList* list = smart_shared_ptr_todata<RimeSchemaList>(L, 2);
      func_ptr(list);
      return 0;
    } else if constexpr SIGNATURE_CHECK(const char*, RimeSchemaInfo*) {
      // get_schema_* (id/name/version/author/description/file_path)
      RimeSchemaInfo* info = smart_shared_ptr_todata<RimeSchemaInfo>(L, 2);
      const char* s = func_ptr(info);
      PUSH_VALUE_OR_NIL(L, s, s != nullptr, lua_pushstring);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeSwitcherSettings*, const char*[], int) {
      // select_schemas(settings, const char* schema_id_list[], int count)
      RimeSwitcherSettings* settings = smart_shared_ptr_todata<RimeSwitcherSettings>(L, 2);
      if (!lua_istable(L, 3)) {
        luaL_error(L, "select_schemas expects a table of schema ids as second argument");
        return 0;
      }
      size_t len = lua_rawlen(L, 3);
      std::vector<const char*> ids;
      ids.reserve(len);
      for (size_t i = 1; i <= len; ++i) {
        lua_rawgeti(L, 3, i);
        const char* id = luaL_checkstring(L, -1);
        ids.push_back(id);
        lua_pop(L, 1);
      }
      Bool ret = func_ptr(settings, ids.data(), (int)ids.size());
      lua_pushboolean(L, ret);
      return 1;
    } else if constexpr SIGNATURE_CHECK(const char*, RimeSwitcherSettings*) {
      // get_hotkeys
      RimeSwitcherSettings* settings = smart_shared_ptr_todata<RimeSwitcherSettings>(L, 2);
      const char* s = func_ptr(settings);
      PUSH_VALUE_OR_NIL(L, s, s != nullptr, lua_pushstring);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeSwitcherSettings*, const char*) {
      // set_hotkeys
      RimeSwitcherSettings* settings = smart_shared_ptr_todata<RimeSwitcherSettings>(L, 2);
      const char* hot = luaL_checkstring(L, 3);
      Bool ret = func_ptr(settings, hot);
      lua_pushboolean(L, ret);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeUserDictIterator*) {
      RimeUserDictIterator* iter = smart_shared_ptr_todata<RimeUserDictIterator>(L, 2);
      Bool ret = func_ptr(iter);
      lua_pushboolean(L, ret);
      return 1;
    } else if constexpr SIGNATURE_CHECK(void, RimeUserDictIterator*) {
      RimeUserDictIterator* iter = smart_shared_ptr_todata<RimeUserDictIterator>(L, 2);
      func_ptr(iter);
      return 0;
    } else if constexpr SIGNATURE_CHECK(const char*, RimeUserDictIterator*) {
      RimeUserDictIterator* iter = smart_shared_ptr_todata<RimeUserDictIterator>(L, 2);
      const char* s = func_ptr(iter);
      PUSH_VALUE_OR_NIL(L, s, s != nullptr, lua_pushstring);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, const char*) {
      const char* name = luaL_checkstring(L, 2);
      Bool ret = func_ptr(name);
      lua_pushboolean(L, ret);
      return 1;
    } else if constexpr SIGNATURE_CHECK(int, const char*, const char*) {
      const char* name = luaL_checkstring(L, 2);
      const char* path = luaL_checkstring(L, 3);
      int ret = func_ptr(name, path);
      lua_pushinteger(L, ret);
      return 1;
    } else if constexpr SIGNATURE_CHECK(Bool, RimeCustomSettings*, const char*, RimeConfig*) {
      RimeCustomSettings* settings = smart_shared_ptr_todata<RimeCustomSettings>(L, 2);
      const char* key = luaL_checkstring(L, 3);
      RimeConfig* cfg = smart_shared_ptr_todata<RimeConfig>(L, 4);
      Bool ret = func_ptr(settings, key, cfg);
      lua_pushboolean(L, ret);
      return 1;
    } else {
      luaL_error(L, "Unsupported function signature for function: %s", func_name);
      return 0;
    }
  }
  static int to_rime_levers_api(lua_State *L) {
    RimeCustomApi* t = smart_shared_ptr_todata<RimeCustomApi>(L);
    if (!t) {
      lua_pushnil(L);
      return 1;
    }
    auto api_ptr = std::shared_ptr<T>((RimeLeversApi*)t, [](T*){});
    LuaType<std::shared_ptr<T>>::pushdata(L, api_ptr);
    return 1;
  }
  static int raw_make(lua_State *L) {
    if (lua_gettop(L) == 1) {
      RimeCustomApi* t = smart_shared_ptr_todata<RimeCustomApi>(L);
      if (!t) {
        lua_pushnil(L);
      } else {
        auto api_ptr = std::shared_ptr<T>((RimeLeversApi*)t, [](T*){});
        LuaType<std::shared_ptr<T>>::pushdata(L, api_ptr);
      }
      return 1;
    }
    T *t = RIMELEVERSAPI;
    // 将API指针包装到shared_ptr中进行管理
    auto api_ptr = std::shared_ptr<T>(t, [](T*){});
    LuaType<std::shared_ptr<T>>::pushdata(L, api_ptr);
    return 1;
  }
  static const luaL_Reg funcs[] = {
    {"RimeLeversApi", raw_make},
    {"ToRimeLeversApi", to_rime_levers_api},
    {nullptr, nullptr}
  };
  static const luaL_Reg methods[] = {
    {"custom_settings_init", WRAP_API_FUNC(custom_settings_init)},
    {"custom_settings_destroy", WRAP_API_FUNC(custom_settings_destroy)},
    {"load_settings", WRAP_API_FUNC(load_settings)},
    {"save_settings", WRAP_API_FUNC(save_settings)},
    {"customize_bool", WRAP_API_FUNC(customize_bool)},
    {"customize_int", WRAP_API_FUNC(customize_int)},
    {"customize_double", WRAP_API_FUNC(customize_double)},
    {"customize_string", WRAP_API_FUNC(customize_string)},
    {"is_first_run", WRAP_API_FUNC(is_first_run)},
    {"settings_is_modified", WRAP_API_FUNC(settings_is_modified)},
    {"settings_get_config", WRAP_API_FUNC(settings_get_config)},
    {"switcher_settings_init", WRAP_API_FUNC(switcher_settings_init)},
    {"get_available_schema_list", WRAP_API_FUNC(get_available_schema_list)},
    {"get_selected_schema_list", WRAP_API_FUNC(get_selected_schema_list)},
    {"schema_list_destroy", WRAP_API_FUNC(schema_list_destroy)},
    {"get_schema_id", WRAP_API_FUNC(get_schema_id)},
    {"get_schema_name", WRAP_API_FUNC(get_schema_name)},
    {"get_schema_version", WRAP_API_FUNC(get_schema_version)},
    {"get_schema_author", WRAP_API_FUNC(get_schema_author)},
    {"get_schema_description", WRAP_API_FUNC(get_schema_description)},
    {"get_schema_file_path", WRAP_API_FUNC(get_schema_file_path)},
    {"select_schemas", WRAP_API_FUNC(select_schemas)},
    {"get_hotkeys", WRAP_API_FUNC(get_hotkeys)},
    {"set_hotkeys", WRAP_API_FUNC(set_hotkeys)},
    {"user_dict_iterator_init", WRAP_API_FUNC(user_dict_iterator_init)},
    {"user_dict_iterator_destroy", WRAP_API_FUNC(user_dict_iterator_destroy)},
    {"next_user_dict", WRAP_API_FUNC(next_user_dict)},
    {"backup_user_dict", WRAP_API_FUNC(backup_user_dict)},
    {"restore_user_dict", WRAP_API_FUNC(restore_user_dict)},
    {"export_user_dict", WRAP_API_FUNC(export_user_dict)},
    {"import_user_dict", WRAP_API_FUNC(import_user_dict)},
    {"customize_item", WRAP_API_FUNC(customize_item)},
    {nullptr, nullptr}
  };
  static const luaL_Reg vars_get[] = {
    {"type", type<std::shared_ptr<T>>},
    {nullptr, nullptr} };
  static const luaL_Reg vars_set[] = { {nullptr, nullptr} };
}
#undef SIGNATURE_CHECK
#undef WRAP_API_FUNC
#undef DECLARE_FUNC_NAME_VAR

static int os_trymkdir(lua_State* L) {
  const char* path = luaL_checkstring(L, 1);
  std::filesystem::path p(path);
  std::error_code ec;
  bool created = std::filesystem::create_directories(p, ec);
  if (ec) lua_pushboolean(L, false);
  else lua_pushboolean(L, true);
  return 1;
}

static int os_isdir(lua_State* L) {
  const char* path = luaL_checkstring(L, 1);
  bool ret = false;
  if (path) {
    std::filesystem::path p(path);
    ret = std::filesystem::is_directory(p);
  }
  lua_pushboolean(L, ret);
  return 1;
}

static void register_rime_bindings(lua_State *L) {
  EXPORT(RimeTraitsReg, L);
  EXPORT(RimeCompositionReg, L);
  EXPORT(RimeCandidateReg, L);
  EXPORT(RimeMenuReg, L);
  EXPORT(RimeCommitReg, L);
  EXPORT(RimeContextReg, L);
  EXPORT(RimeStatusReg, L);
  EXPORT(RimeCandidateListIteratorReg, L);
  EXPORT(RimeConfigReg, L);
  EXPORT(RimeConfigIteratorReg, L);
  EXPORT(RimeSchemaListItemReg, L);
  EXPORT(RimeSchemaListReg, L);
  EXPORT(RimeStringSliceReg, L);
  EXPORT(RimeCustomApiReg, L);
  EXPORT(RimeModuleReg, L);
  EXPORT(RimeApiReg, L);
  EXPORT(RimeCustomSettingsReg, L);
  EXPORT(RimeSwitcherSettingsReg, L);
  EXPORT(RimeSchemaInfoReg, L);
  EXPORT(RimeUserDictIteratorReg, L);
  EXPORT(RimeLeversApiReg, L);
  // register os_trymkdir to os.mkdir
  lua_getglobal(L, "os");
  if (lua_istable(L, -1)) {
    lua_pushcfunction(L, os_trymkdir);
    lua_setfield(L, -2, "mkdir");
    lua_pushcfunction(L, os_isdir);
    lua_setfield(L, -2, "isdir");
  }
#ifdef WIN32
  const auto set_codepage = +[](lua_State* L) -> int {
    int cp = (!lua_gettop(L)) ? CP_UTF8 : luaL_checkinteger(L, 1);
    int ret = SetConsoleOutputCodePage(cp);
    lua_pushinteger(L, ret);
    return 1;
  };
#else
  const auto set_codepage = +[](lua_State* L) -> int { lua_pushinteger(L, 0); return 1; };
#endif
  lua_pushcfunction(L, (lua_CFunction)set_codepage);
  lua_setglobal(L, "set_console_codepage");
}

#ifdef WIN32
#define FREE_RIME() do { if (librime) { FreeLibrary(librime); librime = nullptr; } } while(0)
#define LOAD_RIME_LIBRARY() (LoadLibraryA("rime.dll") ? LoadLibraryA("rime.dll") : LoadLibraryA("librime.dll"))
#define LOAD_RIME_FUNCTION(handle) reinterpret_cast<RimeGetApi>(GetProcAddress(handle, "rime_get_api"))
#define CLEAR_RIME_ERROR() ((void)0)
#else
#define FREE_RIME() do { if (librime) { dlclose(librime); librime = nullptr; } } while(0)
#define LOAD_RIME_LIBRARY() (dlopen("librime.so", RTLD_LAZY | RTLD_LOCAL | RTLD_DEEPBIND) ? dlopen("librime.so", RTLD_LAZY | RTLD_LOCAL | RTLD_DEEPBIND) : dlopen("librime.dylib", RTLD_LAZY | RTLD_LOCAL))
#define LOAD_RIME_FUNCTION(handle) reinterpret_cast<RimeGetApi>(dlsym(handle, "rime_get_api"))
#define CLEAR_RIME_ERROR() ((void)dlerror())
#endif

static void get_api() {
  if (rime_api) return;
  librime = LOAD_RIME_LIBRARY();
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

#if defined(BUILD_AS_LUA_MODULE)
static void ensure_librime_gc(lua_State* L) {
  lua_getfield(L, LUA_REGISTRYINDEX, "__rime_library_gc");
  if (!lua_isnil(L, -1)) {
    lua_pop(L, 1);
    return;
  }
  lua_pop(L, 1);
  void* ud = lua_newuserdata(L, 0);
  if (!ud) return;
  if (luaL_newmetatable(L, "__rime_library_gc_mt")) {
    lua_pushcfunction(L, [](lua_State* L) -> int {
        rime_api = nullptr;
        FREE_RIME();
        return 0;
    });
    lua_setfield(L, -2, "__gc");
  }
  lua_setmetatable(L, -2);
  lua_setfield(L, LUA_REGISTRYINDEX, "__rime_library_gc");
}
extern "C" RIME_API int luaopen_rimeapi_lua(lua_State *L) {
  get_api();
  register_rime_bindings(L);
  ensure_librime_gc(L);
  // Create and return a module table that references main constructors
  lua_newtable(L);
  const char* names[] = {
    "RimeTraits", "RimeComposition", "RimeCandidate", "RimeMenu",
    "RimeCommit", "RimeContext", "RimeStatus", "RimeCandidateListIterator",
    "RimeConfig", "RimeConfigIterator", "RimeSchemaListItem", "RimeSchemaList",
    "RimeStringSlice", "RimeCustomApi", "RimeModule", "RimeApi", "RimeCustomSettings",
    "RimeSwitcherSettings", "RimeSchemaInfo", "RimeUserDictIterator", "RimeLeversApi",
    nullptr
  };
  for (const char** p = names; *p; ++p) {
    lua_getglobal(L, *p); // push global value
    if (!lua_isnil(L, -1)) {
      lua_setfield(L, -2, *p); // module[*p] = global
    } else {
      lua_pop(L, 1); // remove nil
    }
  }
  return 1; // return module table
}
#else
#ifdef _WIN32
static std::string app_script_path() {
  char exe_path[MAX_PATH] = {0};
  GetModuleFileNameA(NULL, exe_path, MAX_PATH);
  char* last_backslash = strrchr(exe_path, '\\');
  if (last_backslash) *last_backslash = '\0';
  std::string lua_path(exe_path);
  lua_path += "\\rimeapi.app.lua";
  return lua_path;
}
#else
#include <unistd.h>
static std::string app_script_path() {
  char exe_path[PATH_MAX];
  ssize_t len = readlink("/proc/self/exe", exe_path, sizeof(exe_path)-1);
  if (len != -1) {
    exe_path[len] = '\0';
    char* last_slash = strrchr(exe_path, '/');
    if (last_slash) *last_slash = '\0';
  }
  std::string lua_path(exe_path);
  lua_path += "/rimeapi.app.lua";
  return lua_path;
}
#endif
int main(int argc, char* argv[]) {
  int codepage = SetConsoleOutputCodePage();
  get_api();
  lua_State *L = luaL_newstate();
  luaL_openlibs(L);
  register_rime_bindings(L);
  // if argv is empty get to interactive mode, else use argv[1] as script path
  std::string script = argc > 1 && std::filesystem::exists(argv[1]) ?
    std::string(argv[1]) : "";
  // add script path's directory to package.path
  std::filesystem::path sp(script);
  std::string script_dir = sp.has_parent_path() ? sp.parent_path().string() : ".";
  lua_getglobal(L, "package");
  lua_getfield(L, -1, "path");
  std::string cur_path = lua_tostring(L, -1);
  cur_path += ";" + script_dir + "/?.lua";
  lua_pop(L, 1); // remove old path
  lua_pushstring(L, cur_path.c_str());
  lua_setfield(L, -2, "path");
  lua_pop(L, 1); // remove package table
  lua_newtable(L);
  // if script is directory, try set script to init.lua inside it
  if (!script.empty() && std::filesystem::is_directory(sp)) {
    std::filesystem::path init_path = sp / "init.lua";
    if (std::filesystem::exists(init_path)) {
      script = init_path.string();
    }
  }
  lua_pushstring(L, script.c_str());
  lua_rawseti(L, -2, 0);
  for (int i = 1; i < argc; ++i) {
    lua_pushstring(L, argv[i]);
    lua_rawseti(L, -2, i - 1);
  }
  lua_setglobal(L, "arg");
  const auto cleanup_levers_on_exit = [&]() {
    std::unordered_set<void*> tmp;
    std::lock_guard<std::mutex> lk(levers_settings_mutex);
    tmp.swap(levers_settings_owned);
    auto api = RIMELEVERSAPI;
    if (!api) return;
    for (auto p : tmp) {
      api->custom_settings_destroy(reinterpret_cast<RimeCustomSettings*>(p));
    }
  };
  int ret = 0;
  if (script.empty()) {
    auto app_script = app_script_path();
    if (!std::filesystem::exists(app_script)) {
      printf("Error: no script specified and default app script not found: %s\n", app_script.c_str());
      ret = 1;
    } else if(luaL_dofile(L, app_script_path().c_str())) {
      const char *msg = lua_tostring(L, -1);
      printf("Error: %s\n", msg);
      lua_pop(L, 1);  // remove error message
      ret = 1;
    }
  } else if (luaL_dofile(L, script.c_str())) {
    const char *msg = lua_tostring(L, -1);
    printf("Error: %s\n", msg);
    lua_pop(L, 1);  // remove error message
    ret = 1;
  }
  lua_close(L);
  cleanup_levers_on_exit();
  SetConsoleOutputCodePage(codepage);
  FREE_RIME();
  return ret;
}
#endif
