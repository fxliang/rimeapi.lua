#include "../src/rime_resources.h"
#include "types.h"
#include <cstdio>
#include <cstdlib>

static int configs_closed = 0;
static int statuses_freed = 0;
static int lists_freed = 0;

static void check(bool condition) {
  if (!condition) std::abort();
}

static Bool close_config(RimeConfig* value) {
  if (value->ptr) ++configs_closed;
  value->ptr = nullptr;
  return true;
}

static Bool free_status(RimeStatus* value) {
  check(value->data_size == sizeof(RimeStatus) - sizeof(value->data_size));
  ++statuses_freed;
  return true;
}

static void free_list(RimeSchemaList* value) {
  ++lists_freed;
  value->list = nullptr;
  value->size = 0;
}

template<typename T>
static void push_global(Lua& state, const char* name, std::shared_ptr<T>& value) {
  state.to_state([&](lua_State* L) {
    LuaType<std::shared_ptr<T>>::pushdata(L, value);
    lua_setglobal(L, name);
  });
}

static void clear_global(Lua& state, const char* name) {
  state.to_state([&](lua_State* L) { lua_pushnil(L); lua_setglobal(L, name); });
  state.gc();
  state.gc();
}

int main() {
  RimeApi fake{};
  RIME_STRUCT_INIT(RimeApi, fake);
  fake.config_close = close_config;
  fake.free_status = free_status;
  fake.free_schema_list = free_list;
  rime_api = &fake;
  {
    Lua state;
    auto config = make_rime_resource<RimeConfig>();
    config->ptr = &fake;
    push_global(state, "first", config);
    push_global(state, "second", config);
    config.reset();
    clear_global(state, "first");
    check(configs_closed == 0);
    clear_global(state, "second");
    check(configs_closed == 1);

    int owner_destroyed = 0;
    auto owner = std::shared_ptr<int>(new int(1), [&](int* p) { ++owner_destroyed; delete p; });
    auto borrowed = make_rime_resource<RimeConfig>();
    borrowed->ptr = &fake;
    set_config_borrowed(borrowed.get(), true, owner);
    owner.reset();
    push_global(state, "borrowed", borrowed);
    borrowed.reset();
    check(owner_destroyed == 0);
    clear_global(state, "borrowed");
    check(configs_closed == 1 && owner_destroyed == 1);
    check(cfg_borrowed_set.empty() && cfg_borrowed_owners.empty());

    auto status = make_rime_resource<RimeStatus>();
    push_global(state, "status", status);
    clear_global(state, "status");
    check(statuses_freed == 0); // A C++ owner must also delay resource cleanup.
    status.reset();
    check(statuses_freed == 1);

    auto list = make_rime_resource<RimeSchemaList>();
    push_global(state, "list", list);
    list.reset();
    clear_global(state, "list");
    check(lists_freed == 1);
  }
  rime_api = nullptr;
  make_rime_resource<RimeConfig>().reset(); // Cleanup is safe after API release.
  std::puts("Rime resource ownership tests passed");
}
