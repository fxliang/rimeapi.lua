# rimeapi.lua: a lua API module for librime

English | [简体中文](README.zh-CN.md)

## Overview
This module provides a set of functions to interact with the Rime Input Method Engine, allowing users to reference **librime api**, **librime levers** api related functionalities programmatically.

Use one binding backend per process. librime exposes one process-wide notification handler, so native `rimeapi_lua` and the LuaJIT `noti_bridge` must not be registered simultaneously.

See the [Lua API guide](docs/api.md) for initialization, lifecycle, ownership,
and API behavior. The complete signatures are in
[`rimeapi.annotation.lua`](rimeapi.annotation.lua).

## Build Instructions
To build the shared libraries, use xmake or CMake. Follow these steps (or the workflow in `./.github/workflows/ci.yml`):

The C++/Lua interop component can also be built and tested independently of
librime with `-DRIMEAPI_BUILD_BINDINGS=OFF -DBUILD_TESTING=ON` in CMake. See
[the component documentation](src/interop/README.md) for its ownership contract,
initialization options and test commands.

- install `xmake` or `cmake`, `git`, and compiler tools for your system
- clone the repository and initialize submodules: `git submodule update --init --recursive`
- install `librime` for Linux/macOS, or prepare librime libraries in `lib`/`lib64` and headers in `include` for Windows
- build with `xmake` or `cmake`
- run `./lua test.lua api_test levers_api_test` or `luajit test.lua api_test levers_api_test`; the harness creates a unique test user-data directory per process
- to choose the test data location explicitly, set `RIMEAPI_TEST_USER_DIR` to a writable directory
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

- `rimeapi.lua`: a lua module that loads the native Lua 5.4 backend or the LuaJIT FFI backend
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
- `rimeapi.app.lua`: a Lua 5.4/LuaJIT script, work as a REPL when no extra args passed, or run test scripts when args passed
- `rimeapi_completion.lua`: readline completion catalogs, including named Rime keys and common key combinations
- `rime_api_console.lua`: a lua script to work like `rime_api_console` of `librime`
- `get-rime.ps1`: a powershell script tool for getting `librime` for windows/macos
- `schema_tester.lua`: a lua script demo for testing rime schema
- `schema_tester_config.lua`: a config file for `schema_tester.lua`

## Command-line tools

All tools below are self-contained scripts. They add the current directory to
`package.path`/`package.cpath`, load `rimeapi`, and run on any of
`luajit`/`lua`/`lua5.x` found in `PATH`. The `rimeapi_lua` shared library and
`librime` must be findable from the script directory or the current working
directory.

### `rimeapi.app.lua` — REPL and script runner

```sh
./rimeapi.app.lua                 # start the interactive REPL
./rimeapi.app.lua script.lua a b  # run script.lua with arguments a b
./rimeapi.app.lua some/dir/       # run some/dir/init.lua
```

- With no arguments it starts a REPL; `Ctrl-C`/`Ctrl-D` exits.
- With a script path it executes that script inside the rimeapi environment and
  forwards the remaining arguments through `arg` (`arg[1]` is the script).
- With a directory it runs the `init.lua` inside it.
- REPL errors show the failing line and a caret for syntax errors.

### `test.lua` — test harness

```sh
./lua test.lua -h                          # list modules under scripts/
./lua test.lua api_test levers_api_test    # run one or more script modules
RIMEAPI_TEST_USER_DIR=/tmp/rime ./lua test.lua api_test
```

- Modules are loaded from `scripts/<name>.lua`.
- Each process uses a unique temporary user-data directory; override it with
  `RIMEAPI_TEST_USER_DIR`.
- Runs the same on `lua` and `luajit`.

### `rime_api_console.lua` — interactive librime console

```sh
./rime_api_console.lua [user_data_dir] [log_dir] [shared_data_dir]
```

Defaults are `./user`, `./log`, and `./shared` next to the script. Most input is
sent to the session as a Rime key sequence, with these special commands:

- `select schema <id>`
- `set option <name>` / `set option !<name>` (prefix `!` to turn it off)
- `select candidate <n>`, `delete <n>`, `delete on current page <n>` (`n` is 1-based)
- `print candidate list`, `print schema list`
- `synchronize` (sync user data)
- `reload` (finalize, reload the script), `exit`

The prompt shows a live schema/status header and an IDE-style completion menu;
see [Interactive completion menu](#interactive-completion-menu) for its keys.

### `schema_tester.lua` — declarative schema testing

```sh
./schema_tester.lua [config.lua]
```

Runs the test groups defined under `deploy` in `schema_tester_config.lua` (or a
config file passed as the first argument). A config returns a table with:

- `schema_id`, `user_data_dir`, `shared_data_dir` (optional), `log_dir` (optional)
- `deploy`: a map of group name to `{ options, properties, patch, tests }`
- each test: `{ send = 'key_sequence', run = 'lua expr' or fn,
  assert = 'lua expr' or fn, options = {...}, properties = {...} }`

`send` simulates a key sequence; after each key the `run` script runs and the
`assert` script is evaluated. `ctx`, `status`, `commit`, and `cand` are exposed,
plus any option/property names listed in `options`/`properties`. `patch` applies
`{ key = ..., value = ... }` lines to the schema (e.g. `engine/translators = []`)
for the duration of the group. Config values may be strings or functions.

For LLM-assisted authoring, see the skill in
[`skills/schema-tester/SKILL.md`](skills/schema-tester/SKILL.md).

### `rime_deployer.lua` — deploy user data

```sh
./rime_deployer.lua [user_data_dir] [shared_data_dir] [staging_dir]
```

Runs librime maintenance (deploy) and writes built files to
`user_data_dir/build`, or to `staging_dir` when given. With no arguments it
prints usage.

### `get-rime.ps1` — fetch librime binaries (Windows/macOS)

```powershell
pwsh ./get-rime.ps1 -h
pwsh ./get-rime.ps1 -tag latest -use toy
```

- `-tag`: release tag such as `1.11.2`, or `latest` for nightly builds
- `-os`: `Windows` or `macOS` (defaults to the running system)
- `-build_variant`: `msvc`/`clang`/`mingw` on Windows, `universal` on macOS
- `-use`: `toy` (plain libs), `dev` (build Weasel), or `weasel` (update an existing Weasel)
- `-extract`: `$true` to extract archives (requires `7z` in `PATH`)
- `-proxy`: e.g. `http://host:port`; a GitHub mirror can be set in `~/.git-rime.conf.ps1`

## Interactive completion menu

`rime_api_console.lua` uses an in-process line editor with an IDE-style
completion menu when a completion catalog is supplied. The menu works on Unix
terminals, Windows Terminal/ConHost with VT processing, and ANSI-capable
consoles such as mintty. When VT/ANSI output is unavailable the editor degrades
to inline suggestions.

- `Tab`: open the menu, accept the highlighted item, or accept a single match
- `Up` / `Down` or `Ctrl-P` / `Ctrl-N`: move the selection
- `PageUp` / `PageDown`: jump a page in the menu (history when closed)
- `Enter`: accept the highlighted item; press again to submit the line
- `Esc`: close the menu
- `Right`: accept the selected item at the end of the line

Completion items are `{ text = ..., display = ..., detail = ..., kind = ... }`
tables (plain strings are still accepted). `kind` selects the menu marker:
`key` for Rime key sequences, `command` for console commands.

`readline` also accepts an optional header block (6th argument). The console
passes the current schema/status line, which is rendered above the prompt and
is redrawn together with the completion menu.

## Credits

- [librime](https://github.com/rime/librime) (The 3-Clause BSD License) RIME: Rime Input Method Engine
- [librime-lua](https://github.com/hchunhui/librime-lua) (The 3-Clause BSD License) librime-lua: Extending RIME with Lua scripts. The lua binding codes is a mod from it.
- [lua](https://www.lua.org/) (The MIT License) Lua: Powerful, efficient, lightweight, embeddable scripting language.
- [luajit](https://luajit.org/) (The MIT License) LuaJIT: Just-In-Time Compiler for Lua.
