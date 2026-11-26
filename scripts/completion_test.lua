-- Run with: ./lua test.lua completion_test (or ./luajit test.lua completion_test)
local completion = require('rimeapi_completion')
local constructor = RimeApi
local callbacks = 0
local inherited = { method = function() end, field = 42 }
setmetatable(inherited, { __index = inherited })
local environment = {
  RimeApi = RimeApi,
  math = math,
  api = RimeApi(),
  traits = RimeTraits(),
  config = RimeConfig(),
  levers = RimeLeversApi(),
  object = setmetatable({ own = true }, {
    __index = function() callbacks = callbacks + 1; error('unexpected getter') end,
    __pairs = function() callbacks = callbacks + 1; error('unexpected iterator') end,
    __tostring = function() callbacks = callbacks + 1; error('unexpected tostring') end,
  }),
  inherited = setmetatable({}, { __index = inherited }),
  nested = { inner = { leaf = true } },
  ['bad-name'] = true,
}
environment._G = environment

local function catalog()
  local items, previous = {}, ''
  for _, item in ipairs(completion.build_lua(environment)) do
    assert(item.text > previous, 'completions must be unique and sorted')
    assert(item.kind == 'lua')
    items[item.text] = item
    previous = item.text
  end
  return items
end

local items = catalog()
for _, text in ipairs({
  'function', 'local', 'nil', 'return', 'RimeApi', 'math.sin',
  'api.get_version', 'api:get_version', 'api:config_begin_list',
  'traits.shared_data_dir', 'traits.app_name', 'config:get_string',
  'levers:load_settings', 'object.own', 'inherited.field', 'inherited:method',
  'nested.inner.leaf',
}) do
  assert(items[text], 'missing completion: ' .. text)
end
assert(not items['traits:app_name'], 'fields must not be offered as methods')
assert(not items['api._c'], 'FFI internals must stay out of the catalog')
assert(not items['bad-name'], 'only Lua identifiers can be completed')
assert(not items['_G._G'], 'global cycles must not be traversed')
assert(callbacks == 0, 'completion must not call user metamethods')
assert(RimeApi == constructor, 'annotations must not overwrite constructors')

environment.added = { value = true }
environment.api = nil
items = catalog()
assert(items['added.value'], 'new globals must appear on the next prompt')
assert(not items['api:get_version'], 'removed globals must leave the catalog')
assert(callbacks == 0)

local large = {}
for i = 1, 4100 do large['key' .. i] = i end
local bounded = {}
for _, item in ipairs(completion.build_lua({ a = large, print = print, z = { member = true } })) do
  bounded[item.text] = true
end
assert(bounded.print and bounded['z.member'], 'large tables must not crowd out unrelated names')

local console = {}
for _, item in ipairs(completion.build()) do console[item.text] = true end
assert(console['select schema '] and console['reload'] and console['exit'])
assert(console['{Control+Shift+grave}'])
print('Lua REPL and console completion regressions passed')
