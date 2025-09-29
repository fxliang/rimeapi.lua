-- Configuration option to choose lua engine
option("lua_engine")
  set_default("lua")
  set_values("lua", "luajit")
  set_description("Choose lua engine: lua or luajit")
option_end()

local prefix = os.getenv("PREFIX")
local is_termux = prefix and prefix:match("com%.termux") ~= nil

-- Get the lua engine configuration
local lua_engine = get_config("lua_engine") or "lua"
-- add_requires of lua_engine
add_requires(lua_engine, {system = false})

-------------------------------------------------------------------------------
--- core object lib
target('core')
  set_kind('object')
  set_languages('c++17')
  if is_plat('linux') then add_cxflags('-fPIC') end
  add_files('src/*.c', 'src/*.cc')
  add_rules('common_rules')

-------------------------------------------------------------------------------
target('rimeapi.app')
  add_deps('core')
  if is_plat('windows') then
    add_linkdirs(is_arch('x64') and 'lib64' or 'lib')
  end
  if is_plat('linux') then
    add_ldflags('-Wl,-rpath,$ORIGIN', {force = true})
  end
  add_files('src/main.cpp')
  add_rules('copy_after_build', 'common_rules')

-------------------------------------------------------------------------------
target('rimeapi')
  set_kind('shared')
  --set target file name to rimeapi.so or rimeapi.dll
  local file_name = is_plat('windows') and 'rimeapi.dll'
    or (is_plat('macosx') and 'rimeapi.dylib' or 'rimeapi.so')
  set_filename(file_name)
  add_files('src/main.cpp', {defines = 'BUILD_AS_LUA_MODULE'})
  add_deps('core')
  if is_plat('windows') then
    add_linkdirs(is_arch('x64') and 'lib64' or 'lib')
  end
  add_rules('copy_after_build', 'common_rules')

-------------------------------------------------------------------------------
-- rules definition
rule('common_rules')
  on_load(function(target)
    target:set('languages', 'c++17')
    target:add('links', 'rime')
    target:add('packages', lua_engine)
    if is_plat('windows') then
      target:add('cxflags', '/utf-8')
      target:add('cflags', '/utf-8')
      target:add('includedirs', 'include')
    else
      target:add('syslinks', {'pthread', 'dl'})
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
  after_load(function (target)
    local pkgs = target:pkgs()
    local pkg = pkgs and pkgs[lua_engine]
    if pkg and pkg.installdir then
      local installdir = pkg:installdir()
      if installdir and os.isdir(installdir) then
        target:set('lua_bin_dir', path.join(installdir, 'bin'))
      end
    end
  end)

rule('copy_after_build')
  -- copy executable to project dir
  after_build(function (target)
    print('copy ' .. target:targetfile() .. ' to ' .. os.projectdir())
    os.cp(target:targetfile(), os.projectdir())
    if is_plat('windows', 'mingw') then
      os.trycp(is_arch('x64') and 'lib64\\rime.dll' or 'lib\\rime.dll', os.projectdir())
    end
    if target:name() == 'rimeapi' then
      local bin_path = target:get('lua_bin_dir')
      if bin_path and os.isdir(bin_path) then
        local lua_bin_name = is_plat('windows', 'mingw') and (lua_engine .. '.exe') or lua_engine
        local lua_path = path.join(bin_path, lua_bin_name)
        print('copy ' .. lua_path .. ' to ' .. os.projectdir())
        os.trycp(lua_path, os.projectdir())
      end
    end
  end)
