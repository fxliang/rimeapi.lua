// Standalone regression test for the C++ Lua wrapper; see CMake's BUILD_TESTING.
#include "types.h"
#include <cstdio>
#include <cstdlib>
#include <stdexcept>

static void check(bool condition) {
  if (!condition) {
    std::fputs("Lua lifetime regression failed\n", stderr);
    std::abort();
  }
}

static void run(lua_State *L, const char *source) {
  if (luaL_dostring(L, source) != LUA_OK) {
    std::fprintf(stderr, "%s\n", lua_tostring(L, -1));
    std::abort();
  }
}

struct PlainValue { int value = 0; };

int main() {
  std::shared_ptr<LuaObj> escaped;
  std::weak_ptr<int> owned_value;
  {
    Lua owner;
    owner.to_state([&](lua_State *L) {
      auto value = std::make_shared<int>(11);
      owned_value = value;
      LuaType<std::shared_ptr<int>>::pushdata(L, value);
      lua_setglobal(L, "owned_value");
      PlainValue plain;
      LuaType<PlainValue>::pushdata(L, plain);
      lua_pushnil(L);
      lua_setmetatable(L, -2);  // Cleanup identities even if the owner loses __gc.
      lua_pop(L, 1);
      run(L, "function value() return 42 end\n"
             "function bad() error({reason = 'table'}) end\n"
             "function generator() yield(1, 2); yield(); error({}) end");
      lua_State *C = lua_newthread(L);
      check(Lua::from_state(C) == &owner);
      lua_getglobal(C, "value");
      escaped = LuaObj::todata(C, -1);
      lua_pop(C, 1);
      lua_pop(L, 1);
    });
    owner.gc();  // The coroutine can die while its referenced function survives.
    owner.to_state([](lua_State *L) {
      lua_gc(L, LUA_GCSTOP, 0);
      for (int i = 0; i < 512; ++i) {
        lua_newuserdata(L, sizeof(PlainValue));
        check(LuaIdentity::get(L, -1) == nullptr);
        lua_pop(L, 1);
      }
      lua_gc(L, LUA_GCRESTART, 0);
    });
    auto result = owner.call<int>(escaped);
    check(result.ok() && result.get() == 42);
    auto bad = owner.call<int>(owner.getglobal("bad"));
    check(!bad.ok() && !bad.get_err().e.empty());
    auto bad_void = owner.void_call(owner.getglobal("bad"));
    check(!bad_void.ok());
    check(!owner.resume<int>(owner.getglobal("value")).ok());
    check(!owner.newthread(std::shared_ptr<LuaObj>{}));
    auto thread = owner.newthread(owner.getglobal("generator"));
    auto first = owner.resume<int>(thread);
    check(first.ok() && first.get() == 2);
    check(!owner.resume<int>(thread).ok());  // yield without a value
    check(!owner.resume<int>(thread).ok());  // table error
    owner.to_state([](lua_State *L) { check(lua_gettop(L) == 0); });
  }
  check(owned_value.expired());  // State shutdown still runs native destructors.
  {
    Lua other;
    auto result = other.call<int>(escaped);
    check(!result.ok());  // An expired registry reference cannot alias a new state.
    escaped.reset();
  }

  lua_State *external = luaL_newstate();
  {
    Lua borrowed(external);
    run(external, "function value() return 7 end");
    escaped = borrowed.getglobal("value");
  }
  run(external, "assert(value() == 7)");
  lua_close(external);
  escaped.reset();

  external = luaL_newstate();
  {
    Lua borrowed(external);
    lua_close(external);  // The caller may close its state before the wrapper dies.
    borrowed.gc();
    borrowed.gc_step(1);
    check(!borrowed.call<int>(escaped).ok());
    check(!borrowed.void_call(escaped).ok());
    check(!borrowed.resume<int>(escaped).ok());
    bool rejected = false;
    try {
      borrowed.getglobal("value");
    } catch (const std::runtime_error &) {
      rejected = true;
    }
    check(rejected);
    rejected = false;
    try {
      borrowed.to_state([](lua_State *) {});
    } catch (const std::runtime_error &) {
      rejected = true;
    }
    check(rejected);
  }
  {
    Lua a;
    Lua b;
    a.to_state([](lua_State *L) { run(L, "function value() return 9 end"); });
    auto f = a.getglobal("value");
    check(!b.call<int>(f).ok());
    check(!b.newthread(f));
    check(a.call<int>(f).get() == 9);
  }
  external = luaL_newstate();
  check(Lua::from_state(external) == nullptr);
  check(lua_gettop(external) == 0);
  {
    Lua first(external);
    {
      Lua second(external);
      check(Lua::from_state(external) == &second);
    }
    check(Lua::from_state(external) == &first);
  }
  check(Lua::from_state(external) == nullptr);
  lua_close(external);
  check(LuaIdentity::identities().empty());
  check(LuaIdentity::guards().empty());
  std::puts("Lua state lifetime regressions passed");
}
