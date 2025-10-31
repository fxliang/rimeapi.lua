# rimeapi.lua: a lua API module for librime

## Overview
This module provides a set of functions to interact with the Rime Input Method Engine, allowing users to reference **librime api**, **librime levers** api related functionalities programmatically.

## Outputs

- `rimeapi.app`/`rimeapi.app.exe`: an app to run rimeapi functions lua scripts, or work as a REPL
- `rimeapi_lua.so`/`rimeapi_lua.dll`/`rimeapi_lua.dylib`: a shared library to be used in other lua scripts

## Build Instructions
To build the shared library, xmake is required. Follow these steps:

- install `xmake`, `git`, and compiler tools for your system
- clone the repository
- install `librime` for linux/macos, or prepare librime libs in `lib` or `lib64` (.lib and .dll) and headers in `include` for windows
- the `rimeapi.app` or `rimeapi.app.exe` will be generated in the project root directory
- if your are to use this module in luajit, make sure lua is static linked in librime-lua for MacOS/termux, because `RTLD_DEEPBIND` is not supported in this platforms.

## Files Description

- `rimeapi.lua`: a lua module for automatically loading shared library or ffi module
- `rimeapi_ffi.lua`: a luajit ffi binding module just like `rimeapi_lua.so`/`rimeapi_lua.dll`/`rimeapi_lua.dylib`
- `scripts/api_test.lua`: a rime api test script, use it `rimeapi.app ./api_test.lua`, temp output will be in `api_test` directory
- `scripts/levers_api_test.lua`: a rime levers api test script, use it `rimeapi.app ./levers_api_test.lua`, temp output will be in `levers_api_test` directory
- `shared`: base yamls from `librime` project, and a yaml `api_test.yaml`
- `rime_api_console.lua`: a lua script to work like `rime_api_console` of `librime`, use it `rimeapi.app ./rime_api_console.lua` or `lua ./rime_api_console.lua`
- `rimeapi.jit.app.lua`: a luajit script to work as a REPL like `rimeapi.app`
- `get-rime.ps1`: a powershell script tool for getting `librime` for windows/macos

## Credites

- [librime](https://github.com/rime/librime) RIME: Rime Input Method Engine
- [librime-lua](https://github.com/hchunhui/librime-lua) librime-lua: Extending RIME with Lua scripts. The lua binding codes is a mod from it.
