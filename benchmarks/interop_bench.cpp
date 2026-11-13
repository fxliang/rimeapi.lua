#include "export.h"
#include "object.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <functional>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
using Clock = std::chrono::steady_clock;
constexpr size_t batch_size = 256;

void require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

// Lua reports a type tag in osize for fresh allocations, not an old byte size.
struct Allocations {
  size_t live = 0, peak = 0;
  uint64_t calls = 0, requested = 0;

  void reset_interval() { peak = live; calls = requested = 0; }

  static void* allocate(void* context, void* ptr, size_t old_size, size_t size) {
    auto& stats = *static_cast<Allocations*>(context);
    const size_t previous = ptr ? old_size : 0;
    if (size == 0) {
      std::free(ptr);
      stats.live -= previous;
      return nullptr;
    }
    void* result = std::realloc(ptr, size);
    if (result) {
      stats.live = stats.live - previous + size;
      stats.peak = std::max(stats.peak, stats.live);
      ++stats.calls;
      stats.requested += size;
    }
    return result;
  }
};

struct SmallValue { int value = 7; double weight = 1.5; };
struct LargeValue { int value = 7; std::array<unsigned char, 1024> bytes{}; };

int add(int a, int b) { return a + b; }

int raw_add(lua_State* L) {
  lua_Integer a = luaL_checkinteger(L, 1);
  lua_Integer b = luaL_checkinteger(L, 2);
  lua_pushinteger(L, a + b);
  return 1;
}

struct Fixture {
  Allocations allocations;
  lua_State* L = nullptr;
  std::unique_ptr<Lua> state;
  SmallValue small;
  LargeValue large;
  std::shared_ptr<SmallValue> shared = std::make_shared<SmallValue>();
  std::string text = std::string(128, 'x');
  std::array<std::string, 256> strings;
  size_t string_index = 0;
  std::shared_ptr<LuaObj> function;
  int function_ref = LUA_NOREF;
  int raw_loop = LUA_NOREF, wrapped_loop = LUA_NOREF, field_loop = LUA_NOREF, setter_loop = LUA_NOREF;

  Fixture() {
    L = lua_newstate(Allocations::allocate, &allocations);
    require(L != nullptr, "cannot create Lua state");
    try {
      state = std::make_unique<Lua>(L, LuaOptions{true, false});
      const luaL_Reg empty[] = {{nullptr, nullptr}};
      const luaL_Reg getters[] = {
        {"value", LuaInterop::get_member<SmallValue, int, &SmallValue::value>},
        {nullptr, nullptr}};
      const luaL_Reg setters[] = {
        {"value", LuaInterop::set_member<SmallValue, int, &SmallValue::value>},
        {nullptr, nullptr}};
      lua_export_type(L, LuaType<std::shared_ptr<SmallValue>>::type(),
          LuaType<std::shared_ptr<SmallValue>>::gc, empty, empty, getters, setters);
      for (size_t i = 0; i < strings.size(); ++i) {
        strings[i] = text;
        strings[i][1] = static_cast<char>('A' + i % 26);
        strings[i][2] = static_cast<char>('A' + i / 26);
      }
      lua_pushcfunction(L, raw_add);
      lua_setglobal(L, "raw_add");
      lua_pushcfunction(L, WRAP(add));
      lua_setglobal(L, "wrapped_add");
      LuaType<std::shared_ptr<SmallValue>>::pushdata(L, shared);
      lua_setglobal(L, "object");
      const char* source =
          "function add_values(a, b) return a + b end\n"
          "local raw, wrapped, obj = raw_add, wrapped_add, object\n"
          "function raw_loop(n) local sum = 0; for i=1,n do sum=sum+raw(20,22) end; return sum end\n"
          "function wrapped_loop(n) local sum = 0; for i=1,n do sum=sum+wrapped(20,22) end; return sum end\n"
          "function field_loop(n) local sum = 0; for i=1,n do sum=sum+obj.value end; return sum end\n"
          "function setter_loop(n) local sum = 0; for i=1,n do obj.value=7; sum=sum+7 end; return sum end\n";
      if (luaL_dostring(L, source) != LUA_OK)
        throw std::runtime_error(lua_error_message(L));
      function = state->getglobal("add_values");
      function_ref = reference("add_values");
      raw_loop = reference("raw_loop");
      wrapped_loop = reference("wrapped_loop");
      field_loop = reference("field_loop");
      setter_loop = reference("setter_loop");
      // This pre-existing object is used only by the read benchmark.
      LuaType<std::shared_ptr<SmallValue>>::pushdata(L, shared);
    } catch (...) {
      state.reset();
      lua_close(L);
      throw;
    }
  }

  ~Fixture() {
    function.reset();
    state.reset();
    lua_close(L);
    if (allocations.live != 0) std::abort();
  }

  int reference(const char* name) {
    lua_getglobal(L, name);
    return luaL_ref(L, LUA_REGISTRYINDEX);
  }

  void collect() {
    // Identity cleanup guards can require a second collection.
    lua_gc(L, LUA_GCCOLLECT, 0);
    lua_gc(L, LUA_GCCOLLECT, 0);
  }

  size_t loop(int ref, size_t count) {
    lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
    lua_pushinteger(L, static_cast<lua_Integer>(count));
    if (lua_pcall(L, 1, 1, 0) != LUA_OK)
      throw std::runtime_error(lua_error_message(L));
    size_t sum = static_cast<size_t>(luaL_checkinteger(L, -1));
    lua_pop(L, 1);
    return sum;
  }
};

enum class GC { automatic, excluded, included };
struct Case {
  const char* name;
  GC gc;
  size_t expected;
  std::function<size_t(Fixture&, size_t)> run;
};

struct Sample {
  double ns = 0;
  size_t operations = 0, peak_extra = 0;
  uint64_t allocations = 0, requested = 0;
};

Sample measure(Fixture& fixture, const Case& test, size_t operations) {
  fixture.collect();
  Sample result;
  for (size_t done = 0; done < operations;) {
    size_t count = std::min(batch_size, operations - done);
    if (test.gc != GC::automatic) lua_gc(fixture.L, LUA_GCSTOP, 0);
    fixture.allocations.reset_interval();
    size_t initial_live = fixture.allocations.live;
    auto start = Clock::now();
    size_t sum = test.run(fixture, count);
    if (test.gc == GC::included) fixture.collect();
    auto finish = Clock::now();
    result.ns += std::chrono::duration<double, std::nano>(finish - start).count();
    result.allocations += fixture.allocations.calls;
    result.requested += fixture.allocations.requested;
    result.peak_extra = std::max(result.peak_extra, fixture.allocations.peak - initial_live);
    require(sum == count * test.expected, "benchmark returned an incorrect result");
    require(lua_gettop(fixture.L) == 1, "benchmark leaked Lua stack entries");
    if (test.gc != GC::automatic) {
      lua_gc(fixture.L, LUA_GCRESTART, 0);
      if (test.gc == GC::excluded) fixture.collect();
    }
    done += count;
  }
  result.operations = operations;
  fixture.collect();
  return result;
}

std::vector<Case> cases() {
  return {
    {"raw/int-roundtrip", GC::automatic, 7, [](Fixture& f, size_t n) {
      size_t sum = 0;
      for (size_t i=0; i<n; ++i) {
        lua_pushinteger(f.L, 7); sum += luaL_checkinteger(f.L, -1); lua_pop(f.L, 1);
      }
      return sum;
    }},
    {"interop/int-roundtrip", GC::automatic, 7, [](Fixture& f, size_t n) {
      size_t sum = 0;
      for (size_t i=0; i<n; ++i) {
        LuaType<int>::pushdata(f.L, 7); sum += LuaType<int>::todata(f.L, -1); lua_pop(f.L, 1);
      }
      return sum;
    }},
    {"raw/cached-string128", GC::automatic, 'x', [](Fixture& f, size_t n) {
      size_t sum = 0;
      for (size_t i=0; i<n; ++i) {
        lua_pushstring(f.L, f.text.c_str()); sum += luaL_checkstring(f.L, -1)[0]; lua_pop(f.L, 1);
      }
      return sum;
    }},
    {"interop/cached-string128", GC::automatic, 'x', [](Fixture& f, size_t n) {
      size_t sum = 0;
      for (size_t i=0; i<n; ++i) {
        LuaType<std::string>::pushdata(f.L, f.text);
        sum += LuaType<const char*>::todata(f.L, -1)[0]; lua_pop(f.L, 1);
      }
      return sum;
    }},
    {"raw/rotating-string128", GC::automatic, 'x', [](Fixture& f, size_t n) {
      size_t sum = 0;
      for (size_t i=0; i<n; ++i) {
        const auto& text = f.strings[f.string_index++ % f.strings.size()];
        lua_pushstring(f.L, text.c_str()); sum += luaL_checkstring(f.L, -1)[0]; lua_pop(f.L, 1);
      }
      return sum;
    }},
    {"interop/rotating-string128", GC::automatic, 'x', [](Fixture& f, size_t n) {
      size_t sum = 0;
      for (size_t i=0; i<n; ++i) {
        const auto& text = f.strings[f.string_index++ % f.strings.size()];
        LuaType<std::string>::pushdata(f.L, text);
        sum += LuaType<const char*>::todata(f.L, -1)[0]; lua_pop(f.L, 1);
      }
      return sum;
    }},
    {"interop/value-wrap-read-no-gc", GC::excluded, 7, [](Fixture& f, size_t n) {
      size_t sum = 0;
      for (size_t i=0; i<n; ++i) {
        LuaType<SmallValue>::pushdata(f.L, f.small);
        sum += LuaType<SmallValue>::todata(f.L, -1).value; lua_pop(f.L, 1);
      }
      return sum;
    }},
    {"interop/large1024-wrap-read-no-gc", GC::excluded, 7, [](Fixture& f, size_t n) {
      size_t sum = 0;
      for (size_t i=0; i<n; ++i) {
        LuaType<LargeValue>::pushdata(f.L, f.large);
        sum += LuaType<LargeValue>::todata(f.L, -1).value; lua_pop(f.L, 1);
      }
      return sum;
    }},
    {"interop/shared-wrap-read-no-gc", GC::excluded, 7, [](Fixture& f, size_t n) {
      size_t sum = 0;
      for (size_t i=0; i<n; ++i) {
        LuaType<std::shared_ptr<SmallValue>>::pushdata(f.L, f.shared);
        sum += LuaType<std::shared_ptr<SmallValue>>::todata(f.L, -1)->value; lua_pop(f.L, 1);
      }
      return sum;
    }},
    {"interop/shared-wrap-read-auto-gc", GC::automatic, 7, [](Fixture& f, size_t n) {
      size_t sum = 0;
      for (size_t i=0; i<n; ++i) {
        LuaType<std::shared_ptr<SmallValue>>::pushdata(f.L, f.shared);
        sum += LuaType<std::shared_ptr<SmallValue>>::todata(f.L, -1)->value; lua_pop(f.L, 1);
      }
      return sum;
    }},
    {"interop/shared-wrap-read-full-gc", GC::included, 7, [](Fixture& f, size_t n) {
      size_t sum = 0;
      for (size_t i=0; i<n; ++i) {
        LuaType<std::shared_ptr<SmallValue>>::pushdata(f.L, f.shared);
        sum += LuaType<std::shared_ptr<SmallValue>>::todata(f.L, -1)->value; lua_pop(f.L, 1);
      }
      return sum;
    }},
    {"interop/shared-read-existing", GC::automatic, 7, [](Fixture& f, size_t n) {
      size_t sum = 0;
      for (size_t i=0; i<n; ++i) sum += LuaInterop::smart_shared_ptr_todata<SmallValue>(f.L, 1)->value;
      return sum;
    }},
    {"lua/property-read", GC::automatic, 7, [](Fixture& f, size_t n) { return f.loop(f.field_loop, n); }},
    {"lua/property-write", GC::automatic, 7, [](Fixture& f, size_t n) { return f.loop(f.setter_loop, n); }},
    {"interop/reference-roundtrip", GC::automatic, 7, [](Fixture& f, size_t n) {
      size_t sum = 0;
      for (size_t i=0; i<n; ++i) {
        auto reference = LuaObj::todata(f.L, 1);
        LuaObj::pushdata(f.L, reference);
        sum += LuaType<std::shared_ptr<SmallValue>>::todata(f.L, -1)->value;
        lua_pop(f.L, 1);
      }
      return sum;
    }},
    {"lua-to-cpp/raw-checked", GC::automatic, 42, [](Fixture& f, size_t n) { return f.loop(f.raw_loop, n); }},
    {"lua-to-cpp/wrapped", GC::automatic, 42, [](Fixture& f, size_t n) { return f.loop(f.wrapped_loop, n); }},
    {"cpp-to-lua/raw-protected", GC::automatic, 42, [](Fixture& f, size_t n) {
      size_t sum = 0;
      for (size_t i=0; i<n; ++i) {
        lua_rawgeti(f.L, LUA_REGISTRYINDEX, f.function_ref);
        lua_pushinteger(f.L, 20); lua_pushinteger(f.L, 22);
        if (lua_pcall(f.L, 2, 1, 0) != LUA_OK) throw std::runtime_error(lua_error_message(f.L));
        sum += luaL_checkinteger(f.L, -1); lua_pop(f.L, 1);
      }
      return sum;
    }},
    {"cpp-to-lua/interop-protected", GC::automatic, 42, [](Fixture& f, size_t n) {
      size_t sum = 0;
      for (size_t i=0; i<n; ++i) {
        auto value = f.state->call<int>(f.function, 20, 22);
        require(value.ok(), "C++ to Lua call failed");
        sum += value.get();
      }
      return sum;
    }}
  };
}

size_t positive_integer(const char* text) {
  require(*text >= '0' && *text <= '9', "expected a positive integer");
  char* end = nullptr;
  unsigned long long value = std::strtoull(text, &end, 10);
  require(*end == '\0' && value > 0 && value <= 100000000, "integer must be in 1..100000000");
  return static_cast<size_t>(value);
}
} // namespace

int main(int argc, char** argv) {
  try {
    size_t iterations = 0, samples = 7;
    std::string filter;
    bool csv = false;
    for (int i=1; i<argc; ++i) {
      std::string arg = argv[i];
      if (arg == "--csv") csv = true;
      else if (arg == "--help") {
        std::puts("Usage: lua_interop_bench [--iterations N] [--samples N] [--filter TEXT] [--csv]\n"
                  "Default: calibrate each case to about 50 ms of timed work per sample; 7 samples.\n"
                  "Each operation is one conversion/call/read. Batch size is 256; no GC timing thresholds.");
        return 0;
      } else {
        require(i+1 < argc, "missing option value");
        if (arg == "--iterations") iterations = positive_integer(argv[++i]);
        else if (arg == "--samples") {
          samples = positive_integer(argv[++i]);
          require(samples <= 100, "samples must be in 1..100");
        } else if (arg == "--filter") filter = argv[++i];
        else throw std::runtime_error("unknown option: " + arg);
      }
    }
    if (!csv) {
      std::printf("%s | C++17 | batch=%zu | samples=%zu | GC=incremental\n", LUA_RELEASE, batch_size, samples);
#ifndef NDEBUG
      std::puts("Note: assertions are enabled; use a Release build for performance comparisons.");
#endif
      std::puts("Lua alloc/op counts successful allocations and reallocations; native C++ allocations are excluded.");
      std::printf("%-40s %10s %12s %12s %10s %12s %10s\n",
          "case", "ops/sample", "median ns/op", "min ns/op", "alloc/op", "request B/op", "peak +B");
    } else {
      std::puts("case,operations_per_sample,samples,median_ns_per_op,min_ns_per_op,lua_allocations_per_op,lua_requested_bytes_per_op,max_batch_peak_extra_bytes");
    }
    size_t matched = 0;
    for (const auto& test : cases()) {
      if (std::string(test.name).find(filter) == std::string::npos) continue;
      ++matched;
      Fixture fixture;
      lua_gc(fixture.L, LUA_GCINC, 200, 100, 13);
      measure(fixture, test, batch_size * 4); // Warm up metatables, VM stack and allocator.
      size_t count = iterations ? iterations : batch_size;
      if (!iterations) {
        for (;;) {
          auto pilot = measure(fixture, test, count);
          if (pilot.ns >= 40000000.0 || count >= 10000000) break;
          double factor = std::clamp(50000000.0 / std::max(1.0, pilot.ns), 2.0, 10.0);
          count = std::min<size_t>(10000000, static_cast<size_t>(std::ceil(count * factor)));
        }
      }
      std::vector<double> timings;
      uint64_t allocations = 0, requested = 0;
      size_t peak = 0;
      for (size_t sample=0; sample<samples; ++sample) {
        auto result = measure(fixture, test, count);
        timings.push_back(result.ns / result.operations);
        allocations += result.allocations;
        requested += result.requested;
        peak = std::max(peak, result.peak_extra);
      }
      std::sort(timings.begin(), timings.end());
      double median = (timings[(samples-1)/2] + timings[samples/2]) / 2;
      double ops = static_cast<double>(count) * samples;
      if (csv) std::printf("%s,%zu,%zu,%.3f,%.3f,%.6f,%.3f,%zu\n", test.name, count, samples,
          median, timings.front(), allocations/ops, requested/ops, peak);
      else std::printf("%-40s %10zu %12.2f %12.2f %10.3f %12.2f %10zu\n", test.name, count,
          median, timings.front(), allocations/ops, requested/ops, peak);
      std::fflush(stdout);
    }
    require(matched > 0, "filter matched no benchmark cases");
  } catch (const std::exception& error) {
    std::fprintf(stderr, "benchmark failed: %s\n", error.what());
    return 1;
  }
}
