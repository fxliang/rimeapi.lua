local runner
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
  local script_cpath = script_path() .. div .. '?.dll' .. ';' .. script_path() .. div .. '?.dylib'
  .. ';' .. script_path() .. div .. '?.so'
  -- add the ?.so, ?.dylib or ?.dll to package.cpath ensure requiring
  -- you must keep the rime.dll, librime.dylib or librime.so in current search path
  package.cpath = package.cpath .. ';' .. script_cpath
  package.path = package.path .. ';' .. script_path() .. div .. '?.lua'
  require('rimeapi')
  runner = true
end
-------------------------------------------------------------------------------
-- write a simple repl
local function repl()
  print("RimeApi REPL. Type 'exit' or 'quit' to leave.")
  while true do
    io.write("> ")
    local input = io.read()
    if input == "exit" or input == "quit" then
      break
    end
    local func, err = load("return " .. input)
    if not func then
      func, err = load(input)
    end
    if func then
      local success, result = pcall(func)
      if success and result ~= nil then
        print(result)
      elseif not success then
        print("Error: " .. result)
      end
    else
      print("Error: " .. err)
    end
  end
end
repl()
