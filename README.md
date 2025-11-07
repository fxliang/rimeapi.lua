# rimeapi.lua: a lua API module for librime

## Overview
This module provides a set of functions to interact with the Rime Input Method Engine, allowing users to reference **librime api**, **librime levers** api related functionalities programmatically.

## Build Instructions
To build the shared library, xmake is required. Follow these steps:

- install `xmake` or `cmake`, `git`, and compiler tools for your system
- clone the repository
- install `librime` for linux/macos, or prepare librime libs in `lib` or `lib64` and headers in `include` for windows/macos
- build the shared library for lua binding with `xmake` or `cmake`, if you want.
- if your are to use this module in luajit, make sure lua is static linked in librime-lua for MacOS/termux, because `RTLD_DEEPBIND` is not supported in these platforms.
- to run tests, run `lua test.lua api_test levers_api_test`, or `luajit test.lua api_test levers_api_test`

## Files Description

- `rimeapi.lua`: a lua module for automatically loading shared library or ffi module, for lua/luajit
- `rimeapi_ffi.lua`: a luajit ffi binding module just like `rimeapi_lua.so`/`rimeapi_lua.dll`/`rimeapi_lua.dylib`
- shared libraries for lua binding:
  - `rimeapi_lua.so`: for linux
  - `rimeapi_lua.dylib`: for macos
  - `rimeapi_lua.dll`: for windows
- `scripts/api_test.lua`: a rime api test script
- `scripts/levers_api_test.lua`: a rime levers api test script
- `shared`: base yamls from `librime` project, and a yaml `api_test.yaml`
- `rimeapi.app.lua`: a lua/luajit script, work as a REPL when no extra args passed, or run test scripts when args passed
- `rime_api_console.lua`: a lua script to work like `rime_api_console` of `librime`
- `get-rime.ps1`: a powershell script tool for getting `librime` for windows/macos

## Credites

- [librime](https://github.com/rime/librime) RIME: Rime Input Method Engine
- [librime-lua](https://github.com/hchunhui/librime-lua) librime-lua: Extending RIME with Lua scripts. The lua binding codes is a mod from it.
