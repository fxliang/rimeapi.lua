#include "fixture.h"
#include "export.h"
#include <cstdio>
#include <cstdlib>

static void check(bool condition) {
  if (!condition) std::abort();
}

static void run(lua_State* L, const char* code) {
  if (luaL_dostring(L, code) != LUA_OK) {
    std::fprintf(stderr, "%s\n", lua_tostring(L, -1));
    std::abort();
  }
}

static void export_probe(lua_State* L) {
  const luaL_Reg empty[] = {{nullptr, nullptr}};
  const luaL_Reg methods[] = {{"add", WRAPMEM(InteropProbe::add)}, {nullptr, nullptr}};
  const luaL_Reg getters[] = {
    {"value", LuaInterop::get_member<InteropProbe, int, &InteropProbe::value>},
    {"name", LuaInterop::get_member<InteropProbe, std::string, &InteropProbe::name>},
    {nullptr, nullptr}};
  const luaL_Reg setters[] = {
    {"value", LuaInterop::set_member<InteropProbe, int, &InteropProbe::value>},
    {"name", LuaInterop::set_member<InteropProbe, std::string, &InteropProbe::name>},
    {nullptr, nullptr}};
  lua_export_type(L, LuaType<std::shared_ptr<InteropProbe>>::type(),
      LuaType<std::shared_ptr<InteropProbe>>::gc, empty, methods, getters, setters);
}

int main() {
  int destroyed = 0;
  auto probe = std::shared_ptr<InteropProbe>(new InteropProbe,
      [&](InteropProbe* value) { ++destroyed; delete value; });
  {
    Lua state;
    state.to_state([&](lua_State* L) {
      export_probe(L);
      push_probe_from_other_unit(L, probe);
      check(LuaType<std::shared_ptr<InteropProbe>>::todata(L, -1) == probe);
      check(read_probe_from_other_unit(L, -1) == probe);
      lua_setglobal(L, "first");
      LuaType<std::shared_ptr<InteropProbe>>::pushdata(L, probe);
      lua_setglobal(L, "second");
      run(L, "assert(first.value == 7 and first.name == 'probe')\n"
             "first.value = 10; first.name = 'updated'\n"
             "assert(second.value == 10 and second.name == 'updated')\n"
             "assert(second:add(2) == 12)\n"
             "assert(not pcall(function() first.value = {} end))\n"
             "assert(not pcall(function() first.name = {} end))\n"
             "local mt = debug.getmetatable(first)\n"
             "mt.__gc(first); mt.__gc(first)\n"
             "assert(not pcall(function() return first.value end))\n"
             "assert(second.value == 12)\n"
             "first = nil; collectgarbage('collect')");
      check(lua_gettop(L) == 0);
    });
    check(destroyed == 0 && probe->value == 12);
    probe.reset();
    check(destroyed == 0); // The second Lua wrapper still owns the resource.
  }
  check(destroyed == 1);

  int owner_destroyed = 0;
  {
    Lua state;
    auto owner = std::shared_ptr<int>(new int(9), [&](int* p) { ++owner_destroyed; delete p; });
    state.to_state([&](lua_State* L) {
      InteropProbe value;
      LuaType<InteropProbe>::pushdata(L, value);
      LuaInterop::push_owner_uservalue(L, -1, owner);
      check(LuaInterop::get_owner_uservalue(L, -1).get() == owner.get());
      lua_setglobal(L, "child");
      char text[] = "mutable";
      LuaType<char*>::pushdata(L, text);
      check(std::string(lua_tostring(L, -1)) == "mutable");
      lua_pop(L, 1);
      LuaType<const char*>::pushdata(L, nullptr);
      check(std::string(lua_tostring(L, -1)).empty());
      lua_pop(L, 1);
    });
    owner.reset();
    state.gc();
    check(owner_destroyed == 0);
    state.to_state([](lua_State* L) { run(L, "child = nil"); });
    state.gc();
    state.gc();
    check(owner_destroyed == 1);
  }
  {
    Lua state(nullptr, {false, false});
    state.to_state([](lua_State* L) {
      for (const char* name : {"os", "io", "table", "Set", "yield"}) {
        lua_getglobal(L, name);
        check(lua_isnil(L, -1));
        lua_pop(L, 1);
      }
      run(L, "function value(a, b) return a + b end");
    });
    auto result = state.call<int>(state.getglobal("value"), 2, 3);
    check(result.ok() && result.get() == 5);
    auto thread = state.newthread(state.getglobal("value"), 2, 3);
    check(bool(thread));
    auto finished = state.resume<int>(thread);
    check(!finished.ok() && finished.get_err().status == LUA_OK);
  }
  check(LuaIdentity::identities().empty());
  check(LuaIdentity::guards().empty());
  std::puts("independent interop object tests passed");
}
