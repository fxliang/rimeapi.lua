# Lua API 使用指南

[English](api.md) | 简体中文

本指南说明类型注解之外的 API 生命周期和行为约定。完整的类与方法签名见
[`rimeapi.annotation.lua`](../rimeapi.annotation.lua)，它同时也是 Lua Language
Server 的类型参考。本指南侧重用法、资源管理和约定，不重复罗列全部签名。

## 加载后端

使用 `require('rimeapi')`，模块会根据当前 Lua 运行时选择绑定：

```lua
local RimeApi = require('rimeapi')
```

普通 Lua 5.4 使用原生绑定 `rimeapi_lua`，LuaJIT 使用 FFI 绑定
`rimeapi_ffi`。两者提供相同的高层 API。一个进程只能使用一种后端：librime
的 notification handler 是进程级唯一的，不要在同一进程同时加载/注册原生绑定
与 `noti_bridge`。

librime 动态库和绑定库必须能被运行时加载器找到。仓库内的独立脚本会把脚本目录
加入 Lua 模块搜索路径；应用直接调用 `require('rimeapi')` 时，应按需配置
`package.path`、`package.cpath` 和系统动态库搜索路径。

## 快速开始

下面示例初始化 librime、创建会话、选择方案、发送按键序列、读取上下文，最后
销毁会话并结束 librime 服务：

```lua
local RimeApi = require('rimeapi')

local traits = RimeTraits()
traits.app_name = 'rimeapi-example'
traits.shared_data_dir = './shared'
traits.prebuilt_data_dir = './shared'
traits.user_data_dir = './user'
traits.log_dir = './log'
traits.distribution_name = 'rimeapi'
traits.distribution_code_name = 'rimeapi'
traits.distribution_version = '1.0.0'

local api = RimeApi()
api:setup(traits)
api:initialize(traits)

local session = api:create_session()
assert(session and session.id ~= 0, 'failed to create Rime session')
assert(api:select_schema(session, 'luna_pinyin'), 'failed to select schema')
assert(api:simulate_key_sequence(session, 'nihao'), 'failed to process keys')

local context = RimeContext()
assert(api:get_context(session, context), 'failed to read context')
print('preedit:', context.composition.preedit)
for i, candidate in ipairs(context.menu.candidates) do
  print(i, candidate.text, candidate.comment)
end

context = nil
collectgarbage('collect') -- 在 finalize librime 前回收 context 包装对象
api:destroy_session(session)
api:finalize()
```

示例假设 `./shared` 中包含方案和其他共享 Rime 数据。若所用平台/后端不会自动
创建目录，请在初始化前创建 user 与 log 目录。

## 生命周期与通知

常见的服务生命周期如下：

1. 创建并填写 `RimeTraits`，设置数据目录和应用元信息。
2. 依次调用 `api:setup(traits)` 和 `api:initialize(traits)`。
3. 可选地调用 `api:start_maintenance(true)` 启动维护。如果返回 `true`，应调用
   `api:join_maintenance_thread()` 等待维护完成。
4. 创建会话，并在使用前为每个会话选择方案。
5. 不再使用时销毁会话，进程退出前调用 `api:finalize()`。

`api:set_notification_handler(fn)` 注册进程级回调，参数为
`(context_object, session, msg_type, msg_value)`。当前绑定传入的
`context_object` 为 `nil`。传入 `nil` handler 可取消注册。通知会排队等待 Lua
处理；在应用合适的时机调用 `api:drain_notifications()`，回调会在调用该方法的
Lua 线程执行。回调中应避免耗时或重入 librime 的操作。

会话参数既可以是 `create_session()` 返回的 `RimeSession`，也可以是其中的整数
`id`。会话销毁后不可继续使用。`cleanup_all_sessions()` 会使所有活动会话失效，
仅应在应用准备丢弃所有会话时调用。

## 对象与资源管理

`RimeContext()`、`RimeStatus()`、`RimeCommit()`、`RimeConfig()`、
`RimeSchemaList()` 等构造器创建可传给 API 填充的包装对象。原生资源由绑定管理，
包装对象被回收时会释放。需要确定性清理时可调用显式的 `free_*` 方法；释放之后
不要再使用该对象。再次调用 `get_context`、`get_status` 或 `get_commit` 时，绑定
会先释放包装对象中上一次读取的数据，再写入新数据。

部分结果是快照/副本。特别是 context 的 composition、menu 和 candidates，在后续
读取 context 或释放父 context 包装对象后仍可读取。`get_schema_list()` 返回的
schema-list item 也是副本。但不要因此假设 C API 的所有指针或字符串都可长期保存；
请使用绑定暴露的 Lua 字符串和表，不要保留原生指针。

对 config 和 iterator API，如果需要确定性清理，请在使用完毕后调用对应的
close/end 方法（`config_close`、`config_end`、`candidate_list_end`）。绑定也会在
包装对象回收时清理其拥有的资源。显式 close/end 后不要继续使用该资源。

## API 约定

- 方法使用冒号调用，例如 `api:get_context(session, context)`。
- 通常，向结构体包装对象写入数据的方法返回 boolean 表示是否成功；成功后再读取
  对象。可选字符串/config 读取在值不可用时可能返回 `nil`。
- `RimeMenu.page_no` 和 `highlighted_candidate_index` 从 0 开始；
  `RimeMenu.candidates` 是普通的 Lua 数组，从 1 开始。选择、高亮和删除候选的
  API 参数使用从 0 开始的索引。
- `get_current_schema(session, buffer_size)` 及接受 `buffer_size` 的字符串 getter
  在省略参数时使用默认缓冲区大小。预期值较长时应增大缓冲区；读取失败或值缺失时
  可能返回 `nil`。
- `simulate_key_sequence(session, sequence)` 使用 librime 按键记法。可直接传入
  `nihao` 这样的文本；命名键和组合键使用花括号，例如 `'{space}'` 或
  `'{Control+space}'`。键名使用 librime 键名，不是终端转义序列。
- `get_schema_list()` 将方案列表写入 `list`，`size` 表示项目数。Lua 数组仍从 1
  开始，即使部分 librime API 的索引从 0 开始。
- `set_option()` 和 `set_property()` 无返回值。如需确认结果，可用
  `get_option()`/`get_property()` 读回。
- 可用 API 成员取决于运行时 librime 版本。若 ABI 中不存在某成员，调用会报告该
  API 不可用。

## LuaJIT 与平台说明

- LuaJIT 使用 FFI 绑定和 `noti_bridge`；普通 Lua 5.4 使用 `rimeapi_lua`。同一进程
  不要同时注册两个 notification bridge。
- macOS 和 Termux 不支持 `RTLD_DEEPBIND`。在这些平台上用 LuaJIT 时，librime-lua
  需要静态链接 Lua。Termux 还可能需要隐藏 librime-lua 导出的 Lua 符号；参见
  [README 构建说明](../README.md#build-instructions)中的补丁。
- Windows 上 `set_console_codepage(65001)` 可将控制台 I/O 切换为 UTF-8；应用退出时
  应恢复原代码页。
- 绑定提供 `os.mkdir`、`os.isdir` 和 `file_exists` 辅助函数。可选的 code-page 参数
  主要用于 Windows 路径，默认值为 UTF-8。

## 参考

- [API 类型注解与签名](../rimeapi.annotation.lua)
- [API 集成测试](../scripts/api_test.lua)
- [Levers API 集成测试](../scripts/levers_api_test.lua)
- [命令行工具与方案测试器](../README.zh-CN.md#命令行工具)
- [librime API](https://github.com/rime/librime)
