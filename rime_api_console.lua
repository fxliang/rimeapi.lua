#!/bin/bash
--[[ 2>/dev/null;:
for interpreter in luajit lua lua5.4 lua5.3 lua5.2 lua5.1; do
  if command -v "$interpreter" >/dev/null 2>&1; then
    exec "$interpreter" "$0" "$@"
  fi
done
echo "错误: 未找到任何 Lua 解释器 (luajit, lua, lua5.x)" >&2
exit 1
]]

-------------------------------------------------------------------------------
-- get absolute path of current script
local function script_path()
  local fullpath = debug.getinfo(1,"S").source:sub(2)
  local dirname, filename
  local is_windows = package.config:sub(1,1) == '\\'
  local sep = is_windows and '\\' or '/'
  if is_windows then
    if not fullpath:match('^%a:[/\\]') and not fullpath:match('^[/\\]') then
      local pwd = os.getenv("CD") or os.getenv("PWD") or "."
      fullpath = pwd .. sep .. fullpath
    end
  else
    if fullpath:sub(1,1) ~= '/' then
      local pwd = os.getenv("PWD") or "."
      fullpath = pwd .. sep .. fullpath
    end
  end
  local prefix = ''
  local root_parts = 0
  local rooted = false
  if is_windows then
    local drive = fullpath:match('^(%a:)[/\\]')
    if drive then
      prefix, fullpath, rooted = drive .. sep, fullpath:sub(4), true
    elseif fullpath:match('^[/\\][/\\]') then
      prefix, fullpath, root_parts, rooted = sep .. sep, fullpath:gsub('^[/\\]+', ''), 2, true
    elseif fullpath:match('^[/\\]') then
      prefix, fullpath, rooted = sep, fullpath:gsub('^[/\\]+', ''), true
    end
    fullpath = fullpath:gsub('/', '\\')
  elseif fullpath:sub(1,1) == '/' then
    prefix, fullpath, rooted = '/', fullpath:gsub('^/+', ''), true
  end
  local parts = {}
  for part in fullpath:gmatch(is_windows and '[^\\]+' or '[^/]+') do
    if part == '..' then
      if #parts > root_parts and parts[#parts] ~= '..' then parts[#parts] = nil
      elseif not rooted then parts[#parts + 1] = part end
    elseif part ~= '.' and part ~= '' then
      parts[#parts + 1] = part
    end
  end
  fullpath = prefix .. table.concat(parts, sep)
  dirname, filename = fullpath:match(is_windows and '^(.*\\)([^\\]+)$' or '^(.*/)([^/]-)$')
  dirname = dirname or ''
  filename = filename or fullpath
  return dirname
end
if not RimeApi then
  --- add the so/dll/lua files in cwd to package.cpath
  -- get path divider
  local div = package.config:sub(1,1) == '\\' and '\\' or '/'
  local script_cpath = script_path() .. div .. '?.dll' .. ';' .. script_path() .. div .. '?.dylib'
  .. ';' .. script_path() .. div .. '?.so'
  -- add the ?.so, ?.dylib or ?.dll to package.cpath ensure requiring
  -- you must keep the rime.dll, librime.dylib or librime.so in current search path
  package.cpath = package.cpath .. ';' .. script_cpath
  package.path = script_path() .. div .. '?.lua' .. ';' .. package.path
  require('rimeapi')
end
-------------------------------------------------------------------------------
local base_dir = script_path()

local function print_usage()
  print("Usage: lua rime_api_console.lua [user_data_dir] [log_dir] [shared_data_dir]")
  print("Defaults: " .. base_dir .. "/user " .. base_dir .. "/log " .. base_dir .. "/shared")
end

if arg[1] == "-h" or arg[1] == "--help" then
  print_usage()
  os.exit(0)
end

local user_data_dir = arg[1] or (base_dir .. "/user")
local log_dir = arg[2] or (base_dir .. "/log")
local shared_data_dir = arg[3] or (base_dir .. "/shared")

local completion = require('rimeapi_completion')
local cp
if package.config:sub(1, 1) == '\\' then
  cp = set_console_codepage() -- set codepage to UTF-8, and return the original codepage
  print("switched console codepage:", 65001, "from", cp)
end
local api = RimeApi()

-- message handler
-- @param _ any not used
-- @param session RimeSession|integer
-- @param msg_type string
-- @param msg_value string
-- @return nil
local function on_message(_, session, msg_type, msg_value)
  local BIT = jit and ((require('ffi').sizeof('void*') == 8) and 16 or 8) or ((string.packsize('T') == 8) and 16 or 8)
  -- session_id format
  local PFORMAT = "%0" .. BIT .. "X"
  local msg = "lua > message: ["..PFORMAT.."] [%s] %s"
  local session_id = session
  print('lua > [ '.. tostring(session) .. ' ] ' .. msg_type .. ': ' .. msg_value)
  if msg_type == "option" then
    local state = msg_value:sub(1, 1) ~= "!"
    local option_name = state and msg_value or msg_value:sub(2)
    local state_label = api:get_state_label(session_id, option_name, state)
    if state_label and state_label ~= "" then
      print(string.format("lua > updated option: %s = %s // %s", option_name, state, state_label))
    end
  end
end

-- init function
-- @return nil
-- @usage call api:setup, api:initialize, api:start_maintenance，api:set_notification_handler
local function init()
  local traits = RimeTraits()
  print('initializing...')
  traits.app_name = "rime_api_console.lua"
  traits.shared_data_dir = shared_data_dir
  traits.user_data_dir = user_data_dir
  traits.prebuilt_data_dir = shared_data_dir
  traits.distribution_name = "rime_api_console"
  traits.distribution_code_name = "rime_api_console"
  traits.distribution_version = "1.0.0"
  traits.log_dir = log_dir
  -- print(traits)
  if not os.mkdir then
    -- check system is windows or unix-like
    local is_windows = package.config:sub(1, 1) == '\\'
    local mkdir_cmd = is_windows and "md " or "mkdir -p "
    local function q(s)
      if is_windows then
        if s:find('[%%!&|<>%^()"\r\n]') then error("unsupported character in Windows path") end
        return '"' .. s .. '"'
      end
      return "'" .. s:gsub("'", "'\\''") .. "'"
    end
    os.execute(mkdir_cmd .. q(traits.shared_data_dir))
    os.execute(mkdir_cmd .. q(traits.user_data_dir))
    os.execute(mkdir_cmd .. q(traits.log_dir))
  else
    os.mkdir(traits.shared_data_dir)
    os.mkdir(traits.user_data_dir)
    os.mkdir(traits.log_dir)
  end
  api:setup(traits)
  api:set_notification_handler(on_message)
  api:initialize(traits)
  if api:start_maintenance(true) then
    api:join_maintenance_thread()
  end
  api:drain_notifications()
end
--- build the one-line status header shown above the prompt
--- @param st RimeStatus
--- @return string|nil
local function status_header(st)
  if not st then return nil end
  local flags = {}
  if st.is_disabled == true then flags[#flags + 1] = "disabled" end
  if st.is_composing == true then flags[#flags + 1] = "composing" end
  if st.is_ascii_mode == true then flags[#flags + 1] = "ascii_mode" end
  if st.is_full_shape == true then flags[#flags + 1] = "full_shape" end
  if st.is_simplified == true then flags[#flags + 1] = "simplified" end
  local state = #flags > 0 and table.concat(flags, " ") or "ready"
  return string.format("schema: %s / %s  [%s]",
    st.schema_id or "?", st.schema_name or "?", state)
end

--- print composition preedit with selection and cursor
--- @param comp RimeComposition
--- @return nil
local function print_composition(comp)
  local preedit = comp.preedit
  if not preedit or preedit == "" then
    return
  end
  local len = #preedit + 1
  local start = comp.sel_start + 1
  local end_ = comp.sel_end + 1
  local cursor = comp.cursor_pos + 1
  local msg = ""
  for i = 1, len + 1 do
    if start < end_ then
      if i == start then msg = msg .. "["
      elseif i == end_ then msg = msg .. "]"
      end
    end
    if i == cursor then msg = msg .. "|" end
    if i < len then msg = msg .. preedit:sub(i, i) end
  end
  print(msg)
end

--- print candidate menu
--- @param menu RimeMenu
--- @return nil
local function print_menu(menu)
  if menu.num_candidates == 0 then return end
  print(string.format("page: %d%s (of size %d)",
    menu.page_no + 1,
    menu.is_last_page == true and "$" or " ",
    menu.page_size))
  for i = 1, menu.num_candidates do
    local highlight = (i - 1) == menu.highlighted_candidate_index
    print(string.format("%d. %s%s%s%s", i,
      highlight and "[" or " ",
      menu.candidates[i].text,
      highlight and "] " or " ",
      menu.candidates[i].comment ~= "" and menu.candidates[i].comment or ""))
  end
end

--- print context info
--- @param ctx RimeContext
--- @return nil
local function print_context(ctx)
  if ctx.composition.length > 0 or ctx.menu.num_candidates > 0 then
    print_composition(ctx.composition)
  else
    print("(not composing)")
  end
  print_menu(ctx.menu)
end

--- RimeCommit instance
--- @type RimeCommit
local commit = RimeCommit()
--- RimeContext instance
--- @type RimeContext
local context = RimeContext()
--- RimeStatus instance
--- @type RimeStatus
local status = RimeStatus()

--- print session info
--- @param session_id RimeSession|integer
--- @return nil
local function print_session(session_id)
  if api:get_commit(session_id, commit) then
    print("Commit text:", commit.text)
  end
  if api:get_context(session_id, context) then
    print_context(context)
  end
end

--- execute special commands
--- @param input string
--- @return boolean true if executed, false otherwise
local function execute_special_command(session_id, input)
  if input:match("^select schema ") then
    local schema_id = input:sub(15)
    print("select schema: ", schema_id)
    if not api:select_schema(session_id, schema_id) then
      print("cannot select schema: " .. schema_id)
    end
    return true
  elseif input:match("^set option ") then
    local value = input:sub(12)[1]~='!'
    print("set option ", input:sub(12), value and "on" or "off")
    api:set_option(session_id, input:sub(12), value)
    return true
  elseif input:match("^select candidate ") then
    local index = tonumber(input:sub(18))
    print("select candidate " .. tostring(index) .. " [indexed from 1]")
    if not api:select_candidate(session_id, index - 1) then
      print("cannot select candidate " .. tostring(index))
    else
      print_session(session_id)
    end
    return true
  elseif input:match("^print candidate list") then
    if api:get_context(session_id, context) then
      if context.menu.num_candidates == 0 then print("no candidates")
      else print_menu(context.menu) end
    else
      print("failed to get context")
    end
    return true
  elseif input:match("^delete on current page ") then
    local index = tonumber(input:sub(24))
    print("delete on current page", index)
    if not api:delete_candidate_on_current_page(session_id, index - 1) then
      print("failed to delete index " .. tostring(index) .. " on current page")
    else print_session(session_id) end
    return true
  elseif input:match("^delete ") then
    local index = tonumber(input:sub(8))
    print("delete "..tostring(index).." [indexed from 1]")
    if not api:delete_candidate(session_id, index - 1)  then
      print("failed to delete index " .. tostring(index))
    else print_session(session_id) end
    return true
  elseif input == "print schema list" then
    local lst = RimeSchemaList()
    if api:get_schema_list(lst) then
      for i = 1, lst.size do print(lst.list[i].schema_id, lst.list[i].name) end
    end
    return true
  elseif input == "synchronize" then
    print("synchronizing user data...")
    if not api:sync_user_data() then
      print("failed to synchronize user data")
    end
    return true
  end
  return false
end

--- continue flag
local continue = true
--- main loop
--- @return nil
local function main()
  init()
  local session_id = api:create_session()
  if not api:select_schema(session_id, "luna_pinyin") then
    print("Failed to select schema luna_pinyin")
  end
  local str = api:get_current_schema(session_id, 256)
  api:drain_notifications()
  if not str then
    print("Failed to get current schema")
  else
    print("Current schema:", str)
  end
  local session_id_alive = session_id ~= nil
  print("ready")
  print("---------------------------------------------")

  local history = {}
  local prompt = '> '

  while continue do
    local header = nil
    local schema_id = nil
    if api:get_status(session_id, status) then
      header = status_header(status)
      schema_id = status.schema_id
    end
    local completions = completion.build(api, schema_id)
    local input = readline(prompt, history, nil, nil, completions, header)
    if input == nil then
      break
    elseif input == '' then
      -- ignore truly empty submissions while allowing whitespace
    else
      local trimmed = input:gsub('%s+', '')
      if trimmed ~= '' then history[#history + 1] = input end
      if input == "exit" then
        continue = false
        break
      elseif input == "reload" then
        api:destroy_session(session_id)
        print("distroying session..." .. tostring(session_id))
        session_id_alive = false
        api:finalize()
        input = ""
        api:drain_notifications()
        -- reload current file
        dofile(debug.getinfo(1,'S').source:sub(2))
        continue = false
      end
      if not execute_special_command(session_id, input) then
        if api:simulate_key_sequence(session_id, input) then print_session(session_id) end
      end
    end
    api:drain_notifications()
  end
  if session_id_alive then
    print("distroying session..." .. session_id.str)
    api:destroy_session(session_id)
  end
  api:finalize()
end

main()
if package.config:sub(1, 1) == '\\' and cp then
  local cpu = set_console_codepage(cp)
  print("restored console codepage:", cp, "from", cpu)
end
