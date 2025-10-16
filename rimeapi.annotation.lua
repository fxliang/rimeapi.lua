---@class RimeSession
---@field id integer -- raw RimeSessionId value
---@field str string -- pointer format of RimeSessionId

---@class RimeComposition
---@field length integer -- length of composition
---@field cursor_pos integer -- cursor position
---@field sel_start integer  -- select start
---@field sel_end integer    -- select end
---@field preedit string     -- preedit string
---@field __tostring fun(self: self): string

---@class RimeCandidate
---@field text string  -- text of candidate
---@field comment string  -- comment of candidate
---@field __tostring fun(self: self): string

---@class RimeMenu
---@field page_size integer -- page size
---@field page_no integer -- page number, 0 base
---@field is_last_page boolean -- is the current page the last page
---@field highlighted_candidate_index integer -- highlighted_candidate_index 0 base
---@field num_candidates integer -- number of candidates
---@field candidates RimeCandidate[] -- table of candidates
---@field select_keys string -- select keys string
---@field __tostring fun(self: self): string

---@class RimeCommit
---@field text string -- text to be committed
---@field __tostring fun(self: self): string

---@class RimeContext
---@field composition RimeComposition
---@field menu RimeMenu
---@field commit_text_preview string
---@field select_labels string

---@class RimeStatus
---@field schema_id string
---@field schema_name string
---@field is_disabled boolean
---@field is_composing boolean
---@field is_ascii_mode boolean
---@field is_full_shape boolean
---@field is_simplified boolean
---@field is_traditional boolean
---@field is_ascii_punct boolean
---@field __tostring fun(self: self): string

---@class RimeCandidateListIterator
---@field ptr lightuserdata
---@field index integer -- index of iterator, 0 base
---@field candidate RimeCandidate -- candidate of iterator

---@class RimeConfig
---@field reload fun(self: self, config_name: string): boolean
---@field open fun(self: self, config_name: string): boolean
---@field close fun(self: self): boolean
---@field get_int fun(self: self, key: string): integer
---@field get_string fun(self: self, key: string, buffer_size: integer|nil): string
---@field get_bool fun(self: self, key: string): boolean
---@field get_double fun(self: self, key: string): number
---@field get_cstring fun(self: self, key: string): string
---@field set_int fun(self: self, key: string, value: integer): boolean
---@field set_string fun(self: self, key: string, value: string): boolean
---@field set_bool fun(self: self, key: string, value: boolean): boolean
---@field set_double fun(self: self, key: string, value: number): boolean

---@class RimeConfigIterator
---@field index integer -- index of iterator, 0 base
---@field key string -- key string of iterator
---@field path string -- path of iterator

---@class RimeSchemaInfo
---@field name string
---@field author string
---@field description string
---@field schema_id string
---@field version string
---@field file_path string
---@field get_schema_id fun(self: self): string
---@field get_schema_name fun(self: self): string
---@field get_schema_author fun(self: self): string
---@field get_schema_description fun(self: self): string
---@field get_schema_file_path fun(self: self): string
---@field get_schema_version fun(self: self): string

---@class RimeSchemaListItem
---@field schema_id string
---@field name string
---@field schema_info RimeSchemaInfo

---@class RimeSchemaList
---@field size integer
---@field list RimeSchemaListItem[]

---@class RimeStringSlice
---@field str string
---@field length integer

---@class RimeTraits
---@field shared_data_dir string
---@field user_data_dir string
---@field distribution_name string
---@field distribution_code_name string
---@field distribution_version string
---@field app_name string
---@field min_log_level integer
---@field log_dir string
---@field prebuilt_data_dir string
---@field staging_dir string

---@class RimeCustomApi
---@field type string

---@class RimeModule
---@field initialize fun(self: self) :nil
---@field finalize fun(self: self) : nil
---@field get_api fun(self: self) : RimeCustomApi

---@class RimeApi
---@field setup fun(self: self, traits: RimeTraits): nil
---@field set_notification_handler fun(self: self, handler: (fun(context_object: any, session_id: integer, msg_type: string, msg_value: any)) | nil): nil
---@field initialize fun(self: self, traits: RimeTraits): nil
---@field finalize fun(self: self): nil
---@field start_maintenance fun(self: self, full_check: boolean): boolean
---@field is_maintenance_mode fun(self: self): boolean
---@field join_maintenance_thread fun(self: self): nil
---@field deployer_initialize fun(self: self, traits: RimeTraits): nil
---@field prebuild fun(self: self): boolean
---@field deploy fun(self: self): boolean
---@field deploy_schema fun(self: self, schema_file: string): boolean
---@field deploy_config_file fun(self: self, file_name: string, version_key: string): boolean
---@field sync_user_data fun(self: self): boolean
---@field create_session fun(self: self): RimeSession
---@field find_session fun(self: self, session: RimeSession|integer): boolean
---@field destroy_session fun(self: self, session: RimeSession|integer): boolean
---@field cleanup_stale_sessions fun(self: self): nil
---@field cleanup_all_sessions fun(self: self): nil
---@field process_key fun(self: self, session: RimeSession|integer, keycode: integer, mask: integer): boolean
---@field commit_composition fun(self: self, session: RimeSession|integer): boolean
---@field clear_composition fun(self: self, session: RimeSession|integer): nil
---@field get_commit fun(self: self, session: RimeSession|integer, commit: RimeCommit): boolean
---@field get_context fun(self: self, session: RimeSession|integer, context: RimeContext): boolean
---@field get_status fun(self: self, session: RimeSession|integer, status: RimeStatus): boolean
---@field free_commit fun(self: self, commit: RimeCommit): boolean
---@field free_context fun(self: self, context: RimeContext): boolean
---@field free_status fun(self: self, status: RimeStatus): boolean
---@field set_option fun(self: self, session: RimeSession|integer, option_name: string, value: boolean): nil
---@field get_option fun(self: self, session: RimeSession|integer, option_name: string): boolean
---@field set_property fun(self: self, session: RimeSession|integer, property_name: string, value: string): nil
---@field get_property fun(self: self, session: RimeSession|integer, property_name: string, buffer_size: integer|nil): string
---@field get_schema_list fun(self: self, schema_list: RimeSchemaList): boolean
---@field free_schema_list fun(self: self, schema_list: RimeSchemaList): nil
---@field get_current_schema fun(self: self, session: RimeSession|integer): string|nil
---@field select_schema fun(self: self, session: RimeSession|integer, schema_id: string): boolean
---@field schema_open fun(self: self, schema_id: string, config: RimeConfig): boolean
---@field config_open fun(self: self, schema_id: string, config: RimeConfig): boolean
---@field config_close fun(self: self, config: RimeConfig): boolean
---@field config_get_bool fun(self: self, config: RimeConfig, key: string): boolean|nil
---@field config_get_int fun(self: self, config: RimeConfig, key: string): integer|nil
---@field config_get_double fun(self: self, config: RimeConfig, key: string): number|nil
---@field config_get_string fun(self: self, config: RimeConfig, key: string, buffer_size: integer|nil): string|nil
---@field config_get_cstring fun(self: self, config: RimeConfig, key: string): string|nil
---@field config_update_signature fun(self: self, config: RimeConfig, signer: string): boolean
---@field config_begin_map fun(self: self, iter: RimeConfigIterator, config: RimeConfig, key: string): boolean
---@field config_next fun(self: self, iter: RimeConfigIterator): boolean
---@field config_end fun(self: self, iter: RimeConfigIterator): nil
---@field simulate_key_sequence fun(self: self, session: RimeSession|integer, key_sequence: string): boolean
---@field run_task fun(self: self, task_name: string): boolean
---@field find_module fun(self: self, module_name: string) : RimeModule|nil
---@field register_module fun(self: self, module: RimeModule) : boolean
---@field get_shared_data_dir fun(self: self): string
---@field get_user_data_dir fun(self: self): string
---@field get_sync_dir fun(self: self): string
---@field get_user_id fun(self: self): string
---@field get_user_data_sync_dir fun(self: self, buffer_size: integer|nil): string 
---@field config_init fun(self: self, config: RimeConfig): boolean
---@field config_load_string fun(self: self, config: RimeConfig, content: string): boolean
---@field config_set_bool fun(self: self, config: RimeConfig, key: string, value: boolean): boolean
---@field config_set_int fun(self: self, config: RimeConfig, key: string, value: integer): boolean
---@field config_set_double fun(self: self, config: RimeConfig, key: string, value: number): boolean
---@field config_set_string fun(self: self, config: RimeConfig, key: string, value: string): boolean
---@field config_get_item fun(self: self, config: RimeConfig, key: string, value: RimeConfig): boolean
---@field config_set_item fun(self: self, config: RimeConfig, key: string, value: RimeConfig): boolean
---@field config_clear fun(self: self, config: RimeConfig, key: string): boolean
---@field config_create_list fun(self: self, config: RimeConfig, key: string): boolean
---@field config_create_map fun(self: self, config: RimeConfig, key: string): boolean
---@field config_list_size fun(self: self, config: RimeConfig, key: string): integer
---@field config_begin_list fun(self: self, iter: RimeConfigIterator, config: RimeConfig, key: string): boolean
---@field get_input fun(self: self, session: RimeSession|integer): string
---@field get_caret_pos fun(self: self, session: RimeSession|integer): integer
---@field select_candidate fun(self: self, session: RimeSession|integer, index: integer): boolean -- index shall be 0 base
---@field get_version fun(self: self): string
---@field set_caret_pos fun(self: self, session: RimeSession|integer, pos: integer): nil
---@field select_candidate_on_current_page fun(self: self, session: RimeSession|integer, index: integer): boolean -- index shall be 0 base
---@field candidate_list_begin fun(self: self, session: RimeSession|integer, iter: RimeCandidateListIterator): boolean
---@field candidate_list_next fun(self: self, iter: RimeCandidateListIterator): boolean
---@field candidate_list_end fun(self: self, iter: RimeCandidateListIterator): nil
---@field user_config_open fun(self: self, config_id: string, config: RimeConfig): boolean
---@field candidate_list_from_index fun(self: self, session: RimeSession|integer, iter: RimeCandidateListIterator, start_index: integer): boolean -- index shall be 0 base
---@field get_prebuilt_data_dir fun(self: self): string
---@field get_staging_dir fun(self: self): string
---@field get_state_label fun(self: self, session: RimeSession|integer, option: string, state: boolean): string
---@field delete_candidate fun(self: self, session: RimeSession|integer, index: integer): boolean -- index shall be 0 base
---@field delete_candidate_on_current_page fun(self: self, session: RimeSession|integer, index: integer): boolean -- index shall be 0 base
---@field get_state_label_abbreviated fun(self: self, session: RimeSession|integer, option: string, state: boolean, abbreviated: boolean): RimeStringSlice
---@field set_input fun(self: self, session: RimeSession|integer, input: string): boolean
---@field get_shared_data_dir_s fun(self: self, buffer_size: integer|nil): string
---@field get_user_data_dir_s fun(self: self, buffer_size: integer|nil): string
---@field get_sync_dir_s fun(self: self, buffer_size: integer|nil): string
---@field get_staging_dir_s fun(self: self, buffer_size: integer|nil): string
---@field get_prebuilt_data_dir_s fun(self: self, buffer_size: integer|nil): string
---@field highlight_candidate fun(self: self, session: RimeSession|integer, index: integer): boolean -- index shall be 0 base
---@field highlight_candidate_on_current_page fun(self: self, session: RimeSession|integer, index: integer): boolean -- index shall be 0 base
---@field change_page fun(self: self, session: RimeSession|integer, backward: boolean): boolean

---@class RimeCustomSettings
---@class RimeSwitcherSettings
---@class RimeUserDictIterator


---@class RimeLeversApi
---@field custom_settings_init fun(self: self, config_id: string, generator_id: string): RimeCustomSettings
---@field custom_settings_destroy fun(self: self, settings: RimeCustomSettings): nil
---@field load_settings fun(self: self, settings: RimeCustomSettings|RimeSwitcherSettings): boolean
---@field save_settings fun(self: self, settings: RimeCustomSettings): boolean
---@field is_first_run fun(self: self, settings: RimeCustomSettings): boolean
---@field customize_bool fun(self: self, settings: RimeCustomSettings, key: string, value: boolean): boolean
---@field customize_int fun(self: self, settings: RimeCustomSettings, key: string, value: integer): boolean
---@field customize_string fun(self: self, settings: RimeCustomSettings, key: string, value: string): boolean
---@field customize_double fun(self: self, settings: RimeCustomSettings, key: string, value: number): boolean
---@field settings_is_modified fun(self: self, settings: RimeCustomSettings): boolean
---@field settings_get_config fun(self: self, settings: RimeCustomSettings, config: RimeConfig): boolean
---@field switcher_settings_init fun(self: self): RimeSwitcherSettings
---@field get_available_schema_list fun(self: self, switcher_settings: RimeSwitcherSettings, schema_list: RimeSchemaList): boolean
---@field get_selected_schema_list fun(self: self, switcher_settings: RimeSwitcherSettings, schema_list: RimeSchemaList): boolean
---@field schema_list_destroy fun(self: self, schema_list: RimeSchemaList): nil
---@field get_schema_id fun(self: self, schema_info: RimeSchemaInfo): string
---@field get_schema_name fun(self: self, schema_info: RimeSchemaInfo): string
---@field get_schema_author fun(self: self, schema_info: RimeSchemaInfo): string
---@field get_schema_description fun(self: self, schema_info: RimeSchemaInfo): string
---@field get_schema_file_path fun(self: self, schema_info: RimeSchemaInfo): string
---@field get_schema_version fun(self: self, schema_info: RimeSchemaInfo): string
---@field select_schemas fun(self: self, switcher_settings: RimeSwitcherSettings, schema_ids: string[], count: integer): boolean
---@field get_hotkeys fun(self: self, switcher_settings: RimeSwitcherSettings): string|nil
---@field set_hotkeys fun(self: self, switcher_settings: RimeSwitcherSettings, hotkeys: string): false --not implemented yet in librime
---@field user_dict_iterator_init fun(self: self, iter: RimeUserDictIterator): boolean
---@field user_dict_iterator_destroy fun(self: self, iter: RimeUserDictIterator): nil
---@field next_user_dict fun(self: self, iter: RimeUserDictIterator): string
---@field backup_user_dict fun(self: self, dict_name: string): boolean
---@field restore_user_dict fun(self: self, snapshot_file: string): boolean
---@field export_user_dict fun(self: self, dict_name: string, text_file: string): integer
---@field import_user_dict fun(self: self, dict_name: string, text_file: string): integer
---@field customize_item fun(self: self, settings: RimeCustomSettings, key: string, value: RimeConfig): boolean
---@field type string

---@return RimeApi
function RimeApi() end
---@return RimeContext
function RimeContext() end
---@return RimeStatus
function RimeStatus() end
---@return RimeCommit
function RimeCommit() end
---@return RimeConfig
function RimeConfig() end
---@return RimeConfigIterator
function RimeConfigIterator() end
---@return RimeSchemaList
function RimeSchemaList() end
---@return RimeCandidateListIterator
function RimeCandidateListIterator() end
---@return RimeTraits
function RimeTraits() end
---@return nil
---@param path string
function os.mkdir(path) end
---@return RimeLeversApi
function RimeLeversApi() end
---@return RimeLeversApi | nil
---@param api RimeCustomApi
function ToRimeLeversApi(api) end
