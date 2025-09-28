local api = RimeApi()
local traits = RimeTraits()
traits.app_name = "rimeapi"
traits.shared_data_dir = "shared"
traits.user_data_dir = "user"
traits.prebuilt_data_dir = "shared"
traits.distribution_name = "rimeapi"
traits.distribution_code_name = "rimeapi"
traits.distribution_version = "1.0.0"
traits.log_dir = "log"

-- 创建必要的目录
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

print("Calling setup...")
api:setup(traits)
print("Setup completed!")

local function rime_api_test()
  print("---------------------------------------------")
  print("test for rime api")
  print("Setting notification handler...")
  local function onNotify(context_object, session_id, message_type, message_value)
    print(string.format("[test_rime.lua][%s][%s]: %s",
      string.format("%x", session_id),
      tostring(message_type or "nil"),
      tostring(message_value or "nil")))
  end

  api:set_notification_handler(onNotify)
  print("Notification handler set!")

  api:initialize(traits)
  print("Initialization completed!")

  print("Starting maintenance...")
  if api:start_maintenance(true) then
    api:join_maintenance_thread()
  end
  local session_id = api:create_session()
  print("Creating session..." .. string.format("0x%x", session_id.id))

  local schema_result = api:select_schema(session_id, "luna_pinyin")
  print("Selecting schema luna_pinyin... " .. (schema_result and "succeeded" or "failed"))
  local ret, str = api:get_current_schema(session_id, 256)
  if ret then print("Current schema id:", str) end

  print("---------------------------------------------")
  print("simulate keys nihao")
  api:simulate_key_sequence(session_id, "nihao")
  local status = RimeStatus()
  if api:get_status(session_id, status) then
    print("status: ")
    print(status)
  end
  local context = RimeContext()
  if api:get_context(session_id, context) then
    local comp = context.composition
    local menu = context.menu
    print("context: ", context)
    print("composition:", comp)
    print("menu", menu)
    print("Candidates:", menu.candidates)
    for i = 1, menu.num_candidates do
      print(string.format("  [%d] %s %s", i, menu.candidates[i].text,
        menu.candidates[i].comment == nil and "" or menu.candidates[i].comment))
    end
  end
  print("---------------------------------------------")
  print("simulate space")
  api:simulate_key_sequence(session_id, " ")

  local commit = RimeCommit()
  if api:get_commit(session_id, commit) then
    print("commit:", commit)
  end
  print("---------------------------------------------")
  print("Opening luna_pinyin.schema.yaml config with RimeConfig()...")
  local config = RimeConfig()
  if api:config_open("luna_pinyin.schema", config) then
    print("config of luna_pinyin.schema.yaml:", config)
    local success, value = api:config_get_int(config, "menu/page_size")
    if success then
      print("menu/page_size:", value)
    else
      print("Failed to get menu/page_size")
    end
    local success, str = api:config_get_string(config, "schema/name", 256)
    if success then
      print("schema/name:", str)
    else
      print("Failed to get schema/name")
    end
    local success, bvalue = api:config_get_bool(config, "reverse_lookup/enable_completion")
    if success then
      print("reverse_lookup/enable_completion:", bvalue)
    else
      print("Failed to get reverse_lookup/enable_completion")
    end
    bvalue = config:get_bool("reverse_lookup/enable_completion")
    print("reverse_lookup/enable_completion (from method):", bvalue)

    local iter = RimeConfigIterator()
    -- examle of config_begin_map and config_next
    print('\niteration on zh_simp map')
    if api:config_begin_map(iter, config, "zh_simp") then
      while api:config_next(iter) do
        local ret, str = api:config_get_string(config, iter.path, 256)
        print(ret, iter.path .. ": " .. str)
      end
      api:config_end(iter)
    end
    -- examle of config_begin_list and config_next
    print('\niteration on speller/algebra list')
    if api:config_begin_list(iter, config, "speller/algebra") then
      while api:config_next(iter) do
        local ret, str = api:config_get_string(config, iter.path, 256)
        print(ret, iter.path .. ": " .. str)
      end
      api:config_end(iter)
    end
    print("")
    iter = nil
    success = api:config_close(config)
    if success then print("Config closed successfully") else print("Failed to close config") end
    print("Config luna_pinyin.schema.yaml closed:", config)
  end
  print("--------------------------------------------")
  print("Opening default.yaml config with RimeConfig constructor...")
  -- Using reload/open to test reload function without new a new object
  config:reload("default")
  if not config then
    print("Failed to open default config")
  end
  local ret, page_size = api:config_get_int(config, "menu/page_size")
  if ret then
    print("menu/page_size:", page_size)
  else
    print("Failed to get menu/page_size from default config")
  end
  print("menu/page_size (from method):", config:get_int("menu/page_size"))
  print(config:set_int("menu/page_size", 9))
  print("after config:set_int:", config:get_int("menu/page_size"))

  local ret, str = api:config_get_string(config, "switcher/caption", 256)
  if ret then
    print("switcher/caption:", str)
  else
    print("Failed to get switcher/caption from default config")
  end
  str = config:get_string("switcher/caption", 256)
  print("switcher/caption (from method):", str)
  str = config:get_cstring("switcher/caption")
  print("switcher/caption (from get_cstring method):", str)
  print(config:get_string("nonexistent/key", 256))
  print(config:get_cstring("nonexistent/key"))
  print("--------------------------------------------")
  print("Destroying session...")
  local destroy_result = api:destroy_session(session_id)
  print("Session destroy result:", destroy_result)

  --print("Disabling notification handler...")
  --api:set_notification_handler(nil)

  print("Calling finalize...")
  api:finalize()
  print("Finalize completed!")
  commit = nil
  context = nil
  config = nil
  status = nil
end
local function levers_api_test()
  print("---------------------------------------------")
  print("test for levers api")
  api:deployer_initialize(traits)
  local levers = RimeLeversApi()
  print("Levers API:", levers)
  local settings = levers:custom_settings_init('default', "rimeapi.lua")
  print("Custom settings:", settings)
  if settings then
    levers:load_settings(settings) -- 先加载一次
    if levers:customize_int(settings, "menu/page_size", 10) then
      levers:save_settings(settings) -- 保存
      print("Customized menu/page_size to 10")
    end
    levers:custom_settings_destroy(settings)
  end
  local switcher_settings = levers:switcher_settings_init()
  print("Switcher settings:", switcher_settings)
  if levers:load_settings(switcher_settings) then
    print("Switcher settings loaded:", switcher_settings)
    local schemalist = RimeSchemaList()
    print("Schema list before customization:", schemalist)
    if levers:get_available_schema_list(switcher_settings, schemalist) then
      print("get_available_schema_list succeeded")
      local list = schemalist.list
      print(list)
      for k,v in pairs(list) do
        print(string.format("  [%d] %s %s", k, v.schema_id, v.name))
        print("schema name:", v.schema_info.name)
        print("schema author:", v.schema_info.author)
        print("schema description:", v.schema_info.description)
        --print(v)
      end
    end
    local schemaselected = RimeSchemaList()
    if levers:get_selected_schema_list(switcher_settings, schemaselected) then
      print("get_selected_schema_list succeeded")
      local list = schemaselected.list
      print(list)
      for k,v in pairs(list) do
        print(string.format("  [%d] %s %s", k, v.schema_id, v.name))
      end
    end
    -- schema list from rime_api and rime_levers_api should be free or destroy by coresponding api
    levers:schema_list_destroy(schemaselected)
    levers:schema_list_destroy(schemalist)
    local schemalistg = RimeSchemaList()
    api:get_schema_list(schemalistg)
    print("Schema list from api:get_schema_list:", schemalistg)
    for k,v in pairs(schemalistg.list) do
      print(string.format("  [%d] %s %s", k, v.schema_id, v.name))
    end
    api:free_schema_list(schemalistg)
  end

  api:finalize()
  api:initialize(traits)
  local default = RimeConfig()
  default:open("default")
  print(default)
  local ret, page_size = api:config_get_int(default, "menu/page_size")
  if ret then print("menu/page_size after customization:", page_size) end
  api:finalize()
  levers = nil
end

rime_api_test()
levers_api_test()
traits = nil
api = nil

collectgarbage("collect")
collectgarbage("collect")
