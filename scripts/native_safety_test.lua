-- Run with: ./lua test.lua native_safety_test
assert(not jit, "this suite exercises the native Lua binding")

local function rejects(f)
  local ok, err = pcall(f)
  assert(not ok and type(err) == "string", "expected a Lua argument error")
end

local api = RimeApi()
local composition = RimeComposition()
local traits = RimeTraits()
assert(getmetatable(composition) == false)
assert(getmetatable(traits) == false)
traits.app_name = "native-safety"
assert(traits.app_name == "native-safety")
assert(traits.unknown_member == nil)

-- A genuine userdata with another object's metatable must retain its real type.
local original = debug.getmetatable(composition)
debug.setmetatable(composition, debug.getmetatable(traits))
rejects(function() return composition.app_name end)
rejects(function() composition.app_name = "forged" end)
debug.setmetatable(composition, original)
assert(composition.length == 0)

-- Foreign userdata must also be rejected without destroying its own resource.
local file = assert(io.tmpfile())
local file_mt = debug.getmetatable(file)
local candidate_mt = debug.getmetatable(RimeCandidate())
debug.setmetatable(file, candidate_mt)
rejects(function() return file.text end)
candidate_mt.__gc(file)
debug.setmetatable(file, file_mt)
assert(file:write("still open"))
assert(file:close())

-- A manually finalized object cannot be read or destroyed a second time.
local candidate = RimeCandidate()
candidate_mt.__gc(candidate)
candidate_mt.__gc(candidate)
rejects(function() return candidate.text end)

-- Metatable type tags are lightuserdata, never usable as native struct pointers.
rejects(function() return candidate_mt.__tostring(candidate_mt.type) end)
rejects(function() return api:config_next(traits) end)

-- Reference identities must not keep discarded objects alive.
local weak = setmetatable({}, {__mode = "v"})
do
  local object = RimeComposition()
  weak[1] = object
end
collectgarbage("collect")
collectgarbage("collect")
assert(weak[1] == nil)

-- Fractional and non-finite session IDs must fail before reaching librime.
for _, id in ipairs({0.5, math.huge, -math.huge, 0/0}) do
  rejects(function() return api:find_session(id) end)
end

print("native userdata safety regressions passed")
