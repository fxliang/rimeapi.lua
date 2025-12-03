-------------------------------------------------------------------------------
-- get absolute path of current script
local function script_path()
  local fullpath = debug.getinfo(1,"S").source:sub(2)
  local dirname, filename
  if package.config:sub(1,1) == '\\' then
    local dirname_, filename_ = fullpath:match('^(.*\\)([^\\]+)$')
    if not dirname_ then dirname_ = '.' end
    if not filename_ then filename_ = fullpath end
    local command = 'cd ' .. dirname_ .. ' && cd'
    local p = io.popen(command)
    fullpath = p and (p:read("*l") .. '\\' .. filename_) or ''
    if p then p:close() end
    fullpath = fullpath:gsub('[\n\r]*$','')
    dirname, filename = fullpath:match('^(.*\\)([^\\]+)$')
  else
    local p = io.popen("realpath '"..fullpath.."'", 'r')
    fullpath = p and p:read('a') or ''
    if p then p:close() end
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
package.path = script_path() .. div .. '?.lua' .. ';' .. package.path
local rmdir = function(path)
  if package.config:sub(1,1) == '\\' then
    os.execute('rd /s /q "' .. path .. '"')
  else
    os.execute('rm -rf "' .. path .. '"')
  end
end

if not RimeApi then require('rimeapi') end
local cp = set_console_codepage(65001)
local function assert_exit(cond, msg)
  if not cond then
    set_console_codepage(cp)
    error(msg)
  end
end

local function get_execution_dir()
  local os_name = package.config:sub(1, 1) == "\\" and "windows" or "unix"
  local cmd = os_name == "windows" and "cd"  or "pwd"
  local handle = io.popen(cmd)
  assert_exit(handle ~= nil, "Failed to get current working directory")
  local cwd = handle:read("*l"):gsub("\r?\n", "")
  handle:close()
  return cwd .. div
end

local exec_dir = resolve_path(get_execution_dir())
local script_dir = resolve_path(script_path())
-------------------------------------------------------------------------------
local config = require('schema_tester_config')
assert_exit(config ~= nil, "Failed to load schema_tester_config.lua")
if type(arg[1]) == 'string' and file_exists(arg[1]) then
  local config_chunk, load_err = loadfile(arg[1])
  assert_exit(config_chunk, 'Failed to load config file: ' .. tostring(load_err))
  config = config_chunk()
  assert_exit(type(config) == 'table', 'Config file must return a table')
end
local function resolve_config_path(path, fallback)
  if path and (path:sub(1,1) ~= '/' and path:sub(1,1) ~= ':') then
    return exec_dir .. div .. path
  else
    return script_dir .. div .. fallback -- if not set, use script dir relative path with fallback
  end
end
config.shared_data_dir = resolve_config_path(config.shared_data_dir, 'shared')
config.user_data_dir = resolve_config_path(config.user_data_dir, 'schema_tester')
config.log_dir = resolve_config_path(config.log_dir, 'log')
print('Using shared_data_dir: ' .. tostring(config.shared_data_dir))
print('Using user_data_dir: ' .. tostring(config.user_data_dir))
print('Using log_dir: ' .. tostring(config.log_dir))
print('Using schema_id: ' .. tostring(config.schema_id or 'luna_pinyin'))
print()
-------------------------------------------------------------------------------
local schema_id = config.schema_id or 'luna_pinyin'
local unpack = table.unpack or unpack
local function pack(...)
  return { n = select('#', ...), ... }
end

local function call_with_env(fn, env, ...)
  if type(fn) ~= 'function' then return fn(...) end
  local restore
  if type(setfenv) == 'function' then
    local old_env = getfenv(fn)
    setfenv(fn, env)
    restore = function() setfenv(fn, old_env) end
  elseif type(debug) == 'table' and debug.getupvalue then
    local i = 1
    while true do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == '_ENV' then
        debug.setupvalue(fn, i, env)
        restore = function() debug.setupvalue(fn, i, value) end
        break
      end
      i = i + 1
    end
  end
  local results = pack(pcall(fn, ...))
  if restore then restore() end
  if not results[1] then error(results[2]) end
  return unpack(results, 2, results.n)
end

local function inject_config_functions(env)
  if type(config) ~= 'table' then return end
  for name, value in pairs(config) do
    if type(value) == 'function' then
      env[name] = function(...)
        return call_with_env(value, env, ...)
      end
    end
  end
end

-------------------------------------------------------------------------------
local rime_api = RimeApi()
local traits = RimeTraits()
local session = nil

-------------------------------------------------------------------------------
local function init_session()
  rime_api:initialize(traits)
  if rime_api:start_maintenance(true) then rime_api:join_maintenance_thread() end
  session = rime_api:create_session()
  assert_exit(session ~= nil)
  assert_exit(rime_api:select_schema(session, schema_id) == true,
    "Failed to select schema: " .. tostring(schema_id))
end
-------------------------------------------------------------------------------
local function init()
  traits.app_name = "schema_tester"
  traits.shared_data_dir = config.shared_data_dir or (script_path() .. "shared")
  traits.user_data_dir = config.user_data_dir or (script_path() .. "schema_test")
  traits.prebuilt_data_dir = config.shared_data_dir
  traits.distribution_name = "rimeapi"
  traits.distribution_code_name = "rimeapi"
  traits.distribution_version = "1.0.0"
  traits.log_dir = config.log_dir or (script_path() .. "log")
  if not os.mkdir then
    -- check system is windows or unix-like
    local is_windows = package.config:sub(1, 1) == '\\'
    local mkdir_cmd = is_windows and "md " or "mkdir -p "
    os.execute(mkdir_cmd .. traits.shared_data_dir)
    os.execute(mkdir_cmd .. traits.user_data_dir)
    os.execute(mkdir_cmd .. traits.log_dir)
  else
    assert_exit(os.mkdir(traits.shared_data_dir) == true)
    assert_exit(os.mkdir(traits.user_data_dir) == true)
    assert_exit(os.mkdir(traits.log_dir) == true)
  end
  rime_api:setup(traits)
  init_session()
end

-------------------------------------------------------------------------------
local function finalize()
  if not session then return end
  rime_api:cleanup_all_sessions()
  rime_api:finalize()
  session = nil
end
-------------------------------------------------------------------------------
-- Main function: Calculate the display width of a string
---@param ambiguous_is_wide boolean defaults to true (treat ambiguous characters as wide)
---@param s string The input string
local function eaw_display_width(s, ambiguous_is_wide)
  -- East Asian display width helpers (UAX #11 inspired)
  -- Check if it is a Combining Mark - width is 0
  local function is_combining_mark(u)
    return (u >= 0x0300 and u <= 0x036F) or
    (u >= 0x1AB0 and u <= 0x1AFF) or
    (u >= 0x1DC0 and u <= 0x1DFF) or
    (u >= 0x20D0 and u <= 0x20FF) or
    (u >= 0xFE20 and u <= 0xFE2F)
  end

  -- Check if it is a Wide or Fullwidth character - width is 2
  local function is_wide_or_fullwidth(u)
    -- Basic Multilingual Plane (BMP)
    if (u >= 0x1100 and u <= 0x115F) or (u >= 0x2329 and u <= 0x232A) or
      (u >= 0x2E80 and u <= 0xA4CF) or (u >= 0xAC00 and u <= 0xD7A3) or
      (u >= 0xF900 and u <= 0xFAFF) or (u >= 0xFE10 and u <= 0xFE19) or
      (u >= 0xFE30 and u <= 0xFE6F) or (u >= 0xFF00 and u <= 0xFF60) or
      (u >= 0xFFE0 and u <= 0xFFE6) then
      return true
    end
    -- SIP (Supplementary Ideographic Plane)
    if (u >= 0x20000 and u <= 0x2FFFD) or (u >= 0x30000 and u <= 0x3FFFD) or
      (u >= 0x2F800 and u <= 0x2FA1F) then
      return true
    end
    -- Emojis & Symbols
    if (u >= 0x1F300 and u <= 0x1F64F) or (u >= 0x1F680 and u <= 0x1F6FF) or
      (u >= 0x1F900 and u <= 0x1F9FF) or (u >= 0x1FA70 and u <= 0x1FAFF) or
      (u >= 0x1F1E6 and u <= 0x1F1FF) then
      return true
    end
    return false
  end

  -- Check if it is an Ambiguous character - width may be 1 or 2 depending on context
  local function is_ambiguous_eaw(u)
    -- Greek
    if (u >= 0x0391 and u <= 0x03A1) or (u >= 0x03A3 and u <= 0x03A9) or
      (u >= 0x03B1 and u <= 0x03C1) or (u >= 0x03C3 and u <= 0x03C9) then
      return true
    end
    -- Cyrillic common subset
    if u == 0x0401 or (u >= 0x0410 and u <= 0x044F) or u == 0x0451 then
      return true
    end
    -- Punctuation & Symbols
    if (u >= 0x2010 and u <= 0x2016) or (u >= 0x2018 and u <= 0x2019) or
      (u >= 0x201C and u <= 0x201D) or (u >= 0x2020 and u <= 0x2022) or
      (u >= 0x2024 and u <= 0x2027) or u == 0x2030 or
      (u >= 0x2032 and u <= 0x2033) or u == 0x2035 or u == 0x203B or u == 0x203E then
      return true
    end
    if u == 0x20AC then return true end -- Euro sign
    -- Arrows
    if (u >= 0x2190 and u <= 0x2199) or u == 0x21D2 or u == 0x21D4 then
      return true
    end
    -- Box Drawing, Block Elements, Shapes
    if (u >= 0x2460 and u <= 0x24E9) or (u >= 0x2500 and u <= 0x257F) or
      (u >= 0x2580 and u <= 0x259F) or (u >= 0x25A0 and u <= 0x25FF) or
      (u >= 0x2600 and u <= 0x267F) or (u >= 0x2680 and u <= 0x26FF) or
      (u >= 0x2700 and u <= 0x27BF) or (u >= 0x2B50 and u <= 0x2B59) then
      return true
    end
    return false
  end
  if ambiguous_is_wide == nil then ambiguous_is_wide = true end

  local width = 0
  local i = 1
  local len = #s
  local byte = string.byte
  -- with continue statement, lua 5.2+ or LuaJIT is required
  while i <= len do
    local c = byte(s, i)
    local cp = 0
    local char_len = 0
    -- UTF-8 decoding
    if c < 0x80 then
      cp = c
      char_len = 1
    elseif c >= 0xC0 and c < 0xE0 then -- 2 bytes: 110xxxxx
      if i + 1 > len then width = width + 1; i = i + 1; goto continue end
      local c2 = byte(s, i + 1)
      cp = ((c % 32) * 64) + (c2 % 64)
      char_len = 2
    elseif c >= 0xE0 and c < 0xF0 then -- 3 bytes: 1110xxxx
      if i + 2 > len then width = width + 1; i = i + 1; goto continue end
      local c2 = byte(s, i + 1)
      local c3 = byte(s, i + 2)
      cp = ((c % 16) * 4096) + ((c2 % 64) * 64) + (c3 % 64)
      char_len = 3
    elseif c >= 0xF0 and c < 0xF8 then -- 4 bytes: 11110xxx
      if i + 3 > len then width = width + 1; i = i + 1; goto continue end
      local c2 = byte(s, i + 1)
      local c3 = byte(s, i + 2)
      local c4 = byte(s, i + 3)
      cp = ((c % 8) * 262144) + ((c2 % 64) * 4096) + ((c3 % 64) * 64) + (c4 % 64)
      char_len = 4
    else
      -- Invalid sequence fallback, treat as single byte
      width = width + 1
      i = i + 1
      goto continue
    end
    i = i + char_len
    -- Width determination logic
    if is_combining_mark(cp) then
      -- Width is 0, do nothing
    elseif is_wide_or_fullwidth(cp) or (ambiguous_is_wide and is_ambiguous_eaw(cp)) then
      width = width + 2
    else
      width = width + 1
    end
    ::continue::
  end
  return width
end
-------------------------------------------------------------------------------
local function test_func()
  init()
  if (session == nil) then set_console_codepage(cp) end
  assert_exit(session ~= nil, "Session is not initialized")
  local ctx = RimeContext()
  local status = RimeStatus()
  local commit = RimeCommit()

  local set_env = function (values, kind)
    if not values then return nil end
    local ret = {}
    local setter = (kind == 'option') and rime_api.set_option or rime_api.set_property
    local getter = (kind == 'option') and rime_api.get_option or rime_api.get_property
    for k, v in pairs(values) do
      ret[k] = getter(rime_api, session, k)
      setter(rime_api, session, k, v)
      local new_value = getter(rime_api, session, k)
      assert_exit(new_value == v, 'Failed to set ' .. kind .. ': ' .. k)
    end
    return ret
  end

  local function colormsg(msg, color)
    if div == '\\' then
      local color_code = { red = 0x04, green = 0x02, blue = 0x01,
        yellow = 0x06, magenta = 0x05, cyan = 0x03, white = 0x07,
      }
      set_console_color(color_code[color] or 0x07)
      io.write(msg)
      set_console_color(0x07)
      return
    end
    local default_tty_text_color = '\27[0m'
    local color_code = {
      red = '\27[31m', green = '\27[32m', yellow = '\27[33m',
      blue = '\27[34m', magenta = '\27[35m', cyan = '\27[36m',
      white = '\27[37m',
    }
    local color_prefix = color_code[color] or default_tty_text_color
    io.write(color_prefix .. msg .. default_tty_text_color)
  end

  -- send key sequence and return candidates, update ctx, status, commit
  local send = function(id, keys)
    assert_exit(rime_api:simulate_key_sequence(id, keys) ~= nil, 'Failed to send key sequence: ' .. keys)
    assert_exit(rime_api:get_context(session, ctx) ~= nil, 'Failed to get context')
    assert_exit(rime_api:get_status(session, status) ~= nil, "Failed to get status")
    assert_exit(rime_api:get_commit(session, commit) ~= nil, "Failed to get commit")
    return ctx.menu.candidates
  end
  local load_chunk = function(expr, env)
    if type(expr) == 'function' then return true, call_with_env(expr, env) end
    local chunk, load_err
    if _VERSION == 'Lua 5.1' or type(setfenv) == 'function' then
      chunk, load_err = load('return ' .. expr, '=(assert)')
      assert_exit(chunk, 'Failed to compile assert: ' .. tostring(load_err))
      setfenv(chunk, env)
    else
      chunk, load_err = load('return ' .. expr, '=(assert)', 't', env)
      assert_exit(chunk, 'Failed to compile assert: ' .. tostring(load_err))
    end
    if not chunk then return false, nil end
    return pcall(chunk)
  end
  local run_chunk = function(expr, env)
    if type(expr) == 'function' then return true, call_with_env(expr, env) end
    local chunk, load_err
    if _VERSION == 'Lua 5.1' or type(setfenv) == 'function' then
      chunk, load_err = load(expr, '=(assert)')
      assert_exit(chunk, 'Failed to compile run: ' .. tostring(load_err))
      setfenv(chunk, env)
    else
      chunk, load_err = load(expr, '=(assert)', 'bt', env)
      assert_exit(chunk, 'Failed to compile run: ' .. tostring(load_err))
    end
    if not chunk then return false end
    return pcall(chunk)
  end
  local sync_env = function(env, keys, kind)
    if type(keys) ~= 'table' or type(kind) ~= 'string' or session == nil then return end
    local getter = (kind == 'option') and rime_api.get_option or rime_api.get_property
    for _, key in pairs(keys) do
      if type(key) == 'string' then env[key] = getter(rime_api, session, key) end
    end
  end
  local get_func_name = function (func_chunk)
    local info = debug.getinfo(func_chunk, 'S')
    local function extract_function_name_robust(content)
      local result_names = {}
      -- Remove multi-line comments --[[ ... ]]
      -- Explanation:
      -- %-%-%[(=*)%[ : Matches "--[" followed by any number of "=" and then "[" (captures the number of "=")
      -- (.-)         : Non-greedy match for the content in between
      -- %]%1%]       : Matches "]" followed by the captured number of "=" and then "]"
      -- This pattern is compatible with both --[[ ]] and --[=[ ]=] styles
      local clean_code = content:gsub("%-%-%[(=*)%[(.-)%]%1%]", " ")
      -- Remove single-line comments -- ... (until end of line)
      clean_code = clean_code:gsub("%-%-[^\r\n]*", " ")
      -- Normalize whitespace (replace newlines with spaces to facilitate cross-line matching)
      clean_code = clean_code:gsub("[\r\n]+", " ")
      -- Match "local name = function"
      for name in clean_code:gmatch("local%s+([%w_]+)%s*=%s*function") do
        table.insert(result_names, name)
      end
      -- Match "function name()" (covers both global and local function name() syntax)
        for name in clean_code:gmatch("function%s+([%w_]+)%s*%(") do
          table.insert(result_names, name)
        end
        -- Match "name = function" (global variable assignment form, optional)
        -- Note: This might incorrectly match table field assignments like t.a = function. 
        -- If you only want pure variable names, you might need to add start-of-word constraints.
        for name in clean_code:gmatch("%s([%w_]+)%s*=%s*function") do
          -- Avoid duplicates (if deduplication is needed)
          local exists = false
          for _, v in ipairs(result_names) do if v == name then exists = true break end end
          if not exists and name ~= "local" then
            table.insert(result_names, name)
          end
        end
        return result_names
      end
      local function read_lines(filename, start_line, end_line)
        if start_line < 1 then start_line = 1 end
        if end_line < start_line then return nil, "End line must be greater than or equal to start line" end
        local file, err = io.open(filename, "r")
        if not file then return nil, "Failed to open file: " .. tostring(err) end
        local lines = {}
        local current_line_num = 0
        for line in file:lines() do
          current_line_num = current_line_num + 1
          if current_line_num >= start_line then table.insert(lines, line) end
          if current_line_num >= end_line then break end
        end
        file:close()
        if current_line_num < start_line then return "" end
        return table.concat(lines, "\n")
      end
      local source_content = read_lines(info.source:sub(2), info.linedefined, info.lastlinedefined)
      local function_names = extract_function_name_robust(source_content)
      local src = info.source:match("([^/\\]+)$")
      if #function_names > 0 then
        return '  ' .. table.concat(function_names, ', ') .. '@' .. src .. ':' .. info.linedefined
      end
      return ''
  end
  local run_tests = function(tests)
    if not tests then return end
    -- run each test
    local col1, col2, col3 = {}, {}, {}
    local w1, w2, w3 = 0, 0, 0
    local function add_row(s1, s2, s3)
      w1 = math.max(w1, eaw_display_width(s1))
      w2 = math.max(w2, eaw_display_width(s2))
      w3 = math.max(w3, eaw_display_width(s3))
      table.insert(col1, s1)
      table.insert(col2, s2)
      table.insert(col3, s3)
    end
    add_row('  send', '  assert', '  result\n')
    local with_failures = false
    for _, v_test in ipairs(tests) do
      local cand = send(session, v_test['send'])
      if v_test['assert'] then
        -- Evaluate the assertion expression in a sandbox that exposes local values
        local env = setmetatable({ cand = cand, ctx = ctx, status = status, commit = commit }, { __index = _G })
        sync_env(env, v_test['properties'], 'property')
        sync_env(env, v_test['options'], 'option')
        inject_config_functions(env)
        local _, result = load_chunk(v_test['assert'], env)
        local s1, s2, s3 = '  ' .. v_test['send'], '  ' .. tostring(v_test['assert']),
          result == true and '  passed\n' or '  failed\n'
        if type(v_test['assert']) == 'function' then
          s2 = get_func_name(v_test['assert'])
        end
        with_failures = with_failures or (not result)
        add_row(s1, s2, s3)
      end
      rime_api:clear_composition(session)
    end
    return { col1 = col1, col2 = col2, col3 = col3, w1 = w1, w2 = w2, w3 = w3, with_failures = with_failures }
  end
  local dry_run = function(tests, k_deploy)
    if not tests then return end
    local has_run = false
    for _, v_test in ipairs(tests) do
      if v_test['run'] then has_run = true break end
    end
    if not has_run then return end
    colormsg('  Running deployment dry run: ' .. k_deploy .. '...\n', 'cyan')
    for _, v_test in ipairs(tests) do
      local cand = send(session, v_test['send'])
      if v_test['run'] then
        local env = setmetatable({ cand = cand, ctx = ctx, status = status, commit = commit }, { __index = _G })
        sync_env(env, v_test['properties'], 'property')
        sync_env(env, v_test['options'], 'option')
        inject_config_functions(env)
        local func_name = type(v_test['run']) == 'function' and get_func_name(v_test['run']) or tostring(v_test['run'])
        colormsg('  send: \"' .. v_test['send'] .. '\", run: '.. func_name)
        run_chunk(v_test['run'], env)
      end
      rime_api:clear_composition(session)
    end
    colormsg('  done.\n', 'green')
  end
  -- deploy patch
  local function deploy_patch(patch_lines)
    if not patch_lines then return end
    finalize()
    local levers = RimeLeversApi()
    local settings = levers:custom_settings_init(schema_id, 'schema_tester.lua')
    assert_exit(levers:load_settings(settings) ~= nil, 'Failed to load settings')
    for _, line in pairs(patch_lines) do
      assert_exit(type(line) == 'table' and line.key ~= nil and line.value ~= nil,
        'Invalid patch line: ' .. tostring(line))
      local patch = RimeConfig()
      assert_exit(rime_api:config_load_string(patch, line.value) == true,
        'Failed to load config from string: ' .. tostring(line.value))
      assert_exit(levers:customize_item(settings, line.key, patch) == true,
        'Failed to customize item: ' .. tostring(line.key))
      assert_exit(levers:save_settings(settings) == true, 'Failed to save settings')
    end
    levers:custom_settings_destroy(settings)
    init_session()
  end
  -- remove patch, and update workspace
  local remove_patch = function(patch_lines)
    if not patch_lines then return end
    local filepath = traits.user_data_dir .. '/' .. schema_id .. '.custom.yaml'
    if not file_exists(filepath) then return end
    finalize()
    os.remove(filepath)
    init_session()
  end

  local results = {}
  local w1, w2, w3 = 0, 0, 0
  for k_deploy, v_deploy in pairs(config.deploy) do
    colormsg('  Running deployment assertion: ' .. k_deploy .. '...', 'cyan')
    if not session then init_session() end
    -- deploy patch if any
    deploy_patch(v_deploy['patch'])
    -- set options and properties
    local opts = set_env(v_deploy['options'], 'option')
    local props = set_env(v_deploy['properties'], 'property')
    -- run tests
    local ret = run_tests(v_deploy['tests'])
    assert_exit(ret, 'Failed to run tests for deployment: ' .. k_deploy)
    local done_color = ret.with_failures and 'red' or 'green'
    local done_msg = ret.with_failures and ' done (with failures).\n' or ' done.\n'
    colormsg(done_msg, done_color)
    w1 = math.max(w1, ret.w1)
    w2 = math.max(w2, ret.w2)
    w3 = math.max(w3, ret.w3)
    table.insert(results, { title = k_deploy, result = ret })
    -- dry run if v_deploy['tests'] has run field
    dry_run(v_deploy['tests'], k_deploy)
    -- recover options and properties to previous values
    set_env(opts, 'option')
    set_env(props, 'property')
    -- remove patch if any
    remove_patch(v_deploy['patch'])
    -- clean userdb
    local userdb = traits.user_data_dir .. div .. schema_id .. '.userdb'
    if file_exists(userdb) then
      finalize()
      rmdir(to_acp_path(userdb))
    end
  end
  print(string.rep('-', w1 + w2 + w3))
  print('Assertion Test Details:')
  local ok = true
  for _, v in ipairs(results) do
    for i = 1, #v.result.col1 do
      local is_header = (i == 1)
      if is_header then
        local header = (v.title or 'default')
        local padding = math.floor((w1 + w2 + w3 - eaw_display_width(header)) / 2)
        local ext = (w1 + w2 + w3 - eaw_display_width(header)) % 2
        colormsg(string.rep('-', padding) .. header .. string.rep('-', padding + ext) .. '\n', 'yellow')
      end
      local row_color1 = is_header and 'yellow' or 'blue'
      local row_color2 = is_header and 'yellow' or 'magenta'
      local result_color = is_header and 'yellow' or (v.result.col3[i]:find('passed') and 'green' or 'red')
      if ok and result_color == 'red' then ok = false end
      colormsg(v.result.col1[i] .. string.rep(' ', w1 - eaw_display_width(v.result.col1[i])) , row_color1)
      colormsg(v.result.col2[i] .. string.rep(' ', w2 - eaw_display_width(v.result.col2[i])) , row_color2)
      colormsg(v.result.col3[i] .. string.rep(' ', w3 - eaw_display_width(v.result.col3[i])) , result_color)
      if is_header then colormsg(string.rep('-', w1 + w2 + w3) .. '\n', 'yellow') end
    end
  end
  if ok then print() else colormsg('\n', 'red') end
  assert_exit(ok, 'Some tests failed')
  finalize()
end
-------------------------------------------------------------------------------
test_func()
