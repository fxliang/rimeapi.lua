# rimeapi.lua: a lua API module for librime

## Overview
This module provides a set of functions to interact with the Rime Input Method Engine, allowing users to reference **librime api**, **librime levers** api related functionalities programmatically.

## Build Instructions
To build the shared library, xmake is required. Follow these steps(or follow workflow in `./.github/workflows/ci.yml`):

- install `xmake` or `cmake`, `git`, and compiler tools for your system
- clone the repository
- install `librime` for linux/macos, or prepare librime libs in `lib` or `lib64` and headers in `include` for windows/macos
- build the shared library for lua binding with `xmake` or `cmake`, if you want.
- to run tests, run `lua test.lua api_test levers_api_test`, or `luajit test.lua api_test levers_api_test`
- if your are to use this module in luajit, make sure lua is static linked in librime-lua for MacOS/termux, because `RTLD_DEEPBIND` is not supported in these platforms. for termux, you may also need to hide the lua apis from librime, follow is a patch for librime-lua to do this
```patch
diff --git a/CMakeLists.txt b/CMakeLists.txt
index 42f2ebb..404567e 100644
--- a/CMakeLists.txt
+++ b/CMakeLists.txt
@@ -20,9 +20,8 @@ else()
   include_directories(thirdparty/lua5.4)
   aux_source_directory(thirdparty/lua5.4 LUA_SRC)
   add_definitions(-DLUA_COMPAT_5_3)
-  if(WIN32)
-    set_property(SOURCE ${LUA_SRC} PROPERTY COMPILE_DEFINITIONS LUA_BUILD_AS_DLL)
-  else()
+  if(NOT WIN32)
+    set(USE_INTREE_LUA ON)
     set_property(SOURCE ${LUA_SRC} PROPERTY COMPILE_DEFINITIONS LUA_USE_POSIX;LUA_USE_DLOPEN)
     execute_process(
       COMMAND ${CMAKE_C_COMPILER} -print-multiarch
@@ -48,3 +47,17 @@ set(plugin_name "rime-lua" PARENT_SCOPE)
 set(plugin_objs $<TARGET_OBJECTS:rime-lua-objs> PARENT_SCOPE)
 set(plugin_deps ${LUA_TARGET} ${rime_library} ${rime_gears_library} PARENT_SCOPE)
 set(plugin_modules "lua" PARENT_SCOPE)
+
+# Hide Lua symbols on Unix-like systems when using in-tree Lua
+# for external lua engine capability
+if (USE_INTREE_LUA)
+  # On Unix-like systems, hide Lua symbols using compiler attributes
+  # Apply to object files only to avoid affecting main library
+  set_target_properties(rime-lua-objs PROPERTIES
+    C_VISIBILITY_PRESET hidden
+    CXX_VISIBILITY_PRESET hidden
+    VISIBILITY_INLINES_HIDDEN ON
+  )
+  # Apply hidden visibility to Lua source files specifically
+  set_source_files_properties(${LUA_SRC} PROPERTIES COMPILE_FLAGS "-fvisibility=hidden")
+endif(USE_INTREE_LUA)
```

## Files Description

- `rimeapi.lua`: a lua module for automatically loading shared library or ffi module, for lua(>=5.4)/luajit
- `rimeapi_ffi.lua`: a luajit ffi binding module just like `rimeapi_lua.so`/`rimeapi_lua.dll`/`rimeapi_lua.dylib`
- shared libraries for lua binding:
  - `rimeapi_lua.so`: for linux
  - `rimeapi_lua.dylib`: for macos
  - `rimeapi_lua.dll`: for windows
- shared library for luajit binding
  - `noti_bridge.so`: for linux
  - `noti_bridge.dylib`: for macos
  - `noti_bridge.dll`: for windows
- `scripts/api_test.lua`: a rime api test script
- `scripts/levers_api_test.lua`: a rime levers api test script
- `shared`: base yamls from `librime` project, and a yaml `api_test.yaml`
- `rimeapi.app.lua`: a lua(>=5.4)/luajit script, work as a REPL when no extra args passed, or run test scripts when args passed
- `rime_api_console.lua`: a lua script to work like `rime_api_console` of `librime`
- `get-rime.ps1`: a powershell script tool for getting `librime` for windows/macos
- `schema_tester.lua`: a lua script demo for testing rime schema
- `schema_tester_config.lua`: a config file for `schema_tester.lua`

## Credites

- [librime](https://github.com/rime/librime) (The 3-Clause BSD License) RIME: Rime Input Method Engine
- [librime-lua](https://github.com/hchunhui/librime-lua) (The 3-Clause BSD License) librime-lua: Extending RIME with Lua scripts. The lua binding codes is a mod from it.
- [lua](https://www.lua.org/) (The MIT License) Lua: Powerful, efficient, lightweight, embeddable scripting language.
- [luajit](https://luajit.org/) (The MIT License) LuaJIT: Just-In-Time Compiler for Lua.
