#pragma once

#include "types.h"

namespace LuaInterop {

// Values and shared ownership use the same native type identity checks.
// nil is permitted for APIs with optional object arguments; raw addresses are not.
template<typename T>
T* smart_shared_ptr_todata(lua_State *L, int index = 1) {
  if (lua_isnil(L, index)) return nullptr;
  if (luaL_testudata(L, index, LuaType<std::shared_ptr<T>>::type()->name())) {
    auto& value = LuaType<std::shared_ptr<T>>::todata(L, index);
    return value.get();
  }
  if (luaL_testudata(L, index, LuaType<T>::type()->name()))
    return &LuaType<T>::todata(L, index);
  luaL_argerror(L, index, "userdata of the expected type required");
  return nullptr;
}

template<typename T>
std::shared_ptr<T> lua_shared_ptr_todata(lua_State* L, int index) {
  if (!luaL_testudata(L, index, LuaType<std::shared_ptr<T>>::type()->name()))
    return {};
  return LuaType<std::shared_ptr<T>>::todata(L, index);
}

// The owner keeps storage referenced by a value userdata alive. It does not
// decide how the resource is released; that remains the owner's C++ deleter.
inline void push_owner_uservalue(
    lua_State* L, int userdata_index, const std::shared_ptr<void>& owner) {
  if (!owner) return;
  const int index = lua_absindex(L, userdata_index);
  auto copy = owner;
  LuaType<std::shared_ptr<void>>::pushdata(L, copy);
  lua_setuservalue(L, index);
}

inline std::shared_ptr<void> get_owner_uservalue(lua_State* L, int userdata_index) {
  std::shared_ptr<void> owner;
  if (lua_getuservalue(L, userdata_index) == LUA_TUSERDATA)
    owner = lua_shared_ptr_todata<void>(L, -1);
  lua_pop(L, 1);
  return owner;
}

template<typename T, typename Member, Member T::*member>
int get_member(lua_State* L) {
  T* object = smart_shared_ptr_todata<T>(L, 1);
  if (!object) {
    lua_pushnil(L);
    return 1;
  }
  LuaType<Member>::pushdata(L, object->*member);
  return 1;
}

template<typename T, typename Member, Member T::*member>
int set_member(lua_State* L) {
  return LuaImpl::wrap_common(L, +[](lua_State* L) -> int {
    auto* temporaries = (C_State*)lua_touserdata(L, 1);
    T* object = smart_shared_ptr_todata<T>(L, 2);
    if (!object)
      return luaL_argerror(L, 2, "non-null object required");
    object->*member = LuaType<Member>::todata(L, 3, temporaries);
    return 0;
  });
}

template<typename T, typename Member, Member T::*member>
int get_bool_member(lua_State* L) {
  T* object = smart_shared_ptr_todata<T>(L, 1);
  if (object) lua_pushboolean(L, !!(object->*member));
  else lua_pushnil(L);
  return 1;
}

}  // namespace LuaInterop
