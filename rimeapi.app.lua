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
  while true do
    io.write('> ')
    local line = io.read('*l')
    if line == nil then break end
    local chunk, err = load('return ' .. line, '=(repl)')
    if not chunk then
      chunk, err = load(line, '=(repl)')
    end
    if not chunk then print('Error: ' .. tostring(err))
    else
      local results = pack(pcall(chunk))
      if not results[1] then print('Error: ' .. tostring(results[2]))
      else
        if results.n > 1 then
          for i = 2, results.n do print(results[i] and tostring(results[i]) or 'nil') end
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
