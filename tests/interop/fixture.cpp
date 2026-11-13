#include "fixture.h"

void push_probe_from_other_unit(lua_State* L, std::shared_ptr<InteropProbe>& probe) {
  LuaType<std::shared_ptr<InteropProbe>>::pushdata(L, probe);
}

std::shared_ptr<InteropProbe> read_probe_from_other_unit(lua_State* L, int index) {
  return LuaInterop::lua_shared_ptr_todata<InteropProbe>(L, index);
}
