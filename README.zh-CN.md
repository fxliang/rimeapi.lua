# rimeapi.lua: 面向 librime 的 Lua API 模块

[English](README.md) | 简体中文

## 概述

本模块提供了一组用于操作 Rime 输入法引擎（librime）的函数，让你可以在脚本中以编程方式使用 **librime api** 与 **librime levers** api 的相关能力。

每个进程只应使用一种绑定后端。librime 的 notification handler 是进程级唯一的，因此原生的 `rimeapi_lua` 与 LuaJIT 的 `noti_bridge` 不能同时注册。

初始化、生命周期、资源管理和 API 行为约定见 [Lua API 使用指南](docs/api.zh-CN.md)；
完整签名见 [`rimeapi.annotation.lua`](rimeapi.annotation.lua)。

## 构建说明

构建共享库可使用 xmake 或 CMake。可按以下步骤操作（也可参考 `./.github/workflows/ci.yml` 中的流程）：

C++/Lua 互操作组件也可以脱离 librime 单独构建与测试：在 CMake 中使用 `-DRIMEAPI_BUILD_BINDINGS=OFF -DBUILD_TESTING=ON`。其所有权约定、初始化选项和测试命令见[组件文档](src/interop/README.md)。

- 安装 `xmake` 或 `cmake`、`git` 以及对应系统的编译工具链
- 克隆仓库并初始化子模块：`git submodule update --init --recursive`
- Linux/macOS 安装 `librime`；Windows 需将 librime 的库放到 `lib`/`lib64`，头文件放到 `include`
- 使用 `xmake` 或 `cmake` 构建
- 运行 `./lua test.lua api_test levers_api_test` 或 `luajit test.lua api_test levers_api_test`；测试框架会为每个进程创建独立的测试 user-data 目录
- 如需显式指定测试数据目录，将 `RIMEAPI_TEST_USER_DIR` 设为可写目录
- 若在 LuaJIT 中使用本模块，在 macOS/termux 上需确保 librime-lua 中的 lua 为静态链接，因为这些平台不支持 `RTLD_DEEPBIND`。在 termux 上还可能需要从 librime 中隐藏 lua 符号，可应用下面这个针对 librime-lua 的补丁：
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

## 文件说明

- `rimeapi.lua`：加载原生 Lua 5.4 后端或 LuaJIT FFI 后端的 lua 模块
- `rimeapi_ffi.lua`：LuaJIT FFI 绑定模块，作用等同于 `rimeapi_lua.so`/`rimeapi_lua.dll`/`rimeapi_lua.dylib`
- lua 绑定的共享库：
  - `rimeapi_lua.so`：Linux
  - `rimeapi_lua.dylib`：macOS
  - `rimeapi_lua.dll`：Windows
- luajit 绑定的共享库：
  - `noti_bridge.so`：Linux
  - `noti_bridge.dylib`：macOS
  - `noti_bridge.dll`：Windows
- `scripts/api_test.lua`：rime api 测试脚本
- `scripts/levers_api_test.lua`：rime levers api 测试脚本
- `shared`：来自 `librime` 项目的基础 yaml，以及 `api_test.yaml`
- `rimeapi.app.lua`：Lua 5.4/LuaJIT 脚本；无参数时作为 REPL，带参数时运行测试脚本
- `rimeapi_completion.lua`：readline 补全目录，包含 Rime 命名按键与常用组合键
- `rime_api_console.lua`：行为类似 `librime` 自带 `rime_api_console` 的 lua 脚本
- `get-rime.ps1`：用于在 Windows/macOS 获取 `librime` 的 PowerShell 脚本
- `schema_tester.lua`：用于测试 rime 方案的 lua 脚本示例
- `schema_tester_config.lua`：`schema_tester.lua` 的配置文件

## 命令行工具

以下工具均为自包含脚本。它们会把当前目录加入 `package.path`/`package.cpath`，加载 `rimeapi`，并自动使用 `PATH` 中任一可用的 `luajit`/`lua`/`lua5.x` 运行。`rimeapi_lua` 共享库与 `librime` 必须能从脚本目录或当前工作目录找到。

### `rimeapi.app.lua` —— REPL 与脚本运行器

```sh
./rimeapi.app.lua                 # 启动交互式 REPL
./rimeapi.app.lua script.lua a b  # 以参数 a b 运行 script.lua
./rimeapi.app.lua some/dir/       # 运行 some/dir/init.lua
```

- 无参数时启动 REPL；`Ctrl-C`/`Ctrl-D` 退出。
- 传入脚本路径时，在 rimeapi 环境中执行该脚本，其余参数通过 `arg` 传入（`arg[1]` 为脚本本身）。
- 传入目录时，运行其中的 `init.lua`。
- REPL 报错会显示出错行号；语法错误还会用 `^` 标出位置。

### `test.lua` —— 测试运行器

```sh
./lua test.lua -h                          # 列出 scripts/ 下的模块
./lua test.lua api_test levers_api_test    # 运行一个或多个脚本模块
RIMEAPI_TEST_USER_DIR=/tmp/rime ./lua test.lua api_test
```

- 模块从 `scripts/<name>.lua` 加载。
- 每个进程使用独立的临时 user-data 目录；可用 `RIMEAPI_TEST_USER_DIR` 覆盖。
- 在 `lua` 与 `luajit` 下行为一致。

### `rime_api_console.lua` —— 交互式 librime 控制台

```sh
./rime_api_console.lua [user_data_dir] [log_dir] [shared_data_dir]
```

默认目录为脚本旁的 `./user`、`./log`、`./shared`。大部分输入会作为 Rime 按键序列发送给会话，另有以下特殊命令：

- `select schema <id>`
- `set option <name>` / `set option !<name>`（前缀 `!` 表示关闭）
- `select candidate <n>`、`delete <n>`、`delete on current page <n>`（`n` 从 1 开始）
- `print candidate list`、`print schema list`
- `synchronize`（同步用户数据）
- `reload`（finalize 并重新加载脚本）、`exit`

提示符上方会显示实时的 scheme/状态头部，并提供 IDE 风格的补全菜单；按键说明见[交互式补全菜单](#交互式补全菜单)。

### `schema_tester.lua` —— 声明式方案测试

```sh
./schema_tester.lua [config.lua]
```

运行 `schema_tester_config.lua`（或作为第一个参数传入的配置文件）中 `deploy` 下定义的所有测试组。配置文件返回一个表，包含：

- `schema_id`、`user_data_dir`、`shared_data_dir`（可选）、`log_dir`（可选）
- `deploy`：组名到 `{ options, properties, patch, tests }` 的映射
- 每个测试：`{ send = 'key_sequence', run = 'lua 表达式' 或函数,
  assert = 'lua 表达式' 或函数, options = {...}, properties = {...} }`

`send` 模拟按键序列；每个按键之后执行 `run` 脚本并求值 `assert`。环境中可用 `ctx`、`status`、`commit`、`cand`，以及在 `options`/`properties` 中列出的选项/属性名。`patch` 会在该组测试期间向方案应用 `{ key = ..., value = ... }` 形式的补丁（例如 `engine/translators = []`）。配置中的值可以是字符串或函数。

如需借助 LLM 生成测试配置，可参考 [`skills/schema-tester/SKILL.md`](skills/schema-tester/SKILL.md)。

### `rime_deployer.lua` —— 部署用户数据

```sh
./rime_deployer.lua [user_data_dir] [shared_data_dir] [staging_dir]
```

执行 librime 的维护（部署）流程，构建产物输出到 `user_data_dir/build`；若提供 `staging_dir` 则输出到该目录。无参数时打印用法。

### `get-rime.ps1` —— 获取 librime 二进制（Windows/macOS）

```powershell
pwsh ./get-rime.ps1 -h
pwsh ./get-rime.ps1 -tag latest -use toy
```

- `-tag`：发布标签，如 `1.11.2`；`latest` 表示每日构建
- `-os`：`Windows` 或 `macOS`（默认为当前系统）
- `-build_variant`：Windows 下为 `msvc`/`clang`/`mingw`，macOS 下为 `universal`
- `-use`：`toy`（普通库），`dev`（构建 Weasel）或 `weasel`（更新已有 Weasel）
- `-extract`：设为 `$true` 解压压缩包（需要 `PATH` 中有 `7z`）
- `-proxy`：如 `http://host:port`；GitHub 镜像可在 `~/.git-rime.conf.ps1` 中配置

## 交互式补全菜单

`rime_api_console.lua` 在提供补全目录时，会使用进程内的行编辑器并显示 IDE 风格的补全菜单。该菜单支持 Unix 终端、开启了 VT 处理的 Windows Terminal/ConHost，以及 mintty 等支持 ANSI 的控制台。当 VT/ANSI 输出不可用时，编辑器会退化为行内建议。

- `Tab`：打开菜单、接受高亮项，或接受唯一匹配项
- `Up` / `Down` 或 `Ctrl-P` / `Ctrl-N`：移动选择
- `PageUp` / `PageDown`：菜单中翻页（菜单关闭时为历史记录）
- `Enter`：接受高亮项；再次按下则提交该行
- `Esc`：关闭菜单
- `Right`：在行尾接受选中项

补全项为 `{ text = ..., display = ..., detail = ..., kind = ... }` 形式的表（仍兼容纯字符串）。`kind` 决定菜单标记：`key` 表示 Rime 按键序列，`command` 表示控制台命令。

`readline` 还接受一个可选的头部块（第 6 个参数）。控制台会传入当前的 schema/状态行，该内容渲染在提示符上方，并与补全菜单一起重绘。

## 致谢

- [librime](https://github.com/rime/librime)（The 3-Clause BSD License）RIME：Rime 输入法引擎
- [librime-lua](https://github.com/hchunhui/librime-lua)（The 3-Clause BSD License）librime-lua：用 Lua 脚本扩展 RIME，本项目的 lua 绑定代码部分改编自它
- [lua](https://www.lua.org/)（The MIT License）Lua：强大、高效、轻量的嵌入式脚本语言
- [luajit](https://luajit.org/)（The MIT License）LuaJIT：Lua 即时编译器
