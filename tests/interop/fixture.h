#pragma once
#include "object.h"
#include <string>

struct InteropProbe {
  int value = 7;
  std::string name = "probe";
  int add(int amount) { return value += amount; }
};

void push_probe_from_other_unit(lua_State* L, std::shared_ptr<InteropProbe>& probe);
std::shared_ptr<InteropProbe> read_probe_from_other_unit(lua_State* L, int index);
