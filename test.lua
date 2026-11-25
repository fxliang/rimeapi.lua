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
  package.path = package.path .. ';' .. script_path() .. div .. '?.lua'
  require('rimeapi')
end
-------------------------------------------------------------------------------
local lua = jit and 'luajit' or 'lua'
local ext = package.config:sub(1,1) == '\\' and '.exe' or ''
local cmd_runner = lua .. ext
local orig_cp = set_console_codepage(65001)
local test_user_dir = os.getenv("RIMEAPI_TEST_USER_DIR")
if not test_user_dir or test_user_dir == "" then
  local identity = tostring({}):match("0x(%x+)") or tostring(os.clock()):gsub("[^%w]", "")
  local temp_dir = os.getenv("TMPDIR") or os.getenv("TEMP") or "."
  local sep = package.config:sub(1, 1)
  test_user_dir = temp_dir .. sep .. "rimeapi_test_" .. tostring(os.time()) .. "_" .. identity
end
RIMEAPI_TEST_USER_DIR = test_user_dir
if #arg == 1 and arg[1] == '-h' then
  -- list modules in ./scripts/
  local function listLuaFiles(dir)
    local files = {}
    local cmd
    if package.config:sub(1,1) == '\\' then cmd = 'dir /b "' .. dir .. '" 2>nul'
    else cmd = 'ls "' .. dir .. '" 2>/dev/null'
    end

    local p = io.popen(cmd)
    if p then
      for line in p:lines() do
        if line:match("%.lua$") then table.insert(files, line:sub(1, -5)) end
      end
      p:close()
    end
    return files
  end
  print("Available <modulen_name> in scripts directory:")
  local luaFiles = listLuaFiles("scripts")
  if #luaFiles == 0 then
    print("  No .lua files found in scripts directory")
  else
    for _, filename in ipairs(luaFiles) do print("  " .. filename) end
  end
  print('Run:\n  '.. cmd_runner ..' test.lua <module_name>\n')
elseif #arg >= 1 then
  -- loop arg to require the module in scripts
  for i = 1, #arg do
    local module = 'scripts.' .. arg[i]
    print('Testing module: ' .. module)
    require(module)
    print('Tested module: ' .. module)
    print('-----------------------------------')
  end
else
  require('scripts.api_test')
  print('Tested default module: script.api_test')
end
set_console_codepage(orig_cp)
