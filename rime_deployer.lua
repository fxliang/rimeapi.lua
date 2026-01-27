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
local function set_codepage(page)
  return (package.config:sub(1, 1) == '\\') and set_console_codepage(page) or 0
end
local cp = set_codepage(65001) -- set to UTF-8
-------------------------------------------------------------------------------
local function deployer(user_dir, shared_dir, staging_dir)
  local api = RimeApi()
  local t = RimeTraits()
  t.app_name = "rime_deployer.lua"
  t.shared_data_dir = shared_dir
  t.user_data_dir = user_dir
  if staging_dir then t.staging_dir = staging_dir end
  t.log_dir = "" -- output to stderr
  api:setup(t)
  api:initialize(t)
  api:start_maintenance(true)
  api:finalize()
end
-------------------------------------------------------------------------------
if #arg == 0 then
  print("Usage: lua rime_deployer.lua [user_data_dir] [shared_data_dir] [staging_dir (optional)]")
  print("Example: lua rime_deployer.lua ./user_data ./shared_data ./staging")
  print("The output deployed files will be in user_data_dir/build or staging_dir if provided")
  set_codepage(cp)
  os.exit(0)
end
-------------------------------------------------------------------------------
local user_dir = arg[1] or "."
local shared_dir = arg[2] or "."
local staging_dir = arg[3] or nil
deployer(user_dir, shared_dir, staging_dir)
set_codepage(cp)
