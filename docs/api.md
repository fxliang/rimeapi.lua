# Lua API Guide

English | [简体中文](api.zh-CN.md)

This guide covers the lifecycle and behavior that type annotations alone cannot
describe. The complete class and method signatures are in
[`rimeapi.annotation.lua`](../rimeapi.annotation.lua), which is also the
Lua-language-server reference. This guide intentionally focuses on usage,
ownership, and conventions rather than duplicating that signature list.

## Loading a backend

Require `rimeapi` to select the binding for the current Lua runtime:

```lua
local RimeApi = require('rimeapi')
```

The module selects the native Lua 5.4 binding (`rimeapi_lua`) or the LuaJIT FFI
binding (`rimeapi_ffi`) automatically. Both expose the same high-level API.
Use only one backend in a process: librime has one process-wide notification
handler, so do not load/register both the native binding and `noti_bridge` in
the same process.

The librime shared library and the binding library must be discoverable by the
runtime loader. The repository's standalone scripts add their own directory to
Lua's module paths; applications using `require('rimeapi')` should configure
`package.path`, `package.cpath`, and the native library search path as needed.

## Quick start

This example initializes librime, opens a session, selects a schema, sends a key
sequence, reads the context, then releases the session and finalizes the
service:

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
collectgarbage('collect') -- release the context wrapper before finalizing librime
api:destroy_session(session)
api:finalize()
```

The example assumes `./shared` contains the schema and other shared Rime data.
Create the user and log directories before initialization if the selected
platform/backend does not create them automatically.

## Lifecycle and notifications

The usual service lifecycle is:

1. Create and populate `RimeTraits` with the data directories and application
   metadata.
2. Call `api:setup(traits)`, then `api:initialize(traits)`.
3. Optionally start maintenance with `api:start_maintenance(true)`. If it
   returns `true`, call `api:join_maintenance_thread()` before proceeding.
4. Create one or more sessions. Select a schema for each session before using
   it.
5. Destroy sessions, then call `api:finalize()` when the process is done with
   librime.

`api:set_notification_handler(fn)` registers a process-wide callback receiving
`(context_object, session, msg_type, msg_value)`. The current bindings pass
`nil` for `context_object`. Pass `nil` as the handler to unregister it.
Notifications are queued for Lua delivery; call `api:drain_notifications()` at
safe points in the application to invoke pending callbacks on the Lua thread.
Avoid doing long-running or reentrant librime work inside the callback.

Sessions may be passed as the `RimeSession` value returned by
`create_session()` or as its integer `id`. A destroyed session is no longer
valid. `cleanup_all_sessions()` invalidates all active sessions; use it only
when the application is ready to discard them.

## Objects and ownership

Constructors such as `RimeContext()`, `RimeStatus()`, `RimeCommit()`,
`RimeConfig()`, and `RimeSchemaList()` create wrappers suitable for passing to
the API methods that fill them. The binding owns their native resources and
releases them when the wrapper is collected. Explicit `free_*` methods are
available for deterministic cleanup; after explicitly freeing a resource, do
not use it again. The `get_context`, `get_status`, and `get_commit` methods
release prior contents before filling the wrapper again.

Some returned values are snapshots/copies. In particular, context composition,
menu, and candidates remain readable after a later context read or after the
parent context wrapper is released. Schema-list items returned by
`get_schema_list()` are also copied. Do not assume that this means every pointer
or string from the underlying C API is safe to retain; use the exposed Lua
strings and tables, not native pointers.

For config and iterator APIs, use the matching close/end method when finished
(`config_close`, `config_end`, `candidate_list_end`) if deterministic cleanup
is needed. The binding also cleans up owned wrappers on collection. Do not use
a resource after explicitly closing/ending it.

## API conventions

- Methods use colon syntax, e.g. `api:get_context(session, context)`.
- Methods that fill a struct wrapper generally return a boolean indicating
  success; inspect the wrapper only after success. Optional string/config reads
  may return `nil` when unavailable.
- `RimeMenu.page_no` and `highlighted_candidate_index` are zero-based, while
  `RimeMenu.candidates` is a normal one-based Lua array. Candidate selection,
  highlighting, and deletion methods take zero-based indexes.
- `get_current_schema(session, buffer_size)` and string getters that accept a
  `buffer_size` use a default buffer size when omitted. Increase it when
  expecting long values; a failed/missing value may be `nil`.
- `simulate_key_sequence(session, sequence)` uses librime key notation. Plain
  text such as `nihao` is accepted; named keys and modifiers use braces, for
  example `'{space}'` or `'{Control+space}'`. Key names are librime key names,
  not terminal escape sequences.
- `get_schema_list()` returns the schema list in `list`; its `size` is the
  number of items. The Lua array is one-based even though some librime indexes
  are zero-based.
- `set_option()` and `set_property()` return no value. Read back with
  `get_option()`/`get_property()` if confirmation is needed.
- API members are limited by the librime version available at runtime. Calling
  a member absent from that librime ABI can report that the API is unavailable.

## LuaJIT and platform notes

- LuaJIT uses the FFI binding and `noti_bridge`; native Lua 5.4 uses
  `rimeapi_lua`. Do not register both notification bridges in one process.
- `RTLD_DEEPBIND` is unavailable on macOS and Termux. For LuaJIT on these
  platforms, use a librime-lua build with Lua statically linked. Termux may also
  require hiding librime-lua's Lua symbols; see the patch in the build section
   of the [README](../README.md).
- On Windows, the helper `set_console_codepage(65001)` can switch console I/O to
  UTF-8; restore the previous code page when the application exits.
- `os.mkdir`, `os.isdir`, and `file_exists` are helpers added by the binding.
  Their optional code-page argument is relevant to Windows paths; it defaults
  to UTF-8.

## Further references

- [API type annotations and signatures](../rimeapi.annotation.lua)
- [API integration tests](../scripts/api_test.lua)
- [Levers API integration tests](../scripts/levers_api_test.lua)
- [Command-line tools and schema tester](../README.md#command-line-tools)
- [librime API](https://github.com/rime/librime)
