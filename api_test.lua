local rime_api = RimeApi()
local traits = RimeTraits()
traits.app_name = "rimeapi"
traits.shared_data_dir = "shared"
traits.user_data_dir = "api_test"
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
print('rime_api:setup passed')
rime_api:set_notification_handler(function(_, session_id, msg_type, msg_value)
  print(string.format("[api_test.lua][%s][%s]: %s",
    string.format("%x", session_id),
    tostring(msg_type or "nil"),
    tostring(msg_value or "nil")))
end)
print('rime_api:set_notification_handler passed')
rime_api:initialize(traits)
print('rime_api:initialize passed')
if rime_api:start_maintenance(true) then
  print('rime_api:start_maintenance passed')
  local is_maintenace_mode = rime_api:is_maintenance_mode()
  assert(is_maintenace_mode ~= nil)
  print('rime_api:is_maintenance_mode passed: ')
  rime_api:join_maintenance_thread()
  print('rime_api:join_maintenance_thread passed')
end

----------------------------------------------------------------
local session = rime_api:create_session()
assert(session ~= 0)
print('rime_api:create_session passed')
assert(rime_api:find_session(session) == true)
print('rime_api:find_session passed')
assert(rime_api:destroy_session(session) == true)
print('rime_api:destroy_session passed')
assert(rime_api:find_session(session) == false)
print('rime_api:find_session after destroy passed')

----------------------------------------------------------------
-- test for cleanup_all_sessions
session = rime_api:create_session()
local session2 = rime_api:create_session()
assert(session2 ~= 0 and session ~= 0)
rime_api:cleanup_all_sessions()
assert(rime_api:find_session(session) == false)
assert(rime_api:find_session(session2) == false)
print('rime_api:cleanup_all_sessions passed')

----------------------------------------------------------------
session = rime_api:create_session()
session2 = nil
assert(session ~= 0)
---------------------------------------------------------------
-- test for get/select schema
assert(rime_api:select_schema(session, "luna_pinyin") ~= nil)
print('rime_api:select_schema passed')
local ret, schema = rime_api:get_current_schema(session)
assert(ret == true and schema ~= nil and schema == "luna_pinyin")
print('rime_api:get_current_schema passed: ' .. schema)
----------------------------------------------------------------
-- test for process_key press a
assert(rime_api:process_key(session, 0x61, 0) == true)
print('rime_api:process_key passed')
local context = RimeContext()
assert(context ~= nil)
print('RimeContext() passed')
local status = RimeStatus()
assert(status ~= nil)
print('RimeStatus() passed')
assert(rime_api:get_status(session, status) == true)
print('rime_api:get_status passed')
assert(status:__tostring():find("schema_id=\"luna_pinyin\"") ~= nil)
assert(status:__tostring():find("is_composing=true") ~= nil)
print('RimeStatus:__tostring passed')
assert(status.is_composing == true)
assert(status.schema_name == "朙月拼音")
assert(status.is_disabled == false)
assert(status.is_ascii_mode == false)
assert(status.is_full_shape == false)
assert(status.is_simplified == false)
assert(status.is_traditional == false)
assert(status.is_ascii_punct == false)
print('RimeStatus fields passed')
assert(rime_api:get_context(session, context) == true)
print('rime_api:get_context passed')
assert(context.composition ~= nil)
assert(context.menu ~= nil)
assert(context.select_labels == nil)
assert(context.commit_text_preview == "啊")
print('RimeContext fields passed')
assert(context.composition.preedit == "a")
assert(context.composition.length == 1)
assert(context.composition.cursor_pos == 1)
assert(context.composition.sel_start == 0)
assert(context.composition.sel_end == 1)
print('RimeComposition fields passed')
local expected_str = [[{
  preedit="a",
  length=1,
  cursor_pos=1,
  sel_start=0,
  sel_end=1
}]]
assert(context.composition:__tostring() == expected_str)
print('RimeComposition:__tostring passed')
local menu = context.menu
assert(menu.page_size == 5)
assert(menu.page_no == 0)
assert(menu.is_last_page == false)
assert(menu.highlighted_candidate_index == 0)
assert(menu.num_candidates == 5)
assert(type(menu.candidates)=='table') -- table 1-base
assert(menu.select_keys == '')
print('RimeMenu fields passed')
assert(menu.candidates[1].text == '啊')
assert(menu.candidates[1].comment == '')
print('RimeCandidate fields passed')
assert(menu.candidates[1]:__tostring() ~= nil)
print('RimeCandidate:__tostring passed, menu.candidates[1]: ' .. menu.candidates[1]:__tostring())
menu = nil

assert(rime_api:commit_composition(session) == true)
print('rime_api:commit_composition passed')
local commit = RimeCommit()
assert(commit ~= nil)
print('RimeCommit() passed')
assert(rime_api:get_commit(session, commit) == true)
assert(commit.text == "啊")
print('rime_api:get_commit passed: ' .. commit.text)

assert(rime_api:process_key(session, 0x61, 0) == true)
assert(rime_api:get_input(session) == "a")
print('rime_api:get_input passed: a')
assert(rime_api:get_caret_pos(session) == 1)
print('rime_api:get_caret_pos passed: 1')
assert(rime_api:select_candidate(session, 0) == true)
print('rime_api:select_candidate passed')

assert(rime_api:process_key(session, 0x61, 0) == true)
assert(rime_api:select_candidate_on_current_page(session, 0) == true)
print('rime_api:select_candidate_on_current_page passed')

assert(rime_api:process_key(session, 0x61, 0) == true)
assert(rime_api:set_caret_pos(session, 0) == nil)
assert(rime_api:get_caret_pos(session) == 0)
print('rime_api:set_caret_pos passed')
assert(rime_api:clear_composition(session) == nil)

assert(rime_api:get_state_label(session, 'ascii_mode', true) == "ABC")
print('rime_api:get_state_label passed: ' .. rime_api:get_state_label(session, 'ascii_mode', true))
local stringslice = rime_api:get_state_label_abbreviated(session, 'ascii_mode', true, true)
assert(stringslice and stringslice.str == 'Ａ' and stringslice.length == 3)
print('rime_api:get_state_label_abbreviated passed: str = ' .. stringslice.str .. ', length = ' .. stringslice.length)
print('RimeStringSlice fields passed')

assert(rime_api:process_key(session, 0x61, 0) == true)
assert(rime_api:set_input(session, "nihao") == true)
assert(rime_api:get_input(session) == "nihao")
print('rime_api:set_input and rime_api:get_input passed: nihao')
assert(rime_api:change_page(session, 0) == true)
assert(rime_api:change_page(session, 1) == true)
print('rime_api:change_page passed')

assert(rime_api:highlight_candidate(session, 2) == true)
assert(rime_api:get_context(session, context) == true)
assert(context.menu.highlighted_candidate_index == 2)
print('rime_api:highlight_candidate passed')

assert(rime_api:highlight_candidate_on_current_page(session, 1) == true)
assert(rime_api:get_context(session, context) == true)
assert(context.menu.highlighted_candidate_index == 1)
print('rime_api:highlight_candidate_on_current_page passed')
assert(rime_api:delete_candidate(session, 1) == true)
print("rime_api:delete_candidate passed")
assert(rime_api:delete_candidate_on_current_page(session, 0) == true)
print("rime_api:delete_candidate_on_current_page passed")

assert(rime_api:clear_composition(session) == nil)
assert(rime_api:get_context(session, context) == true)
assert(context.composition.preedit == "" and context.composition.length == 0)
print('rime_api:clear_composition passed')

assert(rime_api:simulate_key_sequence(session, "nihao") == true)
local candListIter = RimeCandidateListIterator()
assert(candListIter ~= nil)
print('RimeCandidateIterator() passed')
assert(rime_api:candidate_list_begin(session, candListIter) == true)
print('rime_api:candidate_list_begin passed')
while rime_api:candidate_list_next(candListIter) do
  local cand = candListIter.candidate
  assert(cand ~= nil)
  -- print(string.format("%d: %s", candListIter.index, cand.text))
end
assert(rime_api:candidate_list_end(candListIter) == nil)
print('rime_api:candidate_list_end passed')
assert(rime_api:candidate_list_from_index(session, candListIter, 1) == true)
while rime_api:candidate_list_next(candListIter) do
  local cand = candListIter.candidate
  assert(cand ~= nil)
  --print(string.format("%d: %s", candListIter.index, cand.text))
end
assert(rime_api:candidate_list_end(candListIter) == nil)
print('rime_api:candidate_list_from_index passed')
assert(rime_api:clear_composition(session) == nil)

assert(rime_api:free_commit(commit) == true)
print('rime_api:free_commit passed')
assert(rime_api:free_status(status) == true)
print('rime_api:free_status passed')
assert(rime_api:free_context(context) == true)
print('rime_api:free_context passed')
----------------------------------------------------------------
assert(rime_api:set_option(session, "ascii_mode", true) == nil)
print('rime_api:set_option passed')
assert(rime_api:get_option(session, "ascii_mode") == true)
print('rime_api:get_option passed')
assert(rime_api:set_property(session, "api_test_property", "test_value") == nil)
assert(rime_api:get_property(session, "api_test_property", 256) == true, "test_value")
print('rime_api:set_property and rime_api:get_property passed')

local schemas = RimeSchemaList()
assert(schemas ~= nil)
print('RimeSchemaList() passed')
assert(rime_api:get_schema_list(schemas) == true)
print('rime_api:get_schema_list passed')
assert(type(schemas.list) == 'table' and #schemas.list == 2)
assert(schemas.size == #schemas.list)
print('RimeSchemaList fields passed: size=' .. schemas.size)
-- schema_info is nil when rime_api:get_schema_list(schemas)
assert(schemas.list[1].schema_id == "luna_pinyin" and schemas.list[1].name == "朙月拼音" and schemas.list[1].schema_info == nil)
print('RimeSchemaListItem fields passed: schema_id=' .. schemas.list[1].schema_id .. ', name=' .. schemas.list[1].name .. ', schema_info=' .. tostring(schemas.list[1].schema_info))
assert(rime_api:free_schema_list(schemas) == nil)
print('rime_api:free_schema_list passed')
schemas = nil
----------------------------------------------------------------
assert(rime_api:schema_open("luna_pinyin", RimeConfig()) == true)
print('rime_api:schema_open passed')

assert(rime_api:prebuild() == true)
print('rime_api:prebuild passed')
assert(rime_api:deploy() == true)
print('rime_api:deploy passed')
assert(rime_api:deploy_schema("./shared/luna_pinyin.schema.yaml") == true) -- with file path
print('rime_api:deploy_schema passed')
assert(rime_api:deploy_config_file("api_test", "0.1") == true) -- with config id only
print('rime_api:deploy_config_file passed')

local config = RimeConfig()
assert(config ~= nil)
print('RimeConfig() passed')
assert(rime_api:config_open("api_test", config) == true)
print('rime_api:config_open passed')
assert(config:open('api_test') == true) -- open config data
print('RimeConfig:open passed')
assert(config:reload('api_test') == true) -- reload config data
print('RimeConfig:reload passed')
assert(config:get_string("a_string") == "a_string")
print('RimeConfig:get_string passed')
assert(config:get_string('a_string', 256) == "a_string")
print('RimeConfig:get_string with buffer size passed')
assert(config:get_cstring("a_string") == "a_string")
print('RimeConfig:get_cstring passed')
assert(rime_api:config_get_string(config, "a_string", 256) == true, "a_string")
print('rime_api:config_get_string passed')
assert(rime_api:config_get_string(config, "a_string") == true, "a_string")
print('rime_api:config_get_string without buffer size passed')
assert(rime_api:config_get_string(config, "nonexistent_key") == false)
print('rime_api:config_get_string for nonexistent key passed')
assert(config:set_string("a_string", "string_a") == true)
assert(config:get_string("a_string") == "string_a")
print('RimeConfig:set_string passed')
assert(rime_api:config_set_string(config, "a_string", "a_string") == true)
assert(rime_api:config_get_string(config, "a_string") == true, "a_string")
print('rime_api:config_set_string passed')

assert(config:get_int('a_int') == 10)
print('RimeConfig:get_int passed')
assert(rime_api:config_get_int(config, 'a_int') == true, 10)
print('rime_api:config_get_int passed')
assert(config:set_int('a_int', 20) == true)
assert(config:get_int('a_int') == 20)
print('RimeConfig:set_int passed')
assert(rime_api:config_set_int(config, 'a_int', 10) == true)
assert(rime_api:config_get_int(config, 'a_int') == true, 10)
print('rime_api:config_set_int passed')
assert(config:get_int('nonexistent_key') == nil)
print('RimeConfig:get_int for nonexistent key passed')
assert(rime_api:config_get_int(config, 'nonexistent_key') == false, nil)
print('rime_api:config_get_int for nonexistent key passed')

assert(config:get_double('a_double') == 520.233)
print('RimeConfig:get_double passed')
assert(rime_api:config_get_double(config, 'a_double') == true, 520.233)
print('rime_api:config_get_double passed')
assert(config:set_double('a_double', 233.520) == true)
assert(config:get_double('a_double') == 233.520)
print('RimeConfig:set_double passed')
assert(rime_api:config_set_double(config, 'a_double', 520.233) == true)
assert(rime_api:config_get_double(config, 'a_double') == true, 520.233)
print('rime_api:config_set_double passed')
assert(config:get_double('nonexistent_key') == nil)
print('RimeConfig:get_double for nonexistent key passed')
assert(rime_api:config_get_double(config, 'nonexistent_key') == false, nil)
print('rime_api:config_get_double for nonexistent key passed')

assert(config:get_bool('a_bool') == true)
print('RimeConfig:get_bool passed')
assert(rime_api:config_get_bool(config, 'a_bool') == true, true)
print('rime_api:config_get_bool passed')
assert(config:set_bool('a_bool', false) == true)
assert(config:get_bool('a_bool') == false)
print('RimeConfig:set_bool passed')
assert(rime_api:config_set_bool(config, 'a_bool', true) == true)
assert(rime_api:config_get_bool(config, 'a_bool') == true, true)
print('rime_api:config_set_bool passed')
assert(config:get_bool('nonexistent_key', false) == nil)
print('RimeConfig:get_bool for nonexistent key passed')
assert(rime_api:config_get_bool(config, 'nonexistent_key') == false, nil)
print('rime_api:config_get_bool for nonexistent key passed')

local iter = RimeConfigIterator()
assert(iter ~= nil)
print('RimeConfigIterator() passed')
-- examle of config_begin_map and config_next
if rime_api:config_begin_map(iter, config, "a_map") then
  local exp_str = 'a_map/first_item: first_item\na_map/forth_item: false\na_map/second_item: 233\na_map/third_item: 233.233'
  local acc_str = ''
  while rime_api:config_next(iter) do
    local _, str = rime_api:config_get_string(config, iter.path, 256)
    assert(_ == true)
    acc_str = acc_str .. iter.path .. ': ' .. str .. '\n'
  end
  assert(acc_str == exp_str..'\n')
  print('rime_api:config_begin_map and rime_api:config_next passed')
  assert(rime_api:config_end(iter) == nil)
  print('rime_api:config_end passed')
end
-- examle of config_begin_list and config_next
if rime_api:config_begin_list(iter, config, "a_list") then
  local exp_str = 'a_list/@0: first_item\na_list/@1: second_item\na_list/@2: third_item'
  local acc_str = ''
  while rime_api:config_next(iter) do
    local _, str = rime_api:config_get_string(config, iter.path, 256)
    assert(_ == true)
    acc_str = acc_str .. iter.path .. ': ' .. str .. '\n'
  end
  assert(acc_str == exp_str..'\n')
  print('rime_api:config_begin_list and rime_api:config_next passed')
  rime_api:config_end(iter)
end

assert(rime_api:config_close(config) == true)
print('rime_api:config_close passed')

----------------------------------------------------------------
assert(rime_api:get_shared_data_dir() ~= nil)
print('rime_api:get_shared_data_dir passed: \"' .. rime_api:get_shared_data_dir() .. '\"')
assert(rime_api:get_prebuilt_data_dir() ~= nil)
print('rime_api:get_prebuilt_data_dir passed: \"' .. rime_api:get_prebuilt_data_dir() .. '\"')
assert(rime_api:get_user_data_dir() ~= nil)
print('rime_api:get_user_data_dir passed: \"' .. rime_api:get_user_data_dir() .. '\"')
assert(rime_api:get_sync_dir() ~= nil)
print('rime_api:get_sync_dir passed: \"' .. rime_api:get_sync_dir() .. '\"')
assert(rime_api:get_user_id() ~= nil)
print('rime_api:get_user_id passed: \"' .. rime_api:get_user_id() .. '\"')
assert(rime_api:get_staging_dir() ~= nil)
print('rime_api:get_staging_dir passed: \"' .. rime_api:get_staging_dir() .. '\"')
assert(rime_api:get_user_data_sync_dir(256) ~= nil)
print('rime_api:get_user_data_sync_dir passed: \"' .. rime_api:get_user_data_sync_dir(256) .. '\"')

assert(rime_api:get_user_data_dir_s(256) ~= nil)
print('rime_api:get_user_data_dir_s passed: \"' .. rime_api:get_user_data_dir_s(256) .. '\"')
assert(rime_api:get_shared_data_dir_s(256) ~= nil)
print('rime_api:get_shared_data_dir_s passed: \"' .. rime_api:get_shared_data_dir_s(256) .. '\"')
assert(rime_api:get_prebuilt_data_dir_s(256) ~= nil)
print('rime_api:get_prebuilt_data_dir_s passed: \"' .. rime_api:get_prebuilt_data_dir_s(256) .. '\"')
assert(rime_api:get_sync_dir_s(256) ~= nil)
print('rime_api:get_sync_dir_s passed: \"' .. rime_api:get_sync_dir_s(256) .. '\"')
assert(rime_api:get_staging_dir_s(256) ~= nil)
print('rime_api:get_staging_dir_s passed: \"' .. rime_api:get_staging_dir_s(256) .. '\"')
----------------------------------------------------------------
assert(rime_api:get_version() ~= nil)
print('rime_api:get_version passed: \"' .. rime_api:get_version() .. '\"')
----------------------------------------------------------------

assert(rime_api:config_init(config) == true)
print('rime_api:config_init passed')
assert(rime_api:config_load_string(config, [[
a_string: a_string_loaded_from_string
a_item:
  - list_item1
  - list_item2
  - list_item3
map_item1: map_item1_value
map_item2: 233
]]) == true)
assert(config:get_string("a_string") == "a_string_loaded_from_string")
print('rime_api:config_load_string passed')
local item = RimeConfig()
assert(rime_api:config_get_item(config, "a_item", item) == true)
print('rime_api:config_get_item passed')
assert(item:set_string("@0", "list_item1_modified") == true)
assert(rime_api:config_set_item(config, "a_item", item) == true)
assert(rime_api:config_get_string(config, "a_item/@0", 256) == true, "list_item1_modified")
print('rime_api:config_set_item passed')
local config_to_clear = RimeConfig()
assert(rime_api:config_load_string(config_to_clear, [[
to_be_cleared: some_value
]]) == true)
assert(config_to_clear:get_string("to_be_cleared") == "some_value")
assert(rime_api:config_clear(config_to_clear, "to_be_cleared") == true)
print('rime_api:config_clear passed')
assert(config_to_clear:get_string("to_be_cleared") == nil)
print('rime_api:config_clear verified')
assert(rime_api:config_create_list(config_to_clear, "new_list") == true)
assert(rime_api:config_set_string(config_to_clear, "new_list/@0", "new_item1") == true)
assert(rime_api:config_set_string(config_to_clear, "new_list/@1", "new_item2") == true)
assert(rime_api:config_get_string(config_to_clear, "new_list/@0", 256) == true, "new_item1")
assert(rime_api:config_get_string(config_to_clear, "new_list/@1", 256) == true, "new_item2")
assert(rime_api:config_list_size(config_to_clear, "new_list") == 2)
print('rime_api:config_list_size passed')
print('rime_api:config_create_list passed')
assert(rime_api:config_create_map(config_to_clear, "new_map") == true)
assert(rime_api:config_set_string(config_to_clear, "new_map/key1", "value1") == true)
assert(rime_api:config_set_int(config_to_clear, "new_map/key2", 233) == true)
assert(rime_api:config_get_string(config_to_clear, "new_map/key1", 256) == true, "value1")
assert(rime_api:config_get_int(config_to_clear, "new_map/key2") == true, 233)
print('rime_api:config_create_map passed')
assert(rime_api:config_close(config) == true) -- init by config_init, shall use config_close to free object
assert(rime_api:cleanup_stale_sessions() == nil)
print('rime_api:cleanup_stale_sessions passed')
assert(rime_api:user_config_open("user", config) == true)
print('rime_api:user_config_open passed')
----------------------------------------------------------------
assert(rime_api:destroy_session(session) == true)
print('rime_api:destroy_session passed')
----------------------------------------------------------------
assert(rime_api:deployer_initialize() == nil)
print('rime_api:deployer_initialize passed')
assert(rime_api:sync_user_data() == true)
print('rime_api:sync_user_data passed')
rime_api:finalize()
print('rime_api:finalize passed')
rime_api = nil
traits = nil
collectgarbage("collect")
