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

if not RimeApi then
  --- add the so/dll/lua files in cwd to package.cpath
  -------------------------------------------------------------------------------
  -- get absolute path of current script
  local function script_path()
    local fullpath = debug.getinfo(1, "S").source:sub(2)
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
      fullpath = fullpath:gsub('[\n\r]*$', '')
      dirname, filename = fullpath:match('^(.*\\)([^\\]+)$')
    else
      local p = io.popen("realpath '" .. fullpath .. "'", 'r')
      if p then
        fullpath = p:read('a') or fullpath
        p:close()
      end
      fullpath = fullpath:gsub('[\n\r]*$', '')
      dirname, filename = fullpath:match('^(.*/)([^/]-)$')
    end
    dirname = dirname or ''
    filename = filename or fullpath
    return dirname
  end

  local div = package.config:sub(1,1) == '\\' and '\\' or '/'
  local base = script_path()
  local script_cpath = base .. div .. '?.dll' .. ';' .. base .. div .. '?.dylib' .. ';' .. base .. div .. '?.so'
  package.cpath = package.cpath .. ';' .. script_cpath
  package.path = package.path .. ';' .. base .. div .. '?.lua'
  require('rimeapi')
end
--------------------------------------------------------------------------------

local path_sep = package.config:sub(1,1) == '\\' and '\\' or '/'

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

local function beep()
  io.write('\7')
  io.flush()
end

local function create_posix_line_reader()
  if package.config:sub(1,1) == '\\' then return nil end

  local function is_tty()
    return shell_ok('test -t 0 >/dev/null 2>&1')
  end

  local function capture_stty_state()
    local pipe = io.popen('stty -g', 'r')
    if not pipe then return nil end
    local state = pipe:read('*l')
    pipe:close()
    return state
  end

  local function restore_stty(state)
    if state and state ~= '' then
      shell_ok('stty ' .. state)
    end
  end

  local function set_raw_mode()
    return shell_ok('stty -icanon -echo min 1 time 0')
  end

  return function(prompt, history)
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

      local function buffer_length()
        return #buffer
      end

      local function current_text()
        return table.concat(buffer)
      end

      local function set_buffer(text)
        buffer = {}
        for i = 1, #text do
          buffer[i] = text:sub(i, i)
        end
        cursor = #buffer
      end

      local function refresh_line()
        io.write('\r')
        io.write(prompt)
        io.write(current_text())
        io.write('\27[K')
        local move_left = buffer_length() - cursor
        if move_left > 0 then
          io.write(string.format('\27[%dD', move_left))
        end
        io.flush()
      end

      local function history_size()
        return #history
      end

      local function at_bottom()
        return history_index == history_size() + 1
      end

      local function break_history_navigation()
        if not at_bottom() then
          history_index = history_size() + 1
        end
      end

      local function ensure_saved_draft()
        if not saved_draft_valid then
          saved_draft = current_text()
          saved_draft_valid = true
        end
      end

      local function pull_history(index)
        set_buffer(history[index] or '')
        refresh_line()
      end

      while true do
        local ch = io.stdin:read(1)
        if not ch then
          return nil, 'eof'
        end
        local byte = ch:byte()

        if byte == 13 or byte == 10 then
          refresh_line()
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
          else
            beep()
          end
        elseif byte == 27 then -- Escape sequences
          local function read_escape()
            local prefix = io.stdin:read(1)
            if not prefix then return nil end
            if prefix ~= '[' and prefix ~= 'O' then
              return { prefix = prefix }
            end
            local params = {}
            while true do
              local next_ch = io.stdin:read(1)
              if not next_ch then return nil end
              if next_ch:match('[0-9;]') then
                params[#params + 1] = next_ch
              else
                return {
                  prefix = prefix,
                  params = table.concat(params),
                  final = next_ch
                }
              end
            end
          end

          local seq = read_escape()
          if not seq then
            return nil, 'eof'
          end

          local final = seq.final or ''
          if seq.prefix == '[' or seq.prefix == 'O' then
            if final == 'A' then -- Up arrow
              if history_size() == 0 then
                beep()
              else
                if at_bottom() then
                  ensure_saved_draft()
                end
                if history_index > 1 then
                  history_index = history_index - 1
                else
                  history_index = 1
                end
                pull_history(history_index)
              end
            elseif final == 'B' then -- Down arrow
              if history_size() == 0 or at_bottom() then
                beep()
              else
                history_index = history_index + 1
                if at_bottom() then
                  set_buffer(saved_draft_valid and saved_draft or '')
                  saved_draft_valid = false
                  refresh_line()
                else
                  pull_history(history_index)
                end
              end
            elseif final == 'C' then -- Right arrow
              if cursor < buffer_length() then
                cursor = cursor + 1
                break_history_navigation()
                refresh_line()
              else
                beep()
              end
            elseif final == 'D' then -- Left arrow
              if cursor > 0 then
                cursor = cursor - 1
                break_history_navigation()
                refresh_line()
              else
                beep()
              end
            elseif final == 'H' then -- Home
              if cursor > 0 then
                cursor = 0
                break_history_navigation()
                refresh_line()
              else
                beep()
              end
            elseif final == 'F' then -- End
              if cursor < buffer_length() then
                cursor = buffer_length()
                break_history_navigation()
                refresh_line()
              else
                beep()
              end
            else
              local params = seq.params or ''
              if final == '~' and params == '3' then -- Delete key
                if cursor < buffer_length() then
                  table.remove(buffer, cursor + 1)
                  break_history_navigation()
                  saved_draft_valid = false
                  refresh_line()
                else
                  beep()
                end
              else
                beep()
              end
            end
          else
            beep()
          end
        elseif byte >= 32 and byte <= 126 then
          table.insert(buffer, cursor + 1, ch)
          cursor = cursor + 1
          break_history_navigation()
          saved_draft_valid = false
          refresh_line()
        else
          beep()
        end
      end
    end

    local ok, line, tag = pcall(reader_loop)
    restore_stty(stty_state)
    if not ok then
      error(line)
    end
    return line, tag
  end
end

local posix_line_reader = create_posix_line_reader()

local function pack(...) return { n = select('#', ...), ... } end

local function file_exists(path)
  if type(path) ~= 'string' or path == '' then return false end
  local f = io.open(path, 'r')
  if f then f:close() return true end
  return false
end

local function dirname(path)
  if type(path) ~= 'string' or path == '' then return nil end
  local dir = path:match('^(.*)[/\\][^/\\]+$')
  if not dir or dir == '' then dir = '.' end
  return dir
end

local function ensure_package_path(dir)
  if not dir or dir == '' then return end
  local suffix = dir:sub(-1)
  local pattern = (suffix == '/' or suffix == '\\') and (dir .. '?.lua') or (dir .. path_sep .. '?.lua')
  if not package.path:find(pattern, 1, true) then package.path = package.path .. ';' .. pattern end
end

local function set_arg_table(script_path, extras)
  local args = {}
  args[0] = script_path or ''
  for i = 1, #extras do args[i] = extras[i] end
  _G.arg = args
end

local function run_script(script_path, extras)
  ensure_package_path(dirname(script_path))
  set_arg_table(script_path, extras)
  if os.isdir(script_path) then
    local init_path = script_path .. path_sep .. 'init.lua'
    if file_exists(init_path) then
      script_path = init_path
    end
  end
  local chunk, err = loadfile(script_path)
  if not chunk then
    io.stderr:write('Error: ' .. tostring(err) .. '\n')
    return false
  end
  local results = pack(pcall(chunk))
  if not results[1] then
    io.stderr:write('Error: ' .. tostring(results[2]) .. '\n')
    return false
  end
  return true
end

local function repl()
  set_arg_table('', {})
  print('Rime Lua API interactive mode. Ctrl-C to exit.')
  local history = {}

  local function read_line(prompt)
    if linenoise then
      return linenoise.linenoise(prompt)
    elseif posix_line_reader then
      return posix_line_reader(prompt, history)
    else
      io.write(prompt)
      io.flush()
      return io.read('*l')
    end
  end

  while true do
    local line = read_line('> ')
    if line == nil then break end

    if linenoise and line:match('%S') then
      pcall(linenoise.addhistory, line)
    end

    if line:match('%S') then
      history[#history + 1] = line
    end

    local chunk, err = load('return ' .. line, '=(repl)')
    if not chunk then
      chunk, err = load(line, '=(repl)')
    end
    if not chunk then
      print('Error: ' .. tostring(err))
    else
      local results = pack(pcall(chunk))
      if not results[1] then
        print('Error: ' .. tostring(results[2]))
      else
        if results.n > 1 then
          for i = 2, results.n do
            print(results[i] and tostring(results[i]) or 'nil')
          end
        end
      end
    end
  end
end

local function collect_cli()
  if type(_G.arg) ~= 'table' then return nil, {} end
  local script = _G.arg[1]
  if type(script) ~= 'string' or script == '' or not file_exists(script) then
    return nil, {}
  end
  local extras = {}
  local index = 2
  while _G.arg[index] ~= nil do
    extras[#extras + 1] = _G.arg[index]
    index = index + 1
  end
  return script, extras
end

local function main()
  local script, extras = collect_cli()
  if script then
    local ok = run_script(script, extras)
    os.exit(ok and 0 or 1)
  else
    repl()
    os.exit(0)
  end
end

main()
