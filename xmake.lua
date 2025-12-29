if is_plat("windows") then
  if is_mode("debug") then set_runtimes("MTd")
  else set_runtimes("MT") end
end
-------------------------------------------------------------------------------

target('lua')
  set_kind('binary')
  add_files('lua5.4/onelua.c')
  if not is_plat('windows', 'mingw') then
    add_cflags('-fPIC -DLUA_USE_LINUX')
  end
  after_build(function(target)
    print('copy ' .. target:targetfile() .. ' to ' .. os.projectdir())
    os.trycp(target:targetfile(), os.projectdir())
  end)

target('lua5.4')
  set_kind('static')
  add_files('lua5.4/onelua.c')
  add_defines('MAKE_LIB')
  add_includedirs('lua5.4', {public = true})
  if not is_plat('windows', 'mingw') then
    add_cflags('-fPIC -DLUA_USE_LINUX')
  end

-------------------------------------------------------------------------------
target('rimeapi_lua')
  set_kind('shared')
  --set target file name to rimeapi_lua.so rimeapi_lua.dylib or rimeapi_lua.dll
  local file_name = is_plat('windows', 'mingw') and 'rimeapi_lua.dll'
    or (is_plat('macosx') and 'rimeapi_lua.dylib' or 'rimeapi_lua.so')
  set_filename(file_name)
  add_files('src/main.cpp', 'src/*.c', 'src/*.cc')
  add_rules('copy_after_build', 'common_rules')

target('noti_bridge')
  set_kind('shared')
  --set target file name to noti_bridge.so noti_bridge.dylib or noti_bridge.dll
  local file_name = is_plat('windows', 'mingw') and 'noti_bridge.dll'
    or (is_plat('macosx') and 'noti_bridge.dylib' or 'noti_bridge.so')
  set_filename(file_name)
  add_files('src/noti_bridge.cpp', 'src/line_editor.cc')
  add_rules('copy_after_build', 'common_rules')

-------------------------------------------------------------------------------
-- rules definition
rule('common_rules')
  on_load(function(target)
    local is_termux = os.getenv("TERMUX_VERSION") and true or false
    if is_termux or is_plat('macosx') then target:add('defines', 'RTLD_DEEPBIND=0') end
    target:set('languages', 'c++17')
    target:add('deps', 'lua5.4')
    if is_plat('windows', 'mingw') then
      target:add('includedirs', 'include')
      target:add('linkdirs', (is_arch('x64', 'x86_64') and 'lib64' or 'lib'))
      if is_plat('windows') then
        target:add('cxflags', '/utf-8')
        target:add('cflags', '/utf-8')
      else
        target:add('ldflags', '-static-libgcc -static-libstdc++ -static', {force = true})
        target:add('shflags', '-static-libgcc -static-libstdc++ -static', {force = true})
      end
    else
      if is_plat('macosx') then
        target:add('includedirs', 'include')
      elseif is_plat('linux') then
        if os.isdir('librime/src') and os.isfile('librime/src/rime_api.h') then
          target:add('includedirs', 'librime/src')
        end
      end
      target:add('syslinks', {'pthread', 'dl'})
      target:add('ldflags', ('-Wl,-rpath,' .. (is_plat('linux') and '$ORIGIN' or '@loader_path')), {force = true})
    end
    target:add('defines', 'RIME_EXPORTS')
    if is_mode('debug') then
      target:add('defines', 'DEBUG')
      target:add('cxflags', '-g', '-O0')
    else
      target:add('defines', 'NDEBUG')
      target:add('cxflags', '-O2')
    end
  end)

rule('copy_after_build')
  -- copy executable to project dir
  after_build(function (target)
    print('copy ' .. target:targetfile() .. ' to ' .. os.projectdir())
    os.cp(target:targetfile(), os.projectdir())
    if is_plat('windows', 'mingw') then
      os.trycp(is_arch('x64', 'x86_64') and 'lib64\\rime.dll' or 'lib\\rime.dll', os.projectdir())
    end
  end)
