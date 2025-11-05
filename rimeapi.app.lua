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

local function create_posix_line_reader()
  if package.config:sub(1,1) == '\\' then return nil end

  local function is_tty()
    local result = os.execute('tty -s >/dev/null 2>&1')
    return result == true or result == 0
  end

  local function capture_stty_state()
    local pipe = io.popen('stty -g', 'r')
    if not pipe then return nil end
    local state = pipe:read('*l')
    pipe:close()
    return state
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

    local restored = false
    local function restore_stty()
      if not restored then
        os.execute('stty ' .. stty_state)
        restored = true
      end
    end

    local set_raw = os.execute('stty -icanon -echo min 1 time 0')
    if not (set_raw == true or set_raw == 0) then
      restore_stty()
      io.write(prompt)
      io.flush()
      return io.read('*l')
    end

    local function reader_loop()
      io.write(prompt)
      io.flush()
      local buffer = {}
      local buf_len = 0
      local saved_draft = ''
      local history_index = (#history or 0) + 1

      local function history_size()
        return #history
      end

      local function current_buffer()
        if buf_len == 0 then return '' end
        return table.concat(buffer, '', 1, buf_len)
      end

      local function set_buffer(text)
        text = text or ''
        local prev_len = buf_len
        buf_len = #text
        for i = 1, buf_len do
          buffer[i] = text:sub(i, i)
        end
        for i = buf_len + 1, prev_len do
          buffer[i] = nil
        end
      end

      local function refresh_line()
        io.write('\r')
        io.write(prompt)
        io.write(current_buffer())
        io.write('\27[K')
        io.flush()
      end

      local function enter_bottom_mode()
        history_index = history_size() + 1
        saved_draft = current_buffer()
      end

      while true do
        local char = io.read(1)
        if not char or char == '' then
          return nil
        end
        local byte = char:byte()

        if byte == 13 or byte == 10 then
          refresh_line()
          io.write('\n')
          io.flush()
          return current_buffer()
        elseif byte == 4 then -- Ctrl-D
          if buf_len == 0 then
            io.write('\n')
            io.flush()
            return nil
          end
        elseif byte == 3 then -- Ctrl-C
          io.write('\n')
          io.flush()
          return nil
        elseif byte == 127 or byte == 8 then -- Backspace/Delete
          if history_index ~= history_size() + 1 then
            enter_bottom_mode()
          end
          if buf_len > 0 then
            buffer[buf_len] = nil
            buf_len = buf_len - 1
            saved_draft = current_buffer()
            refresh_line()
          else
            io.write('\7')
            io.flush()
          end
        elseif byte == 27 then -- Escape sequences
          local seq1 = io.read(1)
          local seq2 = io.read(1)
          if seq1 == '[' and seq2 then
            if seq2 == 'A' then -- Up arrow
              if history_size() == 0 then
                io.write('\7')
                io.flush()
              else
                if history_index == history_size() + 1 then
                  saved_draft = current_buffer()
                end
                if history_index > 1 then
                  history_index = history_index - 1
                else
                  history_index = 1
                end
                set_buffer(history[history_index] or '')
                refresh_line()
              end
            elseif seq2 == 'B' then -- Down arrow
              if history_size() == 0 or history_index == history_size() + 1 then
                io.write('\7')
                io.flush()
              else
                history_index = history_index + 1
                if history_index > history_size() then
                  history_index = history_size() + 1
                  set_buffer(saved_draft)
                else
                  set_buffer(history[history_index] or '')
                end
                refresh_line()
              end
            else
              io.write('\7')
              io.flush()
            end
          end
        elseif byte >= 32 and byte <= 126 then
          if history_index ~= history_size() + 1 then
            history_index = history_size() + 1
            saved_draft = current_buffer()
          end
          buf_len = buf_len + 1
          buffer[buf_len] = char
          saved_draft = current_buffer()
          io.write(char)
          io.flush()
        else
          io.write('\7')
          io.flush()
        end
      end
    end

    local ok, result = pcall(reader_loop)
    restore_stty()
    if not ok then error(result) end
    return result
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
