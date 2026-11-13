#ifndef LUA_INTEROP_STATE_H_
#define LUA_INTEROP_STATE_H_

#include <memory>
#include <functional>
#include <string>
#include "result.h"

struct lua_State;
struct LuaStateLifetime;

class LuaObj {
public:
  ~LuaObj();
  LuaObj(const LuaObj &) = delete;
  LuaObj &operator=(const LuaObj &) = delete;

  static void pushdata(lua_State *L, std::shared_ptr<LuaObj> &o);
  static std::shared_ptr<LuaObj> todata(lua_State *L, int i);

private:
  LuaObj(lua_State *L, int i);
  std::shared_ptr<LuaStateLifetime> lifetime_;
  int id_;
};

struct LuaErr { int status; std::string e; };
template <typename T>
using LuaResult = Result<T, LuaErr>;

struct LuaOptions {
  bool open_libraries = true;
  bool install_helpers = true;
};

class Lua {
public:
  Lua(lua_State *L = nullptr, LuaOptions options = {});
  ~Lua();
  Lua(const Lua &) = delete;
  Lua &operator=(const Lua &) = delete;

  std::shared_ptr<LuaObj> getglobal(const std::string &f);

  std::shared_ptr<LuaObj> newthreadx(lua_State *L, int nargs);

  void gc();
  void gc_step(int kb);

  template <typename ... I>
  std::shared_ptr<LuaObj> newthread(I ... input);

  template <typename O>
  LuaResult<O> resume(std::shared_ptr<LuaObj> f);

  template <typename O, typename ... I>
  LuaResult<O> call(I ... input);

  template <typename ... I>
  LuaResult<void> void_call(I ... input);

  void to_state(std::function<void (lua_State *)> f);



  static Lua *from_state(lua_State *L);
private:
  bool is_live() const;
  void require_live() const;
  lua_State *L_;
  std::shared_ptr<LuaStateLifetime> lifetime_;
  bool closing_ = false;
  bool owns_ = false;
};

namespace LuaImpl {
  int wrap_common(lua_State *L, int (*cfunc)(lua_State *));
}

#endif  // LUA_INTEROP_STATE_H_
