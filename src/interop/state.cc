#include "state.h"
#include "types.h"

#include <algorithm>
#include <climits>
#include <stdexcept>

struct LuaStateLifetime {
  lua_State *state;
  std::vector<Lua *> owners;
};

namespace {
  const char lifetime_key = 0;
  using Lifetime = std::shared_ptr<LuaStateLifetime>;
  const LuaTypeInfo *lifetime_type() {
    return &LuaTypeInfo::make<LuaStateLifetime>();
  }

  Lifetime state_lifetime(lua_State *L, bool create = true) {
    lua_rawgetp(L, LUA_REGISTRYINDEX, &lifetime_key);
    if (lua_isnil(L, -1)) {
      lua_pop(L, 1);
      if (!create)
        return {};
      lua_rawgeti(L, LUA_REGISTRYINDEX, LUA_RIDX_MAINTHREAD);
      lua_State *main = lua_tothread(L, -1);
      lua_pop(L, 1);
      // An indirection makes a manually repeated __gc harmless.
      auto slot = (Lifetime **)LuaIdentity::newuserdata(L, sizeof(Lifetime *));
      *slot = new Lifetime(std::make_shared<LuaStateLifetime>());
      (**slot)->state = main;
      LuaIdentity::set(L, lifetime_type());
      if (luaL_newmetatable(L, "__lua_state_lifetime")) {
        lua_pushcfunction(L, [](lua_State *L) -> int {
          auto slot = (Lifetime **)luaL_checkudata(L, 1, "__lua_state_lifetime");
          if (LuaIdentity::get(L, 1) != lifetime_type())
            return 0;
          LuaIdentity::erase(L, 1);
          if (*slot) {
            (**slot)->state = nullptr;
            delete *slot;
            *slot = nullptr;
          }
          return 0;
        });
        lua_setfield(L, -2, "__gc");
        lua_hide_metatable(L);
      }
      lua_setmetatable(L, -2);
      lua_pushvalue(L, -1);
      lua_rawsetp(L, LUA_REGISTRYINDEX, &lifetime_key);
    }
    auto slot = (Lifetime **)luaL_checkudata(L, -1, "__lua_state_lifetime");
    Lifetime result = LuaIdentity::get(L, -1) == lifetime_type() && *slot
        ? **slot : Lifetime{};
    lua_pop(L, 1);
    return result;
  }
}

namespace LuaImpl {
  int wrap_common(lua_State *L, int (*cfunc)(lua_State *)) {
    alignas(C_State) char room[sizeof(C_State)];
    C_State *C = new (&room) C_State();
    lua_pushcfunction(L, cfunc);
    lua_insert(L, 1);
    lua_pushlightuserdata(L, (void *) C);
    lua_insert(L, 2);
    int status = lua_pcall(L, lua_gettop(L) - 1, LUA_MULTRET, 0);
    if (status != LUA_OK) {
      C->~C_State();
      lua_error(L);
      abort(); // unreachable
    }
    C->~C_State();
    return lua_gettop(L);
  }

  static int index(lua_State *L) {
    if (luaL_getmetafield(L, 1, "methods") != LUA_TNIL) {
      lua_pushvalue(L, 2);
      lua_rawget(L, -2);
      if (!lua_isnil(L, -1)) {
        return 1;
      }
      lua_pop(L, 2);  // value, methods
    }

    if (luaL_getmetafield(L, 1, "vars_get") != LUA_TNIL) {
      lua_pushvalue(L, 2);
      lua_rawget(L, -2);
      if (!lua_isnil(L, -1)) {
        auto f = lua_tocfunction(L, -1);
        lua_pop(L, 2);  // value, vars_get
        if (f) {
          lua_remove(L, 2);  // key, leaving self at index 1
          return f(L);
        }
      } else {
        lua_pop(L, 2);  // value, vars_get
      }
    }
    return 0;
  }

  static int newindex(lua_State *L) {
    if (luaL_getmetafield(L, 1, "vars_set") != LUA_TNIL) {
      lua_pushvalue(L, 2);
      lua_rawget(L, -2);
      if (!lua_isnil(L, -1)) {
        auto f = lua_tocfunction(L, -1);
        lua_pop(L, 2);  // value, vars_set
        if (f) {
          lua_remove(L, 2);  // key, leaving self and value
          return f(L);
        }
      } else {
        lua_pop(L, 2);  // value, vars_set
      }
    }
    return 0;
  }

  namespace SetReg {
    static int raw_make(lua_State *L) {
      if (lua_gettop(L) != 1 || lua_type(L, 1) != LUA_TTABLE)
        return 0;
      int n = lua_rawlen(L, 1);
      lua_createtable(L, n, 0);
      for (int i = 1; i <= n; i++) {
        lua_rawgeti(L, 1, i);
        LuaType<bool>::pushdata(L, true);
        lua_rawset(L, -3);
      }
      luaL_setmetatable(L, "__set");
      return 1;
    }

    static int raw_union(lua_State *L) {
      int n = lua_gettop(L);
      for (int i = 1; i <= n; i++)
        if (lua_type(L, i) != LUA_TTABLE)
          return 0;
      lua_createtable(L, 0, 0);
      for (int i = 1; i <= n; i++) {
        lua_pushnil(L);
        while (lua_next(L, i) != 0) {
          lua_pushvalue(L, -2);
          LuaType<bool>::pushdata(L, true);
          lua_rawset(L, -5);
          lua_pop(L, 1);
        }
      }
      luaL_setmetatable(L, "__set");
      return 1;
    }

    static int raw_inter(lua_State *L) {
      int n = lua_gettop(L);
      for (int i = 1; i <= n; i++)
        if (lua_type(L, i) != LUA_TTABLE)
          return 0;
      lua_createtable(L, 0, 0);
      if (n > 0) {
        lua_pushnil(L);
        while (lua_next(L, 1) != 0) {
          bool b = true;
          for (int i = 2; b && i <= n; i++) {
            lua_pushvalue(L, -2);
            lua_rawget(L, i);
            b = (lua_type(L, -1) != LUA_TNIL);
            lua_pop(L, 1);
          }
          if (b) {
            lua_pushvalue(L, -2);
            LuaType<bool>::pushdata(L, true);
            lua_rawset(L, -5);
          }
          lua_pop(L, 1);
        }
      }
      luaL_setmetatable(L, "__set");
      return 1;
    }

    static int raw_diff(lua_State *L) {
      int n = lua_gettop(L);
      for (int i = 1; i <= n; i++)
        if (lua_type(L, i) != LUA_TTABLE)
          return 0;
      lua_createtable(L, 0, 0);
      if (n > 0) {
        lua_pushnil(L);
        while (lua_next(L, 1) != 0) {
          bool b = true;
          for (int i = 2; b && i <= n; i++) {
            lua_pushvalue(L, -2);
            lua_rawget(L, i);
            b = (lua_type(L, -1) == LUA_TNIL);
            lua_pop(L, 1);
          }
          if (b) {
            lua_pushvalue(L, -2);
            LuaType<bool>::pushdata(L, true);
            lua_rawset(L, -5);
          }
          lua_pop(L, 1);
        }
      }
      luaL_setmetatable(L, "__set");
      return 1;
    }

    static int raw_empty(lua_State *L) {
      if (lua_gettop(L) != 1)
        return 0;

      lua_pushnil(L);
      if (lua_next(L, 1) == 0) {
        LuaType<bool>::pushdata(L, true);
      } else {
        lua_pop(L, 2);
        LuaType<bool>::pushdata(L, false);
      }
      return 1;
    }

    static const luaL_Reg methods[] = {
      { "empty", raw_empty },
      { NULL, NULL },
    };

    static const luaL_Reg mt[] = {
      { "__index", index },
      { "__add", raw_union },
      { "__sub", raw_diff },
      { "__mul", raw_inter },
      { NULL, NULL },
    };
  }

  void export_set(lua_State *L) {
    lua_register(L, "Set", SetReg::raw_make);

    luaL_newmetatable(L, "__set");
    luaL_setfuncs(L, SetReg::mt, 0);
    lua_createtable(L, 0, 0);
    luaL_setfuncs(L, SetReg::methods, 0);
    lua_setfield(L, -2, "methods");
    lua_hide_metatable(L);
    lua_pop(L, 1);
  }

  static int yield(lua_State *L) {
    return lua_yield(L, lua_gettop(L));
  }

  static const char makeclosurekey = 'k';

  static int unpack_args(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    size_t count = lua_rawlen(L, 1);
    if (count > INT_MAX || !lua_checkstack(L, (int)count))
      return luaL_error(L, "too many coroutine arguments");
    for (size_t i = 1; i <= count; ++i)
      lua_rawgeti(L, 1, i);
    return (int)count;
  }

  static int pmain(lua_State *L) {
    if (lua_toboolean(L, lua_upvalueindex(1))) {
      luaL_openlibs(L);
      xluaopen_utf8(L);
    }
    if (lua_toboolean(L, lua_upvalueindex(2))) {
      lua_register(L, "yield", yield);
      export_set(L);
    }

    lua_pushlightuserdata(L, (void *)&makeclosurekey);
    if (luaL_loadstring(L, "local unpack = ...\n"
                  "return function (f, ...)\n"
                  "local args = {...}\n"
                  "return (function () return f(unpack(args)) end)\n"
                  "end\n") != LUA_OK)
      return lua_error(L);
    lua_pushcfunction(L, unpack_args);
    lua_call(L, 1, 1);
    lua_settable(L, LUA_REGISTRYINDEX);

    return 0;
  }
}

Lua::Lua(lua_State *L, LuaOptions options) {
  owns_ = (L == nullptr);
  L_ = L ? L : luaL_newstate();
  if (!L_)
    throw std::bad_alloc();
  if (L_) {
    lifetime_ = state_lifetime(L_);
    if (!lifetime_ || !lifetime_->state)
      throw std::runtime_error("Lua state lifetime has ended");
    L_ = lifetime_->state;
    lifetime_->owners.push_back(this);

    lua_pushboolean(L_, options.open_libraries);
    lua_pushboolean(L_, options.install_helpers);
    lua_pushcclosure(L_, &LuaImpl::pmain, 2);
    lua_call(L_, 0, 0);
  }
}

Lua::~Lua() {
  closing_ = true;
  if (!L_ || !lifetime_)
    return;
  auto &owners = lifetime_->owners;
  owners.erase(std::remove(owners.begin(), owners.end(), this), owners.end());
  if (owns_ && lifetime_->state) {
    lifetime_->state = nullptr;
    lua_close(L_);
  }
  L_ = nullptr;
}

Lua *Lua::from_state(lua_State *L) {
  if (!L)
    return nullptr;
  auto lifetime = state_lifetime(L, false);
  return lifetime && lifetime->state && !lifetime->owners.empty()
      ? lifetime->owners.back() : nullptr;
}

void Lua::to_state(std::function<void (lua_State *)> f) {
  require_live();
  f(L_);
}

bool Lua::is_live() const {
  return !closing_ && lifetime_ && lifetime_->state;
}

void Lua::require_live() const {
  if (!is_live())
    throw std::runtime_error("Lua state lifetime has ended");
}

std::shared_ptr<LuaObj> Lua::newthreadx(lua_State *L, int nargs) {
  require_live();
  if (nargs < 1 || nargs > lua_gettop(L) ||
      state_lifetime(L, false) != lifetime_)
    return nullptr;
  if (!lua_isfunction(L, -nargs)) {
    lua_pop(L, nargs);
    return nullptr;
  }
  lua_State *C = lua_newthread(L_);
  auto o = LuaObj::todata(L_, -1);
  lua_pop(L_, 1);

  lua_pushlightuserdata(C, (void *)&LuaImpl::makeclosurekey);
  lua_gettable(C, LUA_REGISTRYINDEX);
  lua_xmove(L, C, nargs);
  if (lua_pcall(C, nargs, 1, 0) != LUA_OK) {
    lua_settop(C, 0);
    return nullptr;
  }

  return o;
}

std::shared_ptr<LuaObj> Lua::getglobal(const std::string &v) {
  require_live();
  lua_getglobal(L_, v.c_str());
  auto o = LuaObj::todata(L_, -1);
  lua_pop(L_, 1);
  return o;
}

void Lua::gc() {
  if (!is_live()) {
    return;
  }
  lua_gc(L_, LUA_GCCOLLECT, 0);
}

void Lua::gc_step(int kb) {
  if (!is_live()) {
    return;
  }
  lua_gc(L_, LUA_GCSTEP, kb);
}

LuaObj::LuaObj(lua_State *L, int i) : lifetime_(state_lifetime(L)) {
  lua_pushvalue(L, i);
  id_ = luaL_ref(L, LUA_REGISTRYINDEX);
}

LuaObj::~LuaObj() {
  // The state may already have been closed if this object outlived Lua.
  if (lifetime_ && lifetime_->state)
    luaL_unref(lifetime_->state, LUA_REGISTRYINDEX, id_);
}

void LuaObj::pushdata(lua_State *L, std::shared_ptr<LuaObj> &o) {
  if (!o) {
    lua_pushnil(L);
    return;
  }
  if (!o->lifetime_ || !o->lifetime_->state ||
      o->lifetime_ != state_lifetime(L)) {
    lua_pushnil(L);
    return;
  }
  lua_rawgeti(L, LUA_REGISTRYINDEX, o->id_);
}

std::shared_ptr<LuaObj> LuaObj::todata(lua_State *L, int i) {
  return std::shared_ptr<LuaObj>(new LuaObj(L, i));
}

void lua_export_type(lua_State *L,
                     const LuaTypeInfo *type, lua_CFunction gc,
                     const luaL_Reg *funcs, const luaL_Reg *methods,
                     const luaL_Reg *vars_get, const luaL_Reg *vars_set) {
  for (int i = 0; funcs[i].name; i++) {
    lua_register(L, funcs[i].name, funcs[i].func);
  }

  luaL_newmetatable(L, type->name());
  lua_pushlightuserdata(L, (void *) type);
  lua_setfield(L, -2, "type");
  if (gc) {
    lua_pushcfunction(L, gc);
    lua_setfield(L, -2, "__gc");
  }
  lua_createtable(L, 0, 0);
  luaL_setfuncs(L, methods, 0);
  lua_setfield(L, -2, "methods");
  // if there is a function name __tostring in methods, set it as __tostring metamethod
  lua_getfield(L, -1, "methods");
  lua_getfield(L, -1, "__tostring");
  if (!lua_isnil(L, -1)) {
    lua_setfield(L, -3, "__tostring");
  } else {
    lua_pop(L, 1);
  }
  lua_pop(L, 1);
  lua_createtable(L, 0, 0);
  luaL_setfuncs(L, vars_get, 0);
  lua_setfield(L, -2, "vars_get");
  lua_createtable(L, 0, 0);
  luaL_setfuncs(L, vars_set, 0);
  lua_setfield(L, -2, "vars_set");
  lua_pushcfunction(L, LuaImpl::index);
  lua_setfield(L, -2, "__index");
  lua_pushcfunction(L, LuaImpl::newindex);
  lua_setfield(L, -2, "__newindex");
  lua_hide_metatable(L);
  lua_pop(L, 1);
}
