# C++ / Lua interop

This directory contains the language binding code. It depends on Lua and the C++
standard library; it does not include Rime headers, load librime, or use the line
editor. Both the Rime module and the component tests link the `lua_interop` target.

| Header | Responsibility |
| --- | --- |
| `state.h` | Lua state ownership, references, calls and coroutine entry points |
| `types.h` | Stack conversions, userdata identity and C++ function wrappers |
| `object.h` | Value/shared object access, member access and owner retention |
| `export.h` | Register constructors, methods and properties |
| `std_optional.h`, `boost_optional.h` | Optional conversion adapters |

`LuaType<T>` is the conversion extension point. Value userdata holds a C++ copy.
For `std::shared_ptr<T>`, that copy is a shared reference: collecting the Lua
wrapper only destroys its reference. Application resource cleanup belongs in
the shared pointer's deleter, and runs after the last C++ or Lua owner releases
it. `push_owner_uservalue` can retain an owner for value userdata that references
external storage. Raw references and raw pointers require the application to
keep the pointee alive.

C string reads borrow Lua-managed string storage. Applications must copy strings
before retaining them beyond their Lua lifetime, and must not modify Lua string
storage. The `char*` adapter is retained for existing C API compatibility.

The default `Lua` constructor retains the existing convenience environment:
standard libraries plus the `Set` and `yield` helpers. To use an environment
controlled by the caller, use `Lua(existing_state, {false, false})`, or
`Lua(nullptr, {false, false})` for a new minimal state. Internal coroutine setup
does not require standard libraries or mutate `table.unpack`. An external state
is borrowed and is never closed by its wrapper.

Only one thread may access a given Lua state at a time. Identity checks protect
normal conversions and reject forged object metatables; the component is not a
sandbox for unrestricted modification of the Lua registry or native finalizers.

Build and test the component without building any Rime code:

```sh
cmake -S . -B build-interop -DRIMEAPI_BUILD_BINDINGS=OFF -DBUILD_TESTING=ON
cmake --build build-interop
ctest --test-dir build-interop --output-on-failure
```

With xmake, build/run `lua_lifetime_test` and `lua_object_test`. The latter checks
conversions across translation units, properties, methods, custom deleters and
retained owners. `rime_ownership_test` separately checks the business-side
factories using a fake Rime API, without loading librime. Full Lua API and Levers
suites remain integration tests for the Rime module.

Rime's ABI initialization and resource policies are in `src/rime_resources.h`;
Rime-specific conversions and API registration remain in `src/main.cpp`.
