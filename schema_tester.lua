-- get absolute path of current script
local function script_path()
  local fullpath = debug.getinfo(1,"S").source:sub(2)
  local dirname, filename
  if package.config:sub(1,1) == '\\' then
    local dirname_, filename_ = fullpath:match('^(.*\\)([^\\]+)$')
    local currentDir = io.popen("cd"):read("*l")
    if not dirname_ then dirname_ = '.' end
    if not filename_ then filename_ = fullpath end
    local command = 'cd ' .. dirname_ .. ' && cd'
    local p = io.popen(command)
    fullpath = p:read("*l") .. '\\' .. filename_
    p:close()
    os.execute('cd ' .. currentDir)
    fullpath = fullpath:gsub('[\n\r]*$','')
    dirname, filename = fullpath:match('^(.*\\)([^\\]+)$')
  else
    fullpath = io.popen("realpath '"..fullpath.."'", 'r'):read('a')
    fullpath = fullpath:gsub('[\n\r]*$','')
    dirname, filename = fullpath:match('^(.*/)([^/]-)$')
  end
  dirname = dirname or ''
  filename = filename or fullpath
  return dirname
end
-- get path divider
local div = package.config:sub(1,1) == '\\' and '\\' or '/'
local script_cpath = script_path() .. div .. '?.dll' .. ';' .. script_path() .. div .. '?.dylib'
.. ';' .. script_path() .. div .. '?.so'
-- add the ?.so, ?.dylib or ?.dll to package.cpath ensure requiring
-- you must keep the rime.dll, librime.dylib or librime.so in current search path or pwd
package.cpath = package.cpath .. ';' .. script_cpath
package.path = package.path .. ';' .. script_path() .. div .. '?.lua'

-------------------------------------------------------------------------------
local config = require('schema_tester_config')
assert(config ~= nil, "Failed to load schema_tester_config.lua")
local schema_id = config.schema_id or 'luna_pinyin'
if not RimeApi then require('rimeapi') end

-------------------------------------------------------------------------------
local rime_api = RimeApi()
local traits = RimeTraits()
local session = nil

-------------------------------------------------------------------------------
local function init()
  traits.app_name = "schema_tester"
  traits.shared_data_dir = "shared"
  traits.user_data_dir = config.user_data_dir or "schema_test"
  traits.prebuilt_data_dir = config.shared_data_dir or "shared"
  traits.distribution_name = "rimeapi"
  traits.distribution_code_name = "rimeapi"
  traits.distribution_version = "1.0.0"
  traits.log_dir = "log"
  if not os.mkdir then
    -- check system is windows or unix-like
    local is_windows = package.config:sub(1, 1) == '\\'
    local mkdir_cmd = is_windows and "md " or "mkdir -p "
    os.execute(mkdir_cmd .. traits.shared_data_dir)
    os.execute(mkdir_cmd .. traits.user_data_dir)
    os.execute(mkdir_cmd .. traits.log_dir)
  else
    assert(os.mkdir(traits.shared_data_dir) == true)
    assert(os.mkdir(traits.user_data_dir) == true)
    assert(os.mkdir(traits.log_dir) == true)
  end
  rime_api:setup(traits)
  rime_api:initialize(traits)
  if rime_api:start_maintenance(true) then rime_api:join_maintenance_thread() end
  session = rime_api:create_session()
  assert(session ~= nil)
  assert(rime_api:select_schema(session, schema_id) == true,
    "Failed to select schema: " .. tostring(schema_id))
end

-------------------------------------------------------------------------------
local function finalize()
  rime_api:cleanup_all_sessions()
  rime_api:finalize()
end

-------------------------------------------------------------------------------
local function test_func()
  init()
  local ctx = RimeContext()
  local set_options = function(options, set)
    if not options then return end
    if set == nil then set = true end
    for k_opt, v_opt in pairs(options) do
      v_opt = set and v_opt or not v_opt
      rime_api:set_option(session, k_opt, v_opt)
      assert(rime_api:get_option(session, k_opt) == v_opt, 'Failed to set option: ' .. k_opt)
    end
  end
  local reset_options = function(options) set_options(options, false) end
  local run_tests = function(tests)
    if not tests then return end
    local send = function(id, keys)
      assert(rime_api:simulate_key_sequence(id, keys), 'Failed to send key sequence: ' .. keys)
      assert(rime_api:get_context(session, ctx), 'Failed to get context')
      return ctx.menu.candidates
    end
    local load_chunk = function(expr, env)
      local chunk, load_err
      if _VERSION == 'Lua 5.1' or type(setfenv) == 'function' then
        chunk, load_err = load('return ' .. expr, '=(assert)')
        assert(chunk, 'Failed to compile assert: ' .. tostring(load_err))
        setfenv(chunk, env)
      else
        chunk, load_err = load('return ' .. expr, '=(assert)', 't', env)
        assert(chunk, 'Failed to compile assert: ' .. tostring(load_err))
      end
      return chunk
    end
    for _, v_tests in pairs(tests) do
      local cand = send(session, v_tests['send'])
      if v_tests['assert'] then
        -- Evaluate the assertion expression in a sandbox that exposes local values
        local env = setmetatable({ cand = cand }, { __index = _G })
        local chunk = load_chunk(v_tests['assert'], env)
        local _, result = pcall(chunk)
        assert(result, 'Assertion failed: ' .. v_tests['assert'])
        print('assertion: ' .. v_tests['assert'] .. ' ... passed')
      end
      rime_api:clear_composition(session)
    end
  end
  local function deploy_patch(patch_lines)
    if not patch_lines then return end
    finalize()
    local levers = RimeLeversApi()
    local settings = levers:custom_settings_init(schema_id, 'schema_tester.lua')
    assert(levers:load_settings(settings) ~= nil, 'Failed to load settings')
    for _, line in pairs(patch_lines) do
      assert(type(line) == 'table' and line.key ~= nil and line.value ~= nil,
        'Invalid patch line: ' .. tostring(line))
      local patch = RimeConfig()
      assert(rime_api:config_load_string(patch, line.value) == true,
        'Failed to load config from string: ' .. tostring(line.value))
      assert(levers:customize_item(settings, line.key, patch) == true,
        'Failed to customize item: ' .. tostring(line.key))
      assert(levers:save_settings(settings) == true, 'Failed to save settings')
    end
    levers:custom_settings_destroy(settings)
    init()
  end
  local remove_patch = function(patch_lines)
    if not patch_lines then return end
    local filepath = traits.user_data_dir .. '/' .. schema_id .. '.custom.yaml'
    os.remove(filepath)
    init()
  end

  for k_deploy, v_deploy in pairs(config.deploy) do
    print("---------------------------------------------------\nTesting:", k_deploy)
    -- deploy patch if any
    deploy_patch(v_deploy['patch'])
    -- set options
    set_options(v_deploy['options'])
    -- run tests
    run_tests(v_deploy['tests'])
    -- recover options to default
    reset_options(v_deploy['options'])
    -- remove patch if any
    remove_patch(v_deploy['patch'])
  end
  finalize()
end
-------------------------------------------------------------------------------
test_func()
