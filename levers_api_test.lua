local rime_api = RimeApi()
local traits = RimeTraits()
traits.app_name = "rimeapi"
traits.shared_data_dir = "shared"
traits.user_data_dir = "levers_api_test"
traits.prebuilt_data_dir = "shared"
traits.distribution_name = "rimeapi"
traits.distribution_code_name = "rimeapi"
traits.distribution_version = "1.0.0"
traits.log_dir = "log"
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
rime_api:setup(traits)
rime_api:initialize(traits)
-- deploy
if rime_api:start_maintenance(true) then
  rime_api:join_maintenance_thread()
end
assert(rime_api:deploy_config_file("api_test", "0.1") == true) -- with config id only
-------------------------------------------------------------------------------

rime_api:deployer_initialize(traits)
local levers = RimeLeversApi()
assert(levers ~= nil)
print('RimeLeversApi() pass')
local settings = levers:custom_settings_init('default', "rimeapi.lua")
assert(settings ~= nil)
print('levers:custom_settings_init passed')
assert(levers:is_first_run(settings) ~= nil)
print('levers:is_first_run passed')
if settings then
  assert(levers:load_settings(settings) ~= nil) -- 先加载一次
  print('levers:load_settings passed')
  if levers:customize_int(settings, "menu/page_size", 10) then
    assert(levers:save_settings(settings) ~= nil) -- 保存
    print('levers:save_settings passed')
  end
  assert(levers:custom_settings_destroy(settings) == nil)
  print('levers:custom_settings_destroy passed')
end
local switcher_settings = levers:switcher_settings_init()
assert(switcher_settings ~= nil)
print('levers:switcher_settings_init passed')
if levers:load_settings(switcher_settings) then
  print('levers:load_settings for switcher passed')
  local schemalist = RimeSchemaList()
  assert(schemalist ~= nil)
  print('RimeSchemaList() passed')
  if levers:get_available_schema_list(switcher_settings, schemalist) then
    print("levers:get_available_schema_list passed")
    local list = schemalist.list
    assert(type(list) == "table")
    print("RimeSchemaList.list field passed")
    for _,v in pairs(list) do
      assert(v.schema_id ~= nil)
      assert(v.name ~= nil)
      assert(v.schema_info ~= nil)
      assert(v.schema_info.name ~= nil)
      assert(v.schema_info.author ~= nil)
      assert(v.schema_info.description ~= nil)
      assert(v.schema_info:get_schema_name())
      assert(v.schema_info:get_schema_id())
      assert(v.schema_info:get_schema_author())
      assert(v.schema_info:get_schema_description())
      assert(v.schema_info:get_schema_version())
      assert(v.schema_info:get_schema_file_path())
      assert(levers:get_schema_name(v.schema_info))
      assert(levers:get_schema_id(v.schema_info))
      assert(levers:get_schema_author(v.schema_info))
      assert(levers:get_schema_description(v.schema_info))
      assert(levers:get_schema_version(v.schema_info))
      assert(levers:get_schema_file_path(v.schema_info))
    end
    print('levers:get_schema_xxx and RimeSchemaInfo:get_schema_xxx functions passed')
    print('RimeSchemaListItem fields passed')
  end
  local schemaselected = RimeSchemaList()
  if levers:get_selected_schema_list(switcher_settings, schemaselected) then
    print("levers:get_selected_schema_list passed")
    local list = schemaselected.list
    for _,v in pairs(list) do
      assert(v.schema_id ~= nil)
      assert(v.name ~= nil)
    end
  end
  -- schema list 
  local schema_list = {'luna_pinyin', 'cangjie5'}
  assert(levers:select_schemas(switcher_settings, schema_list, 2) == true)
  print('levers:select_schemas passed')
  local hotkeys = levers:get_hotkeys(switcher_settings)
  assert(type(hotkeys)=='nil' or type(hotkeys)=='string')
  print('levers:get_hotkeys passed', hotkeys)
  assert(levers:set_hotkeys(switcher_settings, 'F5') == false) -- not implemented yet in librime
  print('levers:set_hotkeys passed(not implemented yet in librime)')
  assert(levers:schema_list_destroy(schemaselected) == nil)
  assert(levers:schema_list_destroy(schemalist) == nil)
  print('levers:schema_list_destroy passed')
end

local api_settings = levers:custom_settings_init('api_test', "rimeapi.lua")
assert(api_settings ~= nil)
if api_settings then
  assert(levers:load_settings(api_settings) ~= nil)
  if levers:customize_int(api_settings, "a_int", 42) then
    print('levers:customize_int passed')
    assert(levers:settings_is_modified(api_settings) == true)
    print('levers:settings_is_modified passed')
    assert(levers:save_settings(api_settings) ~= nil)
    print('levers:save_settings passed')
    assert(levers:settings_is_modified(api_settings) == false)
    print('levers:settings_is_modified passed')
  end
  if levers:customize_string(api_settings, "a_string", "hello") then
    print('levers:customize_string passed')
    assert(levers:save_settings(api_settings) ~= nil)
  end
  if levers:customize_bool(api_settings, "a_bool", false) then
    print('levers:customize_bool passed')
    assert(levers:save_settings(api_settings) ~= nil)
  end
  if levers:customize_double(api_settings, "a_double", 3.14) then
    print('levers:customize_double passed')
    assert(levers:save_settings(api_settings) ~= nil)
  end
  local a_patch = RimeConfig()
  assert(rime_api:config_load_string(a_patch, [[
a_list:
  - first_item_value
  - second_item_value
  - third_item_value
  ]]) == true)
  assert(levers:customize_item(api_settings, "a_list", a_patch) == true)
  assert(levers:save_settings(api_settings) ~= nil)
  print('levers:customize_item passed')
  a_patch = nil
end

rime_api:finalize()

-------------------------------------------------------------------------------
-- varify customization
rime_api:initialize(traits)
-- deploy
if rime_api:start_maintenance(true) then
  rime_api:join_maintenance_thread()
end
assert(rime_api:deploy_config_file("api_test", "0.1") == true) -- with config id only

local a_config = RimeConfig()
assert(levers:settings_get_config(api_settings, a_config) == true)
print('levers:settings_get_config passed')

local default = RimeConfig()
default:open("default")
local ret, page_size = rime_api:config_get_int(default, "menu/page_size")
assert(ret == true and page_size == 10)
print('levers customization int verified')

local api_test = RimeConfig()
api_test:open("api_test")
local ret2, a_int = rime_api:config_get_int(api_test, "a_int")
assert(ret2 == true and a_int == 42)
print('api_test customization int verified')
local ret3, a_string = rime_api:config_get_string(api_test, "a_string")
assert(ret3 == true and a_string == "hello")
print('api_test customization string verified')
local ret4, a_bool = rime_api:config_get_bool(api_test, "a_bool")
assert(ret4 == true and a_bool == false)
print('api_test customization bool verified')
local ret5, a_double = rime_api:config_get_double(api_test, "a_double")
assert(ret5 == true and a_double == 3.14)
print('api_test customization double verified')
--[[
api to be fix

user_dict_iterator_init
user_dict_iterator_destroy
next_user_dict
backup_user_dict
restore_user_dict
export_user_dict
import_user_dict

--]]

rime_api:finalize()
levers = nil
rime_api = nil

