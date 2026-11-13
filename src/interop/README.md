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

## Performance benchmarks

The optional benchmark uses ordinary C++ payloads and the same `lua_interop`
library as the application. It does not load librime. Build an optimized version:

```sh
cmake -S . -B build-bench -DCMAKE_BUILD_TYPE=Release \
  -DRIMEAPI_BUILD_BINDINGS=OFF -DLUA_INTEROP_BUILD_BENCHMARKS=ON
cmake --build build-bench --target lua_interop_bench
./build-bench/src/interop/lua_interop_bench
```

On multi-configuration generators, also pass `--config Release` to the build
command and run the executable in `src/interop/Release/` (`.exe` on Windows).
With xmake:

```sh
xmake f -m release
xmake build lua_interop_bench
xmake run lua_interop_bench
```

The Lua library, interop library and benchmark use release optimization with
both builders. Compare runs made with the same builder, compiler and flags.

By default, each case calibrates to approximately 50 ms of timed work per sample
and reports the median and minimum of seven samples. Each operation is one
round trip, property access or call. Setup, warmup, batch checksum/stack validation
and output are outside timing. A call from a Lua loop includes its loop overhead; raw and
wrapped versions use the same loop. Raw checked C functions are a baseline:
wrapped functions additionally provide the component's protected temporary
cleanup. C++ to Lua baselines use `lua_pcall`; the component also checks reference
lifetime and performs protected result conversion.

Cases cover integer conversion, cached and rotating 128-byte strings, small and
1 KiB value userdata, shared userdata, existing-object reads, properties, registry
references and calls in both directions. Shared pointees and string inputs are
created before timing. String reads borrow Lua storage; they do not copy into
a new `std::string`. The cached-string case deliberately exercises Lua's C API
string cache; rotating prebuilt strings also exercises allocation and GC.

GC uses Lua 5.4 incremental mode with fixed parameters. Object cases distinguish:

- `no-gc`: stop GC for a batch of at most 256 operations, then collect outside
  timing. This bounds temporary memory even with large iteration counts.
- `auto-gc`: include automatic collection during the loop. Final cleanup is
  outside timing, so this is not a complete allocation-to-destruction measurement.
- `full-gc`: include two full collections after every batch, amortized over the
  operations in that batch, to include finalizers and identity-guard cleanup.

`alloc/op` counts successful nonzero Lua allocator calls, including reallocations;
`request B/op` sums their requested sizes. `peak +B` is the largest increase in
Lua live bytes within a timed batch. These metrics exclude C++ heap allocations,
including shared-pointer control blocks and native identity maps. Counting Lua
allocations itself adds overhead to both compared paths.

Use fixed iteration counts or export CSV for comparisons:

```sh
./build-bench/src/interop/lua_interop_bench --iterations 100000 --samples 9
./build-bench/src/interop/lua_interop_bench --filter shared --samples 9
./build-bench/src/interop/lua_interop_bench --iterations 100000 --csv > results.csv
```

CSV is emitted to stdout; errors go to stderr. An unmatched filter or invalid
argument returns a failure status. Each timed batch checks results and stack
balance afterward. When benchmarks and CTest are enabled, a short smoke test runs
all cases with correctness checks and no timing thresholds. Timings vary with CPU
frequency, thermal state and other processes; compare several runs on an idle
device using the same settings, and assess absolute time as well as ratios.
