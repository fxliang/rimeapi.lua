if not RimeApi then
  --- add the so/dll/lua files in cwd to package.cpath
  -------------------------------------------------------------------------------
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
  local div = package.config:sub(1,1) == '\\' and '\\' or '/'
  local script_cpath = script_path() .. div .. '?.dll' .. ';' .. script_path() .. div .. '?.dylib'
  .. ';' .. script_path() .. div .. '?.so'
  -- add the ?.so, ?.dylib or ?.dll to package.cpath ensure requiring
  -- you must keep the rime.dll, librime.dylib or librime.so in current search path
  package.cpath = package.cpath .. ';' .. script_cpath
  package.path = package.path .. ';' .. script_path() .. div .. '?.lua'
  require('rimeapi')
end
-------------------------------------------------------------------------------
local cp
if package.config:sub(1, 1) == '\\' then
  cp = set_console_codepage() -- set codepage to UTF-8, and return the original codepage
  print("switched console codepage:", 65001, "from", cp)
end
local api = RimeApi()

local has_linenoise, linenoise = pcall(require, 'linenoise')
if not has_linenoise then linenoise = nil end

local function shell_ok(cmd)
  local r1, r2, r3 = os.execute(cmd)
  if r1 == true then return true end
  if r1 == nil then return false end
  if r1 == false then return false end
  if type(r1) == 'number' then return r1 == 0 end
  if r2 == 'exit' then return r3 == 0 end
  return false
end

local function has_visible_chars(str) return type(str) == 'string' and str:match('%S') ~= nil end

local function beep()
  io.write('\7')
  io.flush()
end

local function create_posix_line_reader()
  if package.config:sub(1,1) == '\\' then return nil end

  local function is_tty() return shell_ok('test -t 0 >/dev/null 2>&1') end

  local function capture_stty_state()
    local pipe = io.popen('stty -g', 'r')
    if not pipe then return nil end
    local state = pipe:read('*l')
    pipe:close()
    return state
  end

  local function restore_stty(state)
    if state and state ~= '' then shell_ok('stty ' .. state) end
  end

  local function set_raw_mode() return shell_ok('stty -icanon -echo min 1 time 0') end

  return function(prompt, history, opts)
    if not is_tty() then
      io.write(prompt)
      io.flush()
      return io.read('*l')
    end

    local stty_state = capture_stty_state()
    if not stty_state or stty_state == '' then
      io.write(prompt)
      io.flush()
      return io.read('*l')
    end

    if not set_raw_mode() then
      restore_stty(stty_state)
      io.write(prompt)
      io.flush()
      return io.read('*l')
    end

    local function reader_loop()
      io.write(prompt)
      io.flush()
      history = history or {}
      local buffer = {}
      local cursor = 0
      local saved_draft = ''
      local saved_draft_valid = false
      local history_index = #history + 1

      local continuation_prompt = (opts and opts.continuation_prompt) or string.rep(' ', #prompt)
      local last_cursor_row = 1
      local function buffer_length() return #buffer end
      local function current_text() return table.concat(buffer) end
      local function set_buffer(text)
        buffer = {}
        for i = 1, #text do buffer[i] = text:sub(i, i) end
        cursor = #buffer
      end

      local function split_lines(text)
        local lines = {}
        local start_idx = 1
        local len = #text
        if len == 0 then return { '' } end
        while true do
          local nl = text:find('\n', start_idx, true)
          if not nl then
            lines[#lines + 1] = text:sub(start_idx)
            break
          end
          lines[#lines + 1] = text:sub(start_idx, nl - 1)
          start_idx = nl + 1
          if start_idx > len then
            lines[#lines + 1] = ''
            break
          end
        end
        return lines
      end

      local function build_display_lines(text)
        local segments = split_lines(text)
        if #segments == 0 then segments = { '' } end
        local lines = {}
        for i, segment in ipairs(segments) do
          if i == 1 then lines[i] = prompt .. segment
          else lines[i] = continuation_prompt .. segment end
        end
        return lines
      end

      local function build_cursor_lines()
        if cursor == 0 then return { prompt } end
        local prefix = table.concat(buffer, '', 1, cursor)
        return build_display_lines(prefix)
      end

      local function refresh_line()
        local display_lines = build_display_lines(current_text())
        if #display_lines == 0 then display_lines = { prompt } end
        local cursor_lines = build_cursor_lines()
        local target_row = #cursor_lines
        local target_col = #cursor_lines[target_row]

        if last_cursor_row > 1 then io.write(string.format('\27[%dF', last_cursor_row - 1)) end
        io.write('\r\27[J')

        for i, line in ipairs(display_lines) do
          if i > 1 then io.write('\r\n') end
          io.write(line)
          io.write('\27[K')
        end

        local total_lines = #display_lines
        if total_lines < 1 then total_lines = 1 end
        last_cursor_row = target_row

        local lines_up = total_lines - target_row
        if lines_up > 0 then io.write(string.format('\27[%dF', lines_up)) end
        io.write('\r')
        if target_col > 0 then io.write(string.format('\27[%dC', target_col)) end
        io.flush()
      end

      local function history_size() return #history end

      local function at_bottom() return history_index == history_size() + 1 end

      local function break_history_navigation() if not at_bottom() then history_index = history_size() + 1 end end

      local function ensure_saved_draft()
        if saved_draft_valid then return end
        saved_draft = current_text()
        saved_draft_valid = true
      end

      local function pull_history(index)
        set_buffer(history[index] or '')
        refresh_line()
      end

      while true do
        local ch = io.stdin:read(1)
        if not ch then return nil, 'eof' end
        local byte = ch:byte()

        if byte == 13 or byte == 10 then
          if cursor < buffer_length() then
            cursor = buffer_length()
            refresh_line()
          else refresh_line() end
          io.write('\n')
          io.flush()
          return current_text()
        elseif byte == 4 then -- Ctrl-D
          if buffer_length() == 0 then
            io.write('\n')
            io.flush()
            return nil, 'eof'
          end
        elseif byte == 3 then -- Ctrl-C
          io.write('\n')
          io.flush()
          return nil, 'interrupt'
        elseif byte == 127 or byte == 8 then -- Backspace/Delete
          if cursor > 0 then
            table.remove(buffer, cursor)
            cursor = cursor - 1
            break_history_navigation()
            saved_draft_valid = false
            refresh_line()
          else beep()
          end
        elseif byte == 27 then -- Escape sequences
          local function read_escape()
            local prefix = io.stdin:read(1)
            if not prefix then return nil end
            if prefix ~= '[' and prefix ~= 'O' then return { prefix = prefix } end
            local params = {}
            while true do
              local next_ch = io.stdin:read(1)
              if not next_ch then return nil end
              if next_ch:match('[0-9;]') then params[#params + 1] = next_ch
              else return { prefix = prefix, params = table.concat(params), final = next_ch }
              end
            end
          end

          local seq = read_escape()
          if not seq then return nil, 'eof' end

          local final = seq.final or ''
          if seq.prefix == '[' or seq.prefix == 'O' then
            if final == 'A' then -- Up arrow
              if history_size() == 0 then beep()
              else
                if at_bottom() then ensure_saved_draft() end
                if history_index > 1 then history_index = history_index - 1
                else history_index = 1 end
                pull_history(history_index)
              end
            elseif final == 'B' then -- Down arrow
              if history_size() == 0 or at_bottom() then beep()
              else
                history_index = history_index + 1
                if at_bottom() then
                  set_buffer(saved_draft_valid and saved_draft or '')
                  saved_draft_valid = false
                  refresh_line()
                else pull_history(history_index) end
              end
            elseif final == 'C' then -- Right arrow
              if cursor < buffer_length() then
                cursor = cursor + 1
                break_history_navigation()
                refresh_line()
              else beep()
              end
            elseif final == 'D' then -- Left arrow
              if cursor > 0 then
                cursor = cursor - 1
                break_history_navigation()
                refresh_line()
              else beep()
              end
            elseif final == 'H' then -- Home
              if cursor > 0 then
                cursor = 0
                break_history_navigation()
                refresh_line()
              else beep()
              end
            elseif final == 'F' then -- End
              if cursor < buffer_length() then
                cursor = buffer_length()
                break_history_navigation()
                refresh_line()
              else beep()
              end
            else
              local params = seq.params or ''
              if final == '~' and params == '3' then -- Delete key
                if cursor < buffer_length() then
                  table.remove(buffer, cursor + 1)
                  break_history_navigation()
                  saved_draft_valid = false
                  refresh_line()
                else beep()
                end
              else beep()
              end
            end
          else beep()
          end
        elseif byte >= 32 and byte <= 126 then
          table.insert(buffer, cursor + 1, ch)
          cursor = cursor + 1
          break_history_navigation()
          saved_draft_valid = false
          refresh_line()
        else beep()
        end
      end
    end

    local ok, line, tag = pcall(reader_loop)
    restore_stty(stty_state)
    if not ok then
      local message = tostring(line or '')
      if message:find('interrupted!') then
        io.write('\n')
        io.flush()
        return nil, 'interrupt'
      end
      error(line)
    end
    return line, tag
  end
end

local posix_line_reader = create_posix_line_reader()

local function read_line(prompt, history, opts)
  if linenoise then
    local line = linenoise.linenoise(prompt)
    if line and has_visible_chars(line) then pcall(linenoise.addhistory, line) end
    if line == nil then return nil, 'interrupt' end
    return line, nil
  end
  if posix_line_reader then
    local line, tag = posix_line_reader(prompt, history or {}, opts)
    return line, tag
  end
  io.write(prompt)
  io.flush()
  local line = io.read('*l')
  if line == nil then return nil, 'eof' end
  return line, nil
end

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
  if type(session) == 'table' and session.id ~= nil then
    session_id = session.id
    print(("lua > message: [%s] [%s] %s"):format(session.str, msg_type, msg_value))
  else
    print(msg:format(tonumber(session), msg_type, msg_value))
  end
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
  traits.shared_data_dir = "./shared"
  traits.user_data_dir = "./user"
  traits.prebuilt_data_dir = "./shared"
  traits.distribution_name = "rime_api_console"
  traits.distribution_code_name = "rime_api_console"
  traits.distribution_version = "1.0.0"
  traits.log_dir = "./log"
  -- print(traits)
  if not os.mkdir then
    -- check system is windows or unix-like
    local is_windows = package.config:sub(1, 1) == '\\'
    local mkdir_cmd = is_windows and "md " or "mkdir -p "
    os.execute(mkdir_cmd .. traits.shared_data_dir)
    os.execute(mkdir_cmd .. traits.user_data_dir)
    os.execute(mkdir_cmd .. traits.log_dir)
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
end
--- print status info
--- @param status RimeStatus
--- @return nil
local function print_status(status)
  local msg = string.format("schema: %s / %s", status.schema_id, status.schema_name)
  print(msg)
  msg = "status: "
  local disabled = status.is_disabled == true and " disabled" or "";
  local composing = status.is_composing == true and " composing" or "";
  local ascii_mode = status.is_ascii_mode == true and " ascii_mode" or "";
  local full_shape = status.is_full_shape == true and " full_shape" or "";
  local simplified = status.is_simplified == true and " simplified" or "";
  msg = msg .. disabled .. composing .. ascii_mode .. full_shape .. simplified
  print(msg)
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
    local highlight = i == menu.highlighted_candidate_index
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
  if api:get_status(session_id, status) then
    print_status(status)
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
    local input, status = read_line(prompt, history)
    if input == nil then
      if status == 'interrupt' then
      else break end
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
        print("distroying session..." .. string.format("0x%x", session_id.id))
        session_id_alive = false
        api:finalize()
        input = ""
        main()
      end
      if not execute_special_command(session_id, input) then
        if api:simulate_key_sequence(session_id, input) then print_session(session_id) end
      end
    end
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
