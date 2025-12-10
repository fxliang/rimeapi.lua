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
    fullpath = p and p:read('*a') or ''
    if p then p:close() end
    fullpath = fullpath:gsub('[\n\r]*$','')
    dirname, filename = fullpath:match('^(.*/)([^/]-)$')
  end
  dirname = dirname or ''
  filename = filename or fullpath
  return dirname
end
if not RimeApi then
  --- add the so/dll/lua files in cwd to package.cpath

  local div = package.config:sub(1,1) == '\\' and '\\' or '/'
  local base = script_path()
  local script_cpath = base .. div .. '?.dll' .. ';' .. base .. div .. '?.dylib' .. ';' .. base .. div .. '?.so'
  package.cpath = package.cpath .. ';' .. script_cpath
  package.path = base .. div .. '?.lua' .. ';' .. package.path
  require('rimeapi')
end
--------------------------------------------------------------------------------

local path_sep = package.config:sub(1,1) == '\\' and '\\' or '/'

local function pack(...) return { n = select('#', ...), ... } end

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

local function try_compile_chunk(chunk)
  if chunk == nil then return nil, false, 'empty chunk' end
  local fn, err = load('return ' .. chunk, '=(repl)')
  if fn then
    return fn, true, nil
  end
  fn, err = load(chunk, '=(repl)')
  if fn then
    return fn, false, nil
  end
  return nil, false, err
end

local function collect_chunk(history, prompt, continuation_prompt, initial_text)
  local lines = {}
  local current_prompt = prompt
  local first = true
  local opts = { continuation_prompt = continuation_prompt, initial_text = initial_text }

  while true do
    local line, tag = LineEditor.read_line(current_prompt, history, opts)
    if first then
      -- after first read, drop initial_text so subsequent continuation lines do not prefill again
      opts.initial_text = nil
      first = false
    end
    if line == nil then
      return nil, nil, false, tag
    end

    lines[#lines + 1] = line
    local chunk = table.concat(lines, '\n')
    if not LineEditor.has_visible_chars(chunk) and #lines == 1 then
      return chunk, nil, false, 'blank'
    end
    local fn, is_expr, err = try_compile_chunk(chunk)
    if fn then
      return chunk, fn, is_expr, nil
    end

    local err_str = err and tostring(err) or ''
    if err_str:find('<eof>', 1, true) then
      current_prompt = continuation_prompt
    else
      -- Return the typed chunk alongside the syntax error so callers can
      -- prefill it for editing and optionally push it to history.
      return chunk, nil, false, 'syntax', err
    end
  end
end

local function supports_color()
  if os.getenv('NO_COLOR') then return false end
  if io.type(io.stdout) == 'file' then
    if os.getenv('TERM') and os.getenv('TERM') ~= 'dumb' then
      if os.getenv('COLORTERM') then return true end
      local term = os.getenv('TERM'):lower()
      if term:match('xterm') or term:match('screen') or term:match('vt100') or term:match('linux') then
        return true
      end
    end
  else return true end
  if os.getenv('TERM_PROGRAM') or os.getenv('COLORTERM') then return true end
  return false
end

-- Format REPL errors with optional color, source line context, caret for syntax
local function format_repl_error(chunk, err, kind)
  local use_color = os.getenv('NO_COLOR') == nil and supports_color()
  local red = use_color and '\27[31m' or ''
  local bold = use_color and '\27[1m' or ''
  local reset = use_color and '\27[0m' or ''
  local msg = tostring(err)
  if kind == 'syntax' then
    local line_no, detail = msg:match('%(repl%):(%d+):%s*(.+)')
    local out = { string.format('%sError:%s %s%s%s', red, reset, bold, detail or msg, reset) }
    if line_no then
      local ln = tonumber(line_no)
      local lines = {}
      for s in (chunk .. '\n'):gmatch('(.-)\n') do lines[#lines + 1] = s end
      local src = lines[ln] or ''
      out[#out + 1] = string.format('  at line %d: %s', ln, src)
      local near_token = detail and detail:match("near '([^']+)'") or nil
      if near_token and src ~= '' then
        local pos = src:find(near_token, 1, true)
        if pos then
          local caret = string.rep(' ', pos - 1) .. (use_color and red or '') .. string.rep('^', #near_token) .. reset
          out[#out + 1] = '             ' .. caret
        end
      end
    end
    return table.concat(out, '\n')
  else
    -- runtime or other errors: include traceback filtered to (repl) frames
    local tb = debug.traceback(err, 2)
    local filtered = {}
    for line in tb:gmatch('[^\n]+') do
      if line:find('=(repl%)') or line:find('%(repl%)') then filtered[#filtered + 1] = line end
    end
    if #filtered == 0 then filtered[#filtered + 1] = tb end
    return string.format('%sError:%s %s%s%s\n%s', red, reset, bold, msg, reset, table.concat(filtered, '\n'))
  end
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
  local prompt = '> '
  local continuation_prompt = '>> '
  local interrupted = false
  local prefill_next = nil

  while true do
    local chunk, fn, is_expr, status, err = collect_chunk(history, prompt, continuation_prompt, prefill_next)
    prefill_next = nil
    if chunk == nil then
      if status == 'interrupt' then
        interrupted = true
        break
      elseif status == 'eof' then
        break
      else
        break
      end
    elseif status == 'blank' or not LineEditor.has_visible_chars(chunk) then
      -- ignore empty submissions
    elseif status == 'syntax' then
      history[#history + 1] = chunk
      if linenoise then pcall(linenoise.addhistory, chunk) end
      print(format_repl_error(chunk, err, 'syntax'))
    else
      history[#history + 1] = chunk
      if linenoise then
        pcall(linenoise.addhistory, chunk)
      end

      local results = pack(pcall(fn))
      if not results[1] then
        print(format_repl_error(chunk, results[2], 'runtime'))
      else
        if results.n > 1 then
          for i = 2, results.n do
            print(results[i] and tostring(results[i]) or 'nil')
          end
        end
      end
    end
  end
  return interrupted
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
  local cp = set_console_codepage()
  if script then
    local ok = run_script(script, extras)
    set_console_codepage(cp)
    os.exit(ok and 0 or 1)
  else
    local interrupted = repl()
    if interrupted then
      set_console_codepage(cp)
      os.exit(130)
    else
      set_console_codepage(cp)
      os.exit(0)
    end
  end
end

main()
