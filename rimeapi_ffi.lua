-- lua api shall not exported in librime
local ffi = require('ffi')
-------------------------------------------------------------------------------
ffi.cdef[[
  typedef uintptr_t RimeSessionId;
  typedef struct {
    int data_size;
    const char* shared_data_dir;
    const char* user_data_dir;
    const char* distribution_name;
    const char* distribution_code_name;
    const char* distribution_version;
    const char* app_name;
    const char** modules;
    int min_log_level;
    const char* log_dir;
    const char* prebuilt_data_dir;
    const char* staging_dir;
  } RimeTraits;

  typedef struct {
    int length;
    int cursor_pos;
    int sel_start;
    int sel_end;
    char* preedit;
  } RimeComposition;

  typedef struct {
    char* text;
    char* comment;
    void* reserved;
  } RimeCandidate;

  typedef struct {
    int page_size;
    int page_no;
    int is_last_page;
    int highlighted_candidate_index;
    int num_candidates;
    RimeCandidate* candidates;
    char* select_keys;
  } RimeMenu;

  typedef struct {
    int data_size;
    char* text;
  } RimeCommit;

  typedef struct {
    int data_size;
    RimeComposition composition;
    RimeMenu menu;
    char* commit_text_preview;
    char** select_labels;
  } RimeContext;

  typedef struct {
    int data_size;
    char* schema_id;
    char* schema_name;
    int is_disabled;
    int is_composing;
    int is_ascii_mode;
    int is_full_shape;
    int is_simplified;
    int is_traditional;
    int is_ascii_punct;
  } RimeStatus;

  typedef struct {
    void* ptr;
    int index;
    RimeCandidate candidate;
  } RimeCandidateListIterator;

  typedef struct {
    void* ptr;
  } RimeConfig;

  typedef struct {
    void* list;
    void* map;
    int index;
    const char* key;
    const char* path;
  } RimeConfigIterator;

  typedef struct {
    char* schema_id;
    char* name;
    void* reserved;
  } RimeSchemaListItem;

  typedef struct {
    size_t size;
    RimeSchemaListItem* list;
  } RimeSchemaList;

  typedef struct {
    const char* str;
    size_t length;
  } RimeStringSlice;

  typedef void (*RimeNotificationHandler)(void* context_object,
                                          RimeSessionId session_id,
                                          const char* message_type,
                                          const char* message_value);

  typedef void RimeProtoBuilder;

  typedef struct {
    int data_size;
  } RimeCustomApi;

  typedef struct {
    int data_size;
    const char* module_name;
    void (*initialize)(void);
    void (*finalize)(void);
    RimeCustomApi* (*get_api)(void);
  } RimeModule;

  typedef struct {
    int data_size;
    void (*setup)(RimeTraits* traits);
    void (*set_notification_handler)(RimeNotificationHandler handler, void* context_object);
    void (*initialize)(RimeTraits* traits);
    void (*finalize)(void);
    int (*start_maintenance)(int full_check);
    int (*is_maintenance_mode)(void);
    void (*join_maintenance_thread)(void);
    void (*deployer_initialize)(RimeTraits* traits);
    int (*prebuild)(void);
    int (*deploy)(void);
    int (*deploy_schema)(const char* schema_file);
    int (*deploy_config_file)(const char* file_name, const char* version_key);
    int (*sync_user_data)(void);
    RimeSessionId (*create_session)(void);
    int (*find_session)(RimeSessionId session_id);
    int (*destroy_session)(RimeSessionId session_id);
    void (*cleanup_stale_sessions)(void);
    void (*cleanup_all_sessions)(void);
    int (*process_key)(RimeSessionId session_id, int keycode, int mask);
    int (*commit_composition)(RimeSessionId session_id);
    void (*clear_composition)(RimeSessionId session_id);
    int (*get_commit)(RimeSessionId session_id, RimeCommit* commit);
    int (*free_commit)(RimeCommit* commit);
    int (*get_context)(RimeSessionId session_id, RimeContext* context);
    int (*free_context)(RimeContext* ctx);
    int (*get_status)(RimeSessionId session_id, RimeStatus* status);
    int (*free_status)(RimeStatus* status);
    void (*set_option)(RimeSessionId session_id, const char* option, int value);
    int (*get_option)(RimeSessionId session_id, const char* option);
    void (*set_property)(RimeSessionId session_id, const char* prop, const char* value);
    int (*get_property)(RimeSessionId session_id, const char* prop, char* value, size_t buffer_size);
    int (*get_schema_list)(RimeSchemaList* schema_list);
    void (*free_schema_list)(RimeSchemaList* schema_list);
    int (*get_current_schema)(RimeSessionId session_id, char* schema_id, size_t buffer_size);
    int (*select_schema)(RimeSessionId session_id, const char* schema_id);
    int (*schema_open)(const char* schema_id, RimeConfig* config);
    int (*config_open)(const char* config_id, RimeConfig* config);
    int (*config_close)(RimeConfig* config);
    int (*config_get_bool)(RimeConfig* config, const char* key, int* value);
    int (*config_get_int)(RimeConfig* config, const char* key, int* value);
    int (*config_get_double)(RimeConfig* config, const char* key, double* value);
    int (*config_get_string)(RimeConfig* config, const char* key, char* value, size_t buffer_size);
    const char* (*config_get_cstring)(RimeConfig* config, const char* key);
    int (*config_update_signature)(RimeConfig* config, const char* signer);
    int (*config_begin_map)(RimeConfigIterator* iterator, RimeConfig* config, const char* key);
    int (*config_next)(RimeConfigIterator* iterator);
    void (*config_end)(RimeConfigIterator* iterator);
    int (*simulate_key_sequence)(RimeSessionId session_id, const char* key_sequence);
    int (*register_module)(RimeModule* module);
    RimeModule* (*find_module)(const char* module_name);
    int (*run_task)(const char* task_name);
    const char* (*get_shared_data_dir)(void);
    const char* (*get_user_data_dir)(void);
    const char* (*get_sync_dir)(void);
    const char* (*get_user_id)(void);
    void (*get_user_data_sync_dir)(char* dir, size_t buffer_size);
    int (*config_init)(RimeConfig* config);
    int (*config_load_string)(RimeConfig* config, const char* yaml);
    int (*config_set_bool)(RimeConfig* config, const char* key, int value);
    int (*config_set_int)(RimeConfig* config, const char* key, int value);
    int (*config_set_double)(RimeConfig* config, const char* key, double value);
    int (*config_set_string)(RimeConfig* config, const char* key, const char* value);
    int (*config_get_item)(RimeConfig* config, const char* key, RimeConfig* value);
    int (*config_set_item)(RimeConfig* config, const char* key, RimeConfig* value);
    int (*config_clear)(RimeConfig* config, const char* key);
    int (*config_create_list)(RimeConfig* config, const char* key);
    int (*config_create_map)(RimeConfig* config, const char* key);
    size_t (*config_list_size)(RimeConfig* config, const char* key);
    int (*config_begin_list)(RimeConfigIterator* iterator, RimeConfig* config, const char* key);
    const char* (*get_input)(RimeSessionId session_id);
    size_t (*get_caret_pos)(RimeSessionId session_id);
    int (*select_candidate)(RimeSessionId session_id, size_t index);
    const char* (*get_version)(void);
    void (*set_caret_pos)(RimeSessionId session_id, size_t caret_pos);
    int (*select_candidate_on_current_page)(RimeSessionId session_id, size_t index);
    int (*candidate_list_begin)(RimeSessionId session_id, RimeCandidateListIterator* iterator);
    int (*candidate_list_next)(RimeCandidateListIterator* iterator);
    void (*candidate_list_end)(RimeCandidateListIterator* iterator);
    int (*user_config_open)(const char* config_id, RimeConfig* config);
    int (*candidate_list_from_index)(RimeSessionId session_id, RimeCandidateListIterator* iterator, int index);
    const char* (*get_prebuilt_data_dir)(void);
    const char* (*get_staging_dir)(void);
    void (*commit_proto)(RimeSessionId session_id, RimeProtoBuilder* commit_builder);
    void (*context_proto)(RimeSessionId session_id, RimeProtoBuilder* context_builder);
    void (*status_proto)(RimeSessionId session_id, RimeProtoBuilder* status_builder);
    const char* (*get_state_label)(RimeSessionId session_id, const char* option_name, int state);
    int (*delete_candidate)(RimeSessionId session_id, size_t index);
    int (*delete_candidate_on_current_page)(RimeSessionId session_id, size_t index);
    RimeStringSlice (*get_state_label_abbreviated)(RimeSessionId session_id, const char* option_name, int state, int abbreviated);
    int (*set_input)(RimeSessionId session_id, const char* input);
    void (*get_shared_data_dir_s)(char* dir, size_t buffer_size);
    void (*get_user_data_dir_s)(char* dir, size_t buffer_size);
    void (*get_prebuilt_data_dir_s)(char* dir, size_t buffer_size);
    void (*get_staging_dir_s)(char* dir, size_t buffer_size);
    void (*get_sync_dir_s)(char* dir, size_t buffer_size);
    int (*highlight_candidate)(RimeSessionId session_id, size_t index);
    int (*highlight_candidate_on_current_page)(RimeSessionId session_id, size_t index);
    int (*change_page)(RimeSessionId session_id, int backward);
  } RimeApi;

  typedef struct {
    char placeholder;
  } RimeCustomSettings;

  typedef struct {
    char placeholder;
  } RimeSwitcherSettings;

  typedef struct {
    char placeholder;
  } RimeSchemaInfo;

  typedef struct {
    void* ptr;
    size_t i;
  } RimeUserDictIterator;
  typedef int Bool;
  typedef struct {
    int data_size;
    RimeCustomSettings* (*custom_settings_init)(const char* config_id,
    const char* generator_id);
    void (*custom_settings_destroy)(RimeCustomSettings* settings);
    Bool (*load_settings)(RimeCustomSettings* settings);
    Bool (*save_settings)(RimeCustomSettings* settings);
    Bool (*customize_bool)(RimeCustomSettings* settings,
    const char* key,
    Bool value);
    Bool (*customize_int)(RimeCustomSettings* settings,
    const char* key,
    int value);
    Bool (*customize_double)(RimeCustomSettings* settings,
    const char* key,
    double value);
    Bool (*customize_string)(RimeCustomSettings* settings,
    const char* key,
    const char* value);
    Bool (*is_first_run)(RimeCustomSettings* settings);
    Bool (*settings_is_modified)(RimeCustomSettings* settings);
    Bool (*settings_get_config)(RimeCustomSettings* settings, RimeConfig* config);

    RimeSwitcherSettings* (*switcher_settings_init)();
    Bool (*get_available_schema_list)(RimeSwitcherSettings* settings,
    RimeSchemaList* list);
    Bool (*get_selected_schema_list)(RimeSwitcherSettings* settings,
    RimeSchemaList* list);
    void (*schema_list_destroy)(RimeSchemaList* list);
    const char* (*get_schema_id)(RimeSchemaInfo* info);
    const char* (*get_schema_name)(RimeSchemaInfo* info);
    const char* (*get_schema_version)(RimeSchemaInfo* info);
    const char* (*get_schema_author)(RimeSchemaInfo* info);
    const char* (*get_schema_description)(RimeSchemaInfo* info);
    const char* (*get_schema_file_path)(RimeSchemaInfo* info);
    Bool (*select_schemas)(RimeSwitcherSettings* settings,
    const char* schema_id_list[],
    int count);
    const char* (*get_hotkeys)(RimeSwitcherSettings* settings);
    Bool (*set_hotkeys)(RimeSwitcherSettings* settings, const char* hotkeys);

    Bool (*user_dict_iterator_init)(RimeUserDictIterator* iter);
    void (*user_dict_iterator_destroy)(RimeUserDictIterator* iter);
    const char* (*next_user_dict)(RimeUserDictIterator* iter);
    Bool (*backup_user_dict)(const char* dict_name);
    Bool (*restore_user_dict)(const char* snapshot_file);
    int (*export_user_dict)(const char* dict_name, const char* text_file);
    int (*import_user_dict)(const char* dict_name, const char* text_file);

    // patch a list or a map
    Bool (*customize_item)(RimeCustomSettings* settings,
    const char* key,
    RimeConfig* value);

  } RimeLeversApi;

  typedef struct {
    RimeSessionId id;
  }RimeSession;
  RimeApi* rime_get_api(void);
]]

function to_acp_path(path, cp)
  local real_path = path
  if ffi and ffi.os == "Windows" then
    ffi.cdef[[
      int MultiByteToWideChar(unsigned int CodePage, unsigned long dwFlags,
                              const char *lpMultiByteStr, int cbMultiByte,
                              wchar_t *lpWideCharStr, int cchWideChar);
      int WideCharToMultiByte(unsigned int CodePage, unsigned long dwFlags,
                              const wchar_t *lpWideCharStr, int cchWideChar,
                              char *lpMultiByteStr, int cbMultiByte,
                              const char *lpDefaultChar, int *lpUsedDefaultChar);
      unsigned int GetACP(void);
    ]]

    -- cp -> UTF-16
    cp = cp or 65001
    local wlen = ffi.C.MultiByteToWideChar(cp, 0, path, -1, nil, 0)
    if wlen == 0 then return false end
    local wpath = ffi.new("wchar_t[?]", wlen)
    ffi.C.MultiByteToWideChar(cp, 0, path, -1, wpath, wlen)

    -- UTF-16 -> ACP
    local acp = ffi.C.GetACP()
    local acplen = ffi.C.WideCharToMultiByte(acp, 0, wpath, -1, nil, 0, nil, nil)
    if acplen == 0 then return false end
    local acppath = ffi.new("char[?]", acplen)
    ffi.C.WideCharToMultiByte(acp, 0, wpath, -1, acppath, acplen, nil, nil)

    real_path = ffi.string(acppath)
  end
  return real_path
end
-------------------------------------------------------------------------------
--- os.mkdir function
os.mkdir = type(os.mkdir) == 'function' and os.mkdir or function (path, codepage)
  if type(path) ~= "string" or path == "" then return false end
  if ffi.os == "Windows" then
    ffi.cdef[[
      int CreateDirectoryA(const char *lpPathName, void *lpSecurityAttributes);
      unsigned long GetLastError();
    ]]

    local r = ffi.C.CreateDirectoryA(to_acp_path(path, codepage), nil)
    return (r ~= 0) and true or (ffi.C.GetLastError() == 183)
  else
    ffi.cdef[[
      typedef struct DIR DIR;
      DIR *opendir(const char *name);
      int closedir(DIR *dirp);
      int mkdir(const char *pathname, unsigned int mode);
    ]]
    local opendir = ffi.C.opendir
    local closedir = ffi.C.closedir
    local mkdirc = ffi.C.mkdir
    local SEP = "/"
    local DEFAULT_MODE = 493 -- 0755

    -- normalize path components
    local comps = {}
    for token in string.gmatch(path, "[^/]+") do
      comps[#comps + 1] = token
    end
    local is_abs = path:sub(1,1) == SEP
    local cur = is_abs and SEP or ""
    -- handle root or "." cases
    if #comps == 0 then
      local d = opendir(cur == "" and "." or cur)
      if d ~= nil then closedir(d); return true end
      return mkdirc(cur, DEFAULT_MODE) == 0
    end

    for i = 1, #comps do
      if cur ~= "" and cur:sub(-1) ~= SEP then cur = cur .. SEP end
      cur = cur .. comps[i]
      local d = opendir(cur)
      if d ~= nil then closedir(d) -- already exists
      else
        local r = mkdirc(cur, DEFAULT_MODE)
        if r ~= 0 then
          local errno = ffi.errno()
          -- EEXIST (race) treat as success if now a directory
          if errno == 17 then
            local d2 = opendir(cur)
            if d2 ~= nil then closedir(d2) else return false end
          else
            return false
          end
        end
      end
    end
    return true
  end
end
-------------------------------------------------------------------------------
local safestr = function(s)
  if s == nil then return nil end
  local ok, res = pcall(ffi.string, s)
  if ok then return res else return nil end
end
--- load librime and get rime api
local api
local rime_get_api_func
local is_termux = os.getenv('PREFIX') and string.match(os.getenv("PREFIX") or '', ('/data/data/com.termux/files/usr')) ~= nil or false
if ffi.os == "Linux" or ffi.os == "OSX" then
  ffi.cdef[[
    void* dlopen(const char *filename, int flag);
    void* dlsym(void *handle, const char *symbol);
    const char* dlerror(void);
    int dlclose(void *handle);
  ]]
  local ok, bit = pcall(require, "bit")  -- LuaJIT bit lib
  local bor = ok and bit.bor or function(a,b) return a + b end
  local RTLD_NOW = 2
  local RTDL_DEEPBIND = ( is_termux or ffi.os == 'OSX' ) and 0 or 0x8
  local libname = ffi.os == 'OSX' and "librime.dylib" or "librime.so"
  local handle = ffi.C.dlopen(libname, bor(RTLD_NOW, RTDL_DEEPBIND))
  local sym = ffi.C.dlsym(handle, "rime_get_api")
  if sym == nil then
    local err = ffi.C.dlerror()
    error("failed to find symbol rime_get_api: " .. safestr(err))
  end
  rime_get_api_func = ffi.cast("RimeApi* (*)()", sym)
  api = rime_get_api_func()
  function set_console_codepage(codepage) end -- noop on linux
else
  ffi.cdef[[
    typedef void* HMODULE;
    typedef void* HANDLE;
    typedef const char* LPCSTR;
    typedef void* FARPROC;
    unsigned int SetConsoleOutputCP(unsigned int code_page);
    unsigned int SetConsoleCP(unsigned int code_page);
    unsigned int GetConsoleOutputCP();
    HMODULE LoadLibraryA(LPCSTR lpLibFileName);
    HANDLE GetProcAddress(HMODULE hModule, LPCSTR lpProcName);
  ]]
  function set_console_codepage(codepage)
    if codepage == nil then codepage = 65001 end -- UTF-8
    local orig_cp = ffi.C.GetConsoleOutputCP()
    ffi.C.SetConsoleOutputCP(codepage)
    ffi.C.SetConsoleCP(codepage)
    return orig_cp
  end
  local librime = ffi.C.LoadLibraryA('rime.dll')
  if not librime then error('failed to load librime') end
  rime_get_api_func = ffi.cast("RimeApi* (*)()", ffi.C.GetProcAddress(librime, "rime_get_api"))
  api = rime_get_api_func()
  if not api then error('failed to get rime api') end
end
if not api then error('failed to get rime api') end

local function ensure_api()
  if api == nil then
    if not rime_get_api_func then error('rime_get_api not initialized') end
    api = rime_get_api_func()
    if not api then error('failed to get rime api after finalize') end
  end
  return api
end

local levers_data_size = ffi.sizeof("RimeLeversApi") - ffi.sizeof("int")

local function get_levers_api()
  local current_api = ensure_api()
  local module = current_api.find_module and current_api.find_module("levers")
  if module == nil or module == ffi.NULL then
    error("levers module not available")
  end
  local ptr = module.get_api and module.get_api()
  if ptr == nil or ptr == ffi.NULL then
    error("levers api not available")
  end
  local levers_api = ffi.cast("RimeLeversApi*", ptr)
  if levers_api.data_size ~= levers_data_size then
    levers_api.data_size = levers_data_size
  end
  return levers_api
end

function file_exists(path, cp)
  if type(path) ~= 'string' or path == '' then return false end
  if os.isdir(path, cp) then return true end
  local real_path = to_acp_path(path, cp)
  local f = io.open(real_path, 'r')
  if f then
    f:close()
    return true
  end
  return false
end
-------------------------------------------------------------------------------
local Set = {}
Set.__index = Set
function Set.new() return setmetatable({_data = {}}, Set) end
function Set:insert(value) self._data[value] = true end
function Set:erase(value) self._data[value] = nil end
function Set:find(value) return self._data[value] ~= nil end
function Set:values()
  local out = {}
  for k, _ in pairs(self._data) do out[#out + 1] = k end
  return out
end
-------------------------------------------------------------------------------
local cfg_borrowed_set = Set.new()
local schemalist_borrowed_set = Set.new()
local function is_config_borrowed(cfg) return cfg and cfg_borrowed_set:find(cfg._c) or false end
local function is_schemalist_borrowed(schlist) return schlist and schemalist_borrowed_set:find(schlist._c.list) or false end
local function set_config_borrowed(cfg, borrowed)
  if not cfg then return end
  if borrowed then cfg_borrowed_set:insert(cfg._c)
  else cfg_borrowed_set:erase(cfg._c)
  end
end

function RimeTraits()
  local traits = ffi.new('RimeTraits')
  traits.data_size = ffi.sizeof('RimeTraits') - ffi.sizeof('int') -- 只读
  local obj = {
    _c = traits,
    _refs = {},
    _keys = {
      "data_size",
      "shared_data_dir",
      "user_data_dir",
      "distribution_name",
      "distribution_code_name",
      "distribution_version",
      "app_name",
      "modules",
      "min_log_level",
      "log_dir",
      "prebuilt_data_dir",
      "staging_dir",
    }
  }
  local function set_cstr(field, s)
    if s == nil then
      obj._c[field] = nil
      obj._refs[field] = nil
      return
    end
    s = tostring(s)
    local buf = ffi.new("char[?]", #s + 1, s)
    obj._refs[field] = buf
    obj._c[field] = ffi.cast("const char *", buf)
  end
  local function set_modules(tbl)
    if tbl == nil then
      obj._c.modules = nil
      obj._refs.modules = nil
      return
    end
    assert(type(tbl) == "table", "modules must be a table of strings or nil")
    local n = #tbl
    local arr = ffi.new("const char *[?]", n + 1) -- 多一个 nil 结尾
    local strrefs = {}
    for i = 1, n do
      local s = tostring(tbl[i] or "")
      local buf = ffi.new("char[?]", #s + 1, s)
      strrefs[i] = buf
      arr[i - 1] = ffi.cast("const char *", buf)
    end
    arr[n] = nil
    obj._refs.modules = { arr = arr, strs = strrefs }
    obj._c.modules = arr
  end

  local mt = {
    __index = function(_, k)
      if k == "modules" then
        local arr = obj._c.modules
        if arr == nil then return nil end
        local out = {}
        local i = 0
        while arr[i] ~= nil do
          out[#out + 1] = ffi.string(arr[i])
          i = i + 1
        end
        return out
      end

      if k == "data_size" then return obj._c.data_size end
      if k == "min_log_level" then return tonumber(obj._c.min_log_level) end
      if k == 'type' then return 'RimeTraits' end

      local v = obj._c[k]
      if v == nil then return nil end
      -- 对 const char* 转为 Lua 字符串
      if ffi.istype("const char *", v) or ffi.istype("char *", v) then
        return ffi.string(v)
      end
      return v
    end,

    __newindex = function(_, k, v)
      if k == "data_size" then
        error("data_size is read-only")
      end
      if k == "modules" then
        set_modules(v)
        return
      end
      if k == "min_log_level" then
        obj._c.min_log_level = tonumber(v) or 0
        return
      end
      -- 其他字符串字段
      if v == nil then
        obj._c[k] = nil
        obj._refs[k] = nil
        return
      end
      set_cstr(k, v)
    end,

    __pairs = function(t)
      local i = 0
      local keys = obj._keys
      return function()
        i = i + 1
        local k = keys[i]
        if not k then return nil end
        return k, t[k]
      end
    end
  }
  setmetatable(obj, mt)
  return obj
end
-------------------------------------------------------------------------------
function RimeCommit()
  local commit = ffi.new('RimeCommit')
  commit.data_size = ffi.sizeof('RimeCommit') - ffi.sizeof('int')
  local c = ffi.gc(commit,  function(cdata) ensure_api().free_commit(cdata) end)
  local obj = { _c = c }
  local mt = {
    __index = function(_, k)
      if k == 'text' then return safestr(obj._c.text)
      elseif k == 'type' then return 'RimeCommit' end
    end,
    __newindex = function(_, k, v) error("RimeCommit is read-only") end,
    __gc = function()
      if api ~= nil then api.free_commit(obj._c) end
    end,
  }
  setmetatable(obj, mt)
  return obj
end
-------------------------------------------------------------------------------
function RimeStatus()
  local status = ffi.new("RimeStatus")
  status.data_size = ffi.sizeof("RimeStatus") - ffi.sizeof("int")
  local c = ffi.gc(status, function(sdata) ensure_api().free_status(sdata) end)
  local obj = { _c = c }
  local mt = {
    __index = function(_, k)
      if k == 'schema_id' then return safestr(obj._c.schema_id)
      elseif k == 'schema_name' then return safestr(obj._c.schema_name)
      elseif k == 'is_disabled' then return obj._c.is_disabled ~= 0
      elseif k == 'is_composing' then return obj._c.is_composing ~= 0
      elseif k == 'is_ascii_mode' then return obj._c.is_ascii_mode ~= 0
      elseif k == 'is_full_shape' then return obj._c.is_full_shape ~= 0
      elseif k == 'is_simplified' then return obj._c.is_simplified ~= 0
      elseif k == 'is_traditional' then return obj._c.is_traditional ~= 0
      elseif k == 'is_ascii_punct' then return obj._c.is_ascii_punct ~= 0
      elseif k == 'type' then return 'RimeStatus'
      elseif k == '__tostring' then
        return function()
          local repr = "{\n"
          if obj._c.schema_id ~= nil then
            repr = repr .. string.format("  schema_id=\"%s\", \n", safestr(obj._c.schema_id))
          end
          if obj._c.schema_name ~= nil then
            repr = repr .. string.format("  schema_name=\"%s\", \n", safestr(obj._c.schema_name))
          end
          repr = repr .. string.format("  is_disabled=%s, \n", tostring(obj._c.is_disabled ~= 0))
          repr = repr .. string.format("  is_composing=%s, \n", tostring(obj._c.is_composing ~= 0))
          repr = repr .. string.format("  is_ascii_mode=%s, \n", tostring(obj._c.is_ascii_mode ~= 0))
          repr = repr .. string.format("  is_full_shape=%s, \n", tostring(obj._c.is_full_shape ~= 0))
          repr = repr .. string.format("  is_simplified=%s, \n", tostring(obj._c.is_simplified ~= 0))
          repr = repr .. string.format("  is_traditional=%s, \n", tostring(obj._c.is_traditional ~= 0))
          repr = repr .. string.format("  is_ascii_punct=%s \n}", tostring(obj._c.is_ascii_punct ~= 0))
          return repr
        end
      end
    end,
    __newindex = function(_, k, v) error("RimeStatus is read-only") end,
  }
  setmetatable(obj, mt)
  return obj
end
-------------------------------------------------------------------------------
function RimeComposition()
  local composition = ffi.new("RimeComposition")
  composition.length = 0
  composition.cursor_pos = 0
  composition.sel_start = 0
  composition.sel_end = 0
  composition.preedit = nil
  local obj = { _c = composition }
  local mt = {
    __index = function(_, k)
      if k == 'length' then return tonumber(obj._c.length)
      elseif k == 'cursor_pos' then return tonumber(obj._c.cursor_pos)
      elseif k == 'sel_start' then return tonumber(obj._c.sel_start)
      elseif k == 'sel_end' then return tonumber(obj._c.sel_end)
      elseif k == 'preedit' then return safestr(obj._c.preedit) or ''
      elseif k == 'type' then return 'RimeComposition'
      elseif k == '__tostring' then
        return function()
          local repr = "{\n"
          if obj._c.preedit ~= nil then
            repr = repr .. string.format("  preedit=\"%s\",\n", safestr(obj._c.preedit))
          end
          repr = repr .. string.format("  length=%d,\n", tonumber(obj._c.length))
          repr = repr .. string.format("  cursor_pos=%d,\n", tonumber(obj._c.cursor_pos))
          repr = repr .. string.format("  sel_start=%d,\n", tonumber(obj._c.sel_start))
          repr = repr .. string.format("  sel_end=%d\n}", tonumber(obj._c.sel_end))
          return repr
        end
      end
    end,
    __newindex = function(_, k, v) error("RimeComposition is read-only") end,
  }
  setmetatable(obj, mt)
  return obj
end

function RimeCandidate()
  local candidate = ffi.new("RimeCandidate")
  candidate.text = nil
  candidate.comment = nil
  candidate.reserved = nil
  local obj = { _c = candidate }
  local mt = {
    __index = function(_, k)
      if k == 'text' then return safestr(obj._c.text) or ''
      elseif k == 'comment' then return safestr(obj._c.comment) or ''
      elseif k == 'type' then return 'RimeCandidate'
      elseif k == '__tostring' then
        return function()
          local repr = "{"
          if obj._c.text ~= nil then
            repr = repr .. string.format("  text=\"%s\"", safestr(obj._c.text) or '')
          end
          if obj._c.comment ~= nil then
            repr = repr .. string.format(", comment=\"%s\"", safestr(obj._c.comment) or '')
          end
          repr = repr .. " }"
          return repr
        end
      end
    end,
    __newindex = function(_, k, v) error("RimeCandidate is read-only") end,
  }
  setmetatable(obj, mt)
  return obj
end

function RimeCandidateListIterator()
  local iterator = ffi.new("RimeCandidateListIterator")
  iterator.ptr = nil
  iterator.index = 0
  iterator.candidate.text = nil
  iterator.candidate.comment = nil
  iterator.candidate.reserved = nil
  local obj = { _c = iterator }
  local mt = {
    __index = function(_, k)
      if k == 'index' then return tonumber(obj._c.index)
      elseif k == 'index' then return tonumber(obj._c.index)
      elseif k == 'type' then return 'RimeCandidateListIterator'
      elseif k == 'candidate' then
        local cand = RimeCandidate()
        ffi.copy(cand._c, obj._c.candidate, ffi.sizeof("RimeCandidate"))
        return cand
      end
    end,
    __newindex = function(_, k, v) error("RimeCandidateListIterator is read-only") end,
  }
  setmetatable(obj, mt)
  return obj
end

function RimeMenu()
  local menu = ffi.new("RimeMenu")
  menu.page_size = 0
  menu.page_no = 0
  menu.is_last_page = 0
  menu.highlighted_candidate_index = 0
  menu.num_candidates = 0
  menu.candidates = nil
  menu.select_keys = nil
  local obj = { _c = menu }
  local mt = {
    __index = function(_, k)
      if k == 'page_size' then return tonumber(obj._c.page_size)
      elseif k == 'page_no' then return tonumber(obj._c.page_no)
      elseif k == 'is_last_page' then return obj._c.is_last_page ~= 0
      elseif k == 'highlighted_candidate_index' then return tonumber(obj._c.highlighted_candidate_index)
      elseif k == 'num_candidates' then return tonumber(obj._c.num_candidates)
      elseif k == 'select_keys' then return safestr(obj._c.select_keys) or ''
      elseif k == 'type' then return 'RimeMenu'
      elseif k == 'candidates' then
        local n = tonumber(obj._c.num_candidates) or 0
        local arr = obj._c.candidates
        if arr == nil or n <= 0 then return {} end
        local out = {}
        for i = 0, n - 1 do
          local ok, cand_c = pcall(function() return arr[i] end)
          if not ok or cand_c == nil then break end
          local candidate = RimeCandidate()
          ffi.copy(candidate._c, cand_c, ffi.sizeof("RimeCandidate"))
          out[#out + 1] = candidate
        end
        return out
      end
    end,
    __newindex = function(_, k, v) error("RimeMenu is read-only") end,
  }
  setmetatable(obj, mt)
  return obj
end

function RimeContext()
  local context = ffi.new("RimeContext")
  context.data_size = ffi.sizeof("RimeContext") - ffi.sizeof("int")
  context.commit_text_preview = nil
  context.select_labels = nil
  local c = ffi.gc(context, function(cdata) ensure_api().free_context(cdata) end)
  local obj = { _c = c }
  local mt = {
    __index = function(_, k)
      if k == 'composition' then
        local comp = RimeComposition()
        ffi.copy(comp._c, obj._c.composition, ffi.sizeof("RimeComposition"))
        return comp
      elseif k == 'menu' then
        local menu = RimeMenu()
        ffi.copy(menu._c, obj._c.menu, ffi.sizeof("RimeMenu"))
        return menu
      elseif k == 'commit_text_preview' then
        return safestr(obj._c.commit_text_preview)
      elseif k == 'select_labels' then
        local arr = obj._c.select_labels
        if arr == nil then return nil end
        local out = {}
        local i = 0
        while arr[i] ~= nil do
          out[#out + 1] = ffi.string(arr[i])
          i = i + 1
        end
      elseif k == 'type' then return 'RimeContext'
      end
    end,
    __newindex = function(_, k, v) error("RimeContext is read-only") end,
  }
  setmetatable(obj, mt)
  return obj
end

function RimeConfig()
  local config = ffi.new("RimeConfig")
  config.ptr = nil
  local obj = { _c = config }
  local mt = {
    __index = function(_, k)
      if k == 'get_int' then
        return function(_, key)
          local value = ffi.new("int[1]")
          local res = api.config_get_int(obj._c, tostring(key), value)
          return res ~= 0 and tonumber(value[0]) or nil
        end
      elseif k == 'get_double' then
        return function(_, key)
          local value = ffi.new("double[1]")
          local res = api.config_get_double(obj._c, tostring(key), value)
          return res ~= 0 and tonumber(value[0]) or nil
        end
      elseif k == 'get_bool' then
        return function(_, key)
          local value = ffi.new("int[1]")
          local res = api.config_get_bool(obj._c, tostring(key), value)
          if res == 1 then return value[0] ~= 0 else return nil end
        end
      elseif k == 'get_string' then
        return function(_, key, buffer_size)
          buffer_size = buffer_size or 1024
          local buf = ffi.new("char[?]", buffer_size)
          local res = api.config_get_string(obj._c, tostring(key), buf, tonumber(buffer_size))
          return res ~= 0 and safestr(buf) or nil
        end
      elseif k == 'get_cstring' then
        return function(_, key) return safestr(api.config_get_cstring(obj._c, tostring(key))) end
      elseif k == 'set_int' then
        return function(_, key, value) return api.config_set_int(obj._c, tostring(key), tonumber(value)) ~= 0 end
      elseif k == 'set_double' then
        return function(_, key, value) return api.config_set_double(obj._c, tostring(key), tonumber(value)) ~= 0 end
      elseif k == 'set_bool' then
        return function(_, key, value) return api.config_set_bool(obj._c, tostring(key), value and 1 or 0) ~= 0 end
      elseif k == 'set_string' then
        return function(_, key, value) return api.config_set_string(obj._c, tostring(key), tostring(value)) ~= 0 end
      elseif k == 'open' then
        return function(_, config_id) return api.config_open(tostring(config_id), obj._c) ~= 0 end
      elseif k == 'reload' or k == 'open' then
        return function(_, config_id)
          local was_borrowed = is_config_borrowed(obj)
          if not was_borrowed then api.config_close(obj._c) end
          local ok = api.config_open(tostring(config_id), obj._c) ~= 0
          set_config_borrowed(obj, was_borrowed and (not ok))
          return ok
        end
      elseif k == 'close' then
        return function(_)
          if is_config_borrowed(obj) then return false
          else
            local ret = api.config_close(obj._c) ~= 0
            set_config_borrowed(obj, false)
            return ret
          end
        end
      elseif k == 'type' then return 'RimeConfig'
      else
        error("RimeConfig has no such method: " .. tostring(k))
      end
    end,
    __newindex = function(_, k, v) error("RimeConfig is read-only") end,
  }
  ffi.gc(obj._c, function(cdata)
    if not is_config_borrowed(obj) then ensure_api().config_close(cdata) end
  end)
  setmetatable(obj, mt)
  return obj
end

function RimeConfigIterator()
  local iterator = ffi.new("RimeConfigIterator")
  local obj = { _c = iterator }
  local mt = {
    __index = function(_, k)
      if k == 'path' then return safestr(obj._c.path)
      elseif k == 'key' then return safestr(obj._c.key)
      elseif k == 'index' then return tonumber(obj._c.index)
      elseif k == 'type' then return 'RimeConfigIterator'
      end
    end,
    __newindex = function(_, k, v) error("RimeConfigIterator is read-only") end,
  }
  setmetatable(obj, mt)
  return obj
end

function RimeCustomApi(ptr)
  local custom_api
  if ptr ~= nil and ptr ~= ffi.NULL then
    custom_api = ffi.cast("RimeCustomApi*", ptr)
  else
    custom_api = ffi.new("RimeCustomApi")
  end
  if custom_api ~= nil and custom_api ~= ffi.NULL then
    custom_api.data_size = ffi.sizeof("RimeCustomApi") - ffi.sizeof("int")
  end
  local obj = { _c = custom_api }
  local mt = {
    __index = function(_, k)
      if k == 'type' then return 'RimeCustomApi' end
    end,
    __newindex = function(_, k, v) error("RimeCustomApi is read-only") end,
  }
  setmetatable(obj, mt)
  return obj
end

function RimeModule()
  local module = ffi.new("RimeModule")
  module.data_size = ffi.sizeof("RimeModule") - ffi.sizeof("int")
  module.initialize = nil
  module.finalize = nil
  module.get_api = nil
  local obj = { _c = module }
  local mt = {
    __index = function(_, k)
      if k == 'get_api' then
        return function(_)
          local api_ptr = obj._c.get_api()
          if api_ptr == nil or api_ptr == ffi.NULL then return nil end
          return RimeCustomApi(api_ptr)
        end
      elseif k == 'type' then return 'RimeModule'
      end
    end,
    __newindex = function(_, k, v) error("RimeModule is read-only") end,
  }
  setmetatable(obj, mt)
  return obj
end

local MAX_SAFE_INTEGER = 9007199254740991 -- 2^53 - 1
function RimeSession(session_id, opts)
  local options = opts
  if type(session_id) == 'table' and opts == nil then
    options = session_id
    session_id = nil
  end

  local borrowed = (type(options) == 'table' and options.borrowed) or false

  local session = ffi.new("RimeSession")
  if session_id ~= nil then
    if ffi.istype("RimeSessionId", session_id) then
      session.id = session_id
    elseif type(session_id) == 'number' then
      session.id = ffi.cast("RimeSessionId", session_id)
    else
      error("invalid session_id type")
    end
  else
    session.id = 0
  end

  local obj = { _c = session }
  local mt = {
    __index = function(_, k)
      if k == 'id' then
        return obj._c.id > MAX_SAFE_INTEGER and ffi.cast("RimeSessionId", obj._c.id) or tonumber(obj._c.id)
      elseif k == 'str' then
        local BIT = jit and ((require('ffi').sizeof('void*') == 8) and 16 or 8) or ((string.packsize('T') == 8) and 16 or 8)
        local PFORMAT = "%0" .. BIT .. "X"
        local id = obj._c.id > MAX_SAFE_INTEGER and ffi.cast("RimeSessionId", obj._c.id) or tonumber(obj._c.id)
        return (PFORMAT:format(id))
      elseif k == 'type' then return 'RimeSession'
      elseif k == 'borrowed' then return borrowed
      end
    end,
    __newindex = function(_, k, v) error("RimeSession is read-only") end,
    __eq = function(_, other)
      local current_id = tonumber(obj._c.id)
      if current_id == nil then return false end
      if type(other) == 'number' then
        return current_id == tonumber(other)
      elseif ffi.istype("RimeSessionId", other) then
        return current_id == tonumber(other)
      elseif type(other) == 'table' and other._c and ffi.istype("RimeSession", other._c) then
        return tonumber(obj._c.id) == tonumber(other._c.id)
      end
      return false
    end,
  }
  setmetatable(obj, mt)

  if not borrowed then
    ffi.gc(obj._c, function(cdata) ensure_api().destroy_session(cdata.id) end)
  end

  return obj
end

function RimeStringSlice()
  local slice = ffi.new("RimeStringSlice")
  slice.str = nil
  slice.length = 0
  local obj = { _c = slice }
  local mt = {
    __index = function(_, k)
      if k == 'str' then return safestr(obj._c.str)
      elseif k == 'length' then return tonumber(obj._c.length)
      elseif k == 'type' then return 'RimeStringSlice'
      end
    end,
    __newindex = function(_, k, v) error("RimeStringSlice is read-only") end,
  }
  setmetatable(obj, mt)
  return obj
end

function RimeSchemaInfo(ptr)
  if ptr == nil or ptr == ffi.NULL then return nil end
  local schema_info = ffi.cast("RimeSchemaInfo*", ptr)
  local obj = { _c = schema_info }
  local mt = {
    __index = function(_, k)
      local levers_api = get_levers_api()
      if k == 'schema_id' then return safestr(levers_api.get_schema_id(obj._c))
      elseif k == 'name' then return safestr(levers_api.get_schema_name(obj._c))
      elseif k == 'author' then return safestr(levers_api.get_schema_author(obj._c))
      elseif k == 'description' then return safestr(levers_api.get_schema_description(obj._c))
      elseif k == 'version' then return safestr(levers_api.get_schema_version(obj._c))
      elseif k == 'file_path' then return safestr(levers_api.get_schema_file_path(obj._c))
      elseif k == 'get_schema_id' then return function(_) return safestr(get_levers_api().get_schema_id(obj._c)) end
      elseif k == 'get_schema_name' then return function(_) return safestr(get_levers_api().get_schema_name(obj._c)) end
      elseif k == 'get_schema_author' then return function(_) return safestr(get_levers_api().get_schema_author(obj._c)) end
      elseif k == 'get_schema_description' then return function(_) return safestr(get_levers_api().get_schema_description(obj._c)) end
      elseif k == 'get_schema_version' then return function(_) return safestr(get_levers_api().get_schema_version(obj._c)) end
      elseif k == 'get_schema_file_path' then return function(_) return safestr(get_levers_api().get_schema_file_path(obj._c)) end
      elseif k == 'type' then return 'RimeSchemaInfo'
      end
    end,
    __newindex = function(_, k, v) error("RimeSchemaInfo is read-only") end,
  }
  setmetatable(obj, mt)
  return obj
end

function RimeSchemaListItem(ptr)
  if ptr == nil or ptr == ffi.NULL then return nil end
  local item = ffi.cast("RimeSchemaListItem*", ptr)
  local obj = { _c = item }
  local mt = {
    __index = function(_, k)
      if k == 'schema_id' then return safestr(obj._c.schema_id) or ''
      elseif k == 'name' then return safestr(obj._c.name) or ''
      elseif k == 'schema_info' then
        if obj._c.reserved == ffi.NULL then return nil end
        local schema_info = RimeSchemaInfo(ffi.cast("RimeSchemaInfo*", obj._c.reserved))
        return schema_info
      elseif k == 'type' then return 'RimeSchemaListItem'
      end
    end,
    __newindex = function(_, k, v) error("RimeSchemaListItem is read-only") end,
  }
  setmetatable(obj, mt)
  return obj
end

function RimeSchemaList()
  local schema_list = ffi.new("RimeSchemaList")
  local obj = { _c = schema_list }
  local mt = {
    __index = function(_, k)
      if k == 'size' then return tonumber(obj._c.size)
      elseif k == 'list' then
        local n = tonumber(obj._c.size) or 0
        local arr = obj._c.list
        if arr == nil or n <= 0 then return {} end
        local out = {}
        for i = 0, n - 1 do
          local ok, item_c = pcall(function() return arr[i] end)
          if not ok or item_c == nil then break end
          local item = RimeSchemaListItem(item_c)
          out[#out + 1] = item
        end
        return out
      elseif k == 'type' then return 'RimeSchemaList'
      end
    end,
    __newindex = function(_, k, v) error("RimeSchemaList is read-only") end,
  }
  ffi.gc(obj._c, function(cdata)
    if not is_schemalist_borrowed(obj) then ensure_api().free_schema_list(cdata) end
  end)
  setmetatable(obj, mt)
  return obj
end
-------------------------------------------------------------------------------
--- get rime api end
function RimeApi()
  local tosessionid = function(session_id)
    if type(session_id) == 'number' then
      return ffi.cast("RimeSessionId", session_id)
    elseif ffi.istype("RimeSessionId", session_id) then
      return session_id
    elseif type(session_id) == 'table' and session_id._c ~= nil and ffi.istype("RimeSession", session_id._c) then
      return ffi.cast("RimeSessionId", session_id._c.id)
    else
      error("invalid session_id type")
    end
  end

  local pthread_mutex_defined = false
  local critical_section_defined = false

  local function create_notification_mutex()
    if ffi.os == "Windows" then
      if not critical_section_defined then
        ffi.cdef[[
        typedef struct _RTL_CRITICAL_SECTION {
          void* DebugInfo;
          long LockCount;
          long RecursionCount;
          void* OwningThread;
          void* LockSemaphore;
          uintptr_t SpinCount;
        } CRITICAL_SECTION;

        void InitializeCriticalSection(CRITICAL_SECTION* lpCriticalSection);
        void EnterCriticalSection(CRITICAL_SECTION* lpCriticalSection);
        void LeaveCriticalSection(CRITICAL_SECTION* lpCriticalSection);
        void DeleteCriticalSection(CRITICAL_SECTION* lpCriticalSection);
        ]]
        critical_section_defined = true
      end

      local storage = ffi.new("CRITICAL_SECTION[1]")
      ffi.C.InitializeCriticalSection(storage)

      local mutex = { _storage = storage }
      function mutex.lock()
        ffi.C.EnterCriticalSection(storage)
      end
      function mutex.unlock()
        ffi.C.LeaveCriticalSection(storage)
      end

      ffi.gc(storage, function(sec)
        ffi.C.DeleteCriticalSection(sec)
      end)

      return mutex
    else
      if not pthread_mutex_defined then
        if ffi.os == "OSX" then
          ffi.cdef[[
          typedef struct _opaque_pthread_mutex_t {
            long __sig;
            char __opaque[56];
          } pthread_mutex_t;

          typedef struct _opaque_pthread_mutexattr_t {
            long __sig;
            char __opaque[8];
          } pthread_mutexattr_t;
          ]]
        else
          ffi.cdef[[
          typedef union {
            char __size[40];
            long int __align;
          } pthread_mutex_t;

          typedef union {
            char __size[4];
            long int __align;
          } pthread_mutexattr_t;
          ]]
        end

        ffi.cdef[[
        int pthread_mutex_init(pthread_mutex_t* mutex, const pthread_mutexattr_t* attr);
        int pthread_mutex_lock(pthread_mutex_t* mutex);
        int pthread_mutex_unlock(pthread_mutex_t* mutex);
        int pthread_mutex_destroy(pthread_mutex_t* mutex);
        ]]

        pthread_mutex_defined = true
      end

      local storage = ffi.new("pthread_mutex_t[1]")
      local rc = ffi.C.pthread_mutex_init(storage, nil)
      if rc ~= 0 then
        return nil, rc
      end

      local mutex = { _storage = storage }
      function mutex.lock()
        local err = ffi.C.pthread_mutex_lock(storage)
        if err ~= 0 then
          error("pthread_mutex_lock failed: " .. tostring(err))
        end
      end
      function mutex.unlock()
        local err = ffi.C.pthread_mutex_unlock(storage)
        if err ~= 0 then
          error("pthread_mutex_unlock failed: " .. tostring(err))
        end
      end

      ffi.gc(storage, function(ptr)
        ffi.C.pthread_mutex_destroy(ptr)
      end)

      return mutex
    end
  end

  local notification_mutex
  do
    local ok, res, err = pcall(create_notification_mutex)
    if ok and res ~= nil then
      notification_mutex = res
    else
      local stderr = io.stderr
      if stderr and stderr.write then
        stderr:write("[rimeapi_ffi] warning: notification mutex unavailable: " .. tostring(err or res) .. "\n")
      end
      notification_mutex = nil
    end
  end

  local function notification_lock()
    if notification_mutex and notification_mutex.lock then
      notification_mutex.lock()
    end
  end

  local function notification_unlock()
    if notification_mutex and notification_mutex.unlock then
      notification_mutex.unlock()
    end
  end

  local notification_entries = {}
  local notification_entry_counter = 0

  local MAX_NOTIFICATION_QUEUE = 64
  local MAX_NOTIFICATION_TYPE_LEN = 64
  local MAX_NOTIFICATION_VALUE_LEN = 1024

  local NotificationContextStruct = ffi.typeof(string.format([[struct {
    intptr_t entry_id;
    unsigned int capacity;
    volatile unsigned int head;
    volatile unsigned int tail;
    volatile unsigned int active;
    struct {
      uintptr_t session;
      unsigned int type_len;
      unsigned int value_len;
      char msg_type[%d];
      char msg_value[%d];
    } events[%d];
  }]], MAX_NOTIFICATION_TYPE_LEN, MAX_NOTIFICATION_VALUE_LEN, MAX_NOTIFICATION_QUEUE))

  local NotificationContextPtr = ffi.typeof("$*", NotificationContextStruct)

  local notification_callback_c

  local function copy_cstring(dst, src, max_len)
    if dst == nil or max_len <= 0 then return 0 end
    local dst_ptr = ffi.cast("unsigned char*", dst)
    if src == nil or src == ffi.NULL then
      dst_ptr[0] = 0
      return 0
    end
    local src_ptr = ffi.cast("const unsigned char*", src)
    local i = 0
    local limit = max_len - 1
    while i < limit do
      local byte = src_ptr[i]
      if byte == 0 then break end
      dst_ptr[i] = byte
      i = i + 1
    end
    dst_ptr[i] = 0
    return i
  end

  local function notification_queue_advance(index, capacity)
    index = index + 1
    if index >= capacity then index = 0 end
    return index
  end

  local function cleanup_notification_entry(entry_id)
    if entry_id == nil then return end
    local entry = notification_entries[entry_id]
    if not entry then return end
    local ctx = entry.ctx
    local queue_empty = true
    if ctx ~= nil then
      queue_empty = (ctx.head == ctx.tail)
    end
    if not entry.active and queue_empty then
      if ctx then ctx.active = 0 end
      notification_entries[entry_id] = nil
    end
  end

  local function get_notification_callback()
    if notification_callback_c == nil then
      local function bridge(context_object, session_id, msg_type, msg_value)
        if context_object == nil or context_object == ffi.NULL then return end
        local ctx = ffi.cast(NotificationContextPtr, context_object)
        if ctx == nil then return end

        notification_lock()
        if ctx.active == 0 then
          notification_unlock()
          return
        end

        local capacity = ctx.capacity
        if capacity == 0 then capacity = MAX_NOTIFICATION_QUEUE end
        local head = ctx.head
        local tail = ctx.tail
        local next_tail = notification_queue_advance(tail, capacity)
        if next_tail == head then
          head = notification_queue_advance(head, capacity)
          ctx.head = head
        end

        local event = ctx.events[tail]
        event.session = ffi.cast("uintptr_t", session_id)
        event.type_len = copy_cstring(event.msg_type, msg_type, MAX_NOTIFICATION_TYPE_LEN)
        event.value_len = copy_cstring(event.msg_value, msg_value, MAX_NOTIFICATION_VALUE_LEN)

        ctx.tail = next_tail
        notification_unlock()
      end

      notification_callback_c = ffi.cast("RimeNotificationHandler", bridge)
    end
    return notification_callback_c
  end

  local function drain_notification_entry(entry)
    local ctx = entry.ctx
    if ctx == nil then return end

    if not entry.active then
      notification_lock()
      ctx.head = ctx.tail
      notification_unlock()
      cleanup_notification_entry(entry.id)
      return
    end

    local capacity = ctx.capacity
    if capacity == 0 then capacity = MAX_NOTIFICATION_QUEUE end

    while true do
      notification_lock()
      local head = ctx.head
      local tail = ctx.tail
      if head == tail then
        notification_unlock()
        break
      end
      local event = ctx.events[head]
      ctx.head = notification_queue_advance(head, capacity)
      notification_unlock()

      local session
      if event.session ~= 0 then
        local session_id = ffi.cast("RimeSessionId", event.session)
        local ok, wrapped = pcall(RimeSession, session_id, { borrowed = true })
        session = (ok and wrapped) and wrapped or session_id
      else
        session = 0
      end
      local msg_type_str = event.type_len > 0 and ffi.string(event.msg_type, event.type_len) or nil
      local msg_value_str = event.value_len > 0 and ffi.string(event.msg_value, event.value_len) or nil

      local ok, err = entry.invoker(entry, session, msg_type_str, msg_value_str)
      if not ok then
        local stderr = io.stderr
        if stderr and stderr.write then
          stderr:write("[rimeapi_ffi] notification handler error: " .. tostring(err) .. "\n")
        end
      end
    end

    if not entry.active then
      cleanup_notification_entry(entry.id)
    end
  end

  local function drain_notifications()
    for _, entry in pairs(notification_entries) do
      drain_notification_entry(entry)
    end
  end
  local obj = { _c = ensure_api(), }
  local mt = {
    __index = function(_, k)
      drain_notifications()
      if k == '_notification_entry_id' then
        return rawget(obj, k)
      elseif k == 'setup' then
        return function(_, traits)
          obj._c.setup(traits._c)
          drain_notifications()
          return nil
        end
      elseif k == 'set_notification_handler' then
        return function(_, handler_func, context_object)
          if handler_func ~= nil and type(handler_func) ~= 'function' then
            error("handler_func must be a function or nil")
          end

          notification_lock()
          local previous_id = rawget(obj, '_notification_entry_id')
          if previous_id ~= nil then
            local prev_entry = notification_entries[previous_id]
            if prev_entry then
              prev_entry.active = false
              if prev_entry.ctx then prev_entry.ctx.active = 0 end
              cleanup_notification_entry(previous_id)
            end
            rawset(obj, '_notification_entry_id', nil)
          end
          notification_unlock()

          if handler_func == nil then
            obj._c.set_notification_handler(nil, nil)
            drain_notifications()
            return nil
          end

          local ok, info = pcall(debug.getinfo, handler_func, 'u')
          local expects_context = not (ok and info and info.nparams == 3)

          local ctx = ffi.new(NotificationContextStruct)
          ctx.capacity = MAX_NOTIFICATION_QUEUE
          ctx.head = 0
          ctx.tail = 0
          ctx.active = 1

          local effective_context = context_object
          if effective_context == nil or effective_context == ffi.NULL then
            effective_context = obj
          end

          local entry = {
            handler = handler_func,
            user_context = context_object,
            call_context = effective_context,
            expects_context = expects_context,
            ctx = ctx,
            active = true,
          }

          if expects_context then
            entry.invoker = function(e, session, msg_type, msg_value)
              return pcall(e.handler, e.call_context, session, msg_type, msg_value)
            end
          else
            entry.invoker = function(e, session, msg_type, msg_value)
              return pcall(e.handler, session, msg_type, msg_value)
            end
          end

          notification_lock()
          notification_entry_counter = notification_entry_counter + 1
          local entry_id = notification_entry_counter
          entry.id = entry_id
          ctx.entry_id = entry_id
          notification_entries[entry_id] = entry
          notification_unlock()

          rawset(obj, '_notification_entry_id', entry_id)

          local callback = get_notification_callback()
          obj._c.set_notification_handler(callback, ffi.cast("void*", ctx))
          drain_notifications()
          return nil
        end
      elseif k == 'is_maintenance_mode' then
        return function() return tonumber(obj._c.is_maintenance_mode()) end
      elseif k == 'start_maintenance' then
        return function(_, full_check)
          drain_notifications()
          local res = obj._c.start_maintenance(full_check and 1 or 0)
          drain_notifications()
          return tonumber(res)
        end
      elseif k == 'join_maintenance_thread' then
        return function(_)
          obj._c.join_maintenance_thread()
          drain_notifications()
          return nil
        end
      elseif k == 'initialize' then
        return function(_, traits)
          obj._c.initialize(traits._c)
          drain_notifications()
          return nil
        end
      elseif k == 'finalize' then
        return function(_)
          obj._c.finalize()
          drain_notifications()
          return nil
        end
      elseif k == 'create_session' then
        return function(_)
          local session_id = obj._c.create_session()
          local session = RimeSession()
          session._c.id = session_id
          return session
        end
      elseif k == 'simulate_key_sequence' then
        return function(_, session_id, key_sequence) return (obj._c.simulate_key_sequence(tosessionid(session_id), tostring(key_sequence)) ~= 0) end
      elseif k == 'process_key' then
        return function(_, session_id, keycode, mask) return (obj._c.process_key(tosessionid(session_id), tonumber(keycode), tonumber(mask)) ~= 0) end
      elseif k == 'commit_composition' then
        return function(_, session_id) return (obj._c.commit_composition(tosessionid(session_id)) ~= 0) end
      elseif k == 'clear_composition' then
        return function(_, session_id) obj._c.clear_composition(tosessionid(session_id)) return nil
        end
      elseif k == 'get_commit' then
        return function(_, session_id, commit_obj) return obj._c.get_commit(tosessionid(session_id), commit_obj._c) ~= 0 end
      elseif k == 'get_status' then
        return function(_, session_id, status_obj) return obj._c.get_status(tosessionid(session_id), status_obj._c) ~= 0 end
      elseif k == 'get_schema_list' then
        return function(_, schemas) return obj._c.get_schema_list(schemas._c) ~= 0 end
      elseif k == 'free_schema_list' then
        return function(_, schemas) obj._c.free_schema_list(schemas._c) end
      elseif k == 'get_context' then
        return function(_, session_id, context_obj) return obj._c.get_context(tosessionid(session_id), context_obj._c) ~= 0 end
      elseif k == 'free_commit' then
        return function(_, commit_obj) return obj._c.free_commit(commit_obj._c) ~= 0 end
      elseif k == 'free_status' then
        return function(_, status_obj) return obj._c.free_status(status_obj._c) ~= 0 end
      elseif k == 'free_context' then
        return function(_, context_obj) return obj._c.free_context(context_obj._c) ~= 0 end
      elseif k == 'candidate_list_begin' then
        return function(_, session_id, iterator_obj)
          return obj._c.candidate_list_begin(tosessionid(session_id), iterator_obj._c) ~= 0
        end
      elseif k == 'candidate_list_next' then
        return function(_, iterator_obj)
          return obj._c.candidate_list_next(iterator_obj._c) ~= 0
        end
      elseif k == 'candidate_list_end' then
        return function(_, iterator_obj)
          obj._c.candidate_list_end(iterator_obj._c)
          return nil
        end
      elseif k == 'cleanup_all_sessions' then
        return function(_) obj._c.cleanup_all_sessions() return nil  end
      elseif k == 'cleanup_stale_sessions' then
        return function(_) obj._c.cleanup_stale_sessions() return nil  end
      elseif k == 'destroy_session' then
        return function(_, session_id) return obj._c.destroy_session(tosessionid(session_id)) ~= 0 end
      elseif k == 'find_session' then
        return function(_, session_id) return obj._c.find_session(tosessionid(session_id)) ~= 0 end
      elseif k == 'deployer_initialize' then
        return function(_, traits)
          obj._c.deployer_initialize(traits._c)
          drain_notifications()
          return nil
        end
      elseif k == 'prebuild' then
        return function(_)
          drain_notifications()
          local ok = obj._c.prebuild() ~= 0
          drain_notifications()
          return ok
        end
      elseif k == 'deploy' then
        return function(_)
          drain_notifications()
          local ok = obj._c.deploy() ~= 0
          drain_notifications()
          return ok
        end
      elseif k == 'deploy_schema' then
        return function(_, schema_file)
          drain_notifications()
          local ok = obj._c.deploy_schema(tostring(schema_file)) ~= 0
          drain_notifications()
          return ok
        end
      elseif k == 'deploy_config_file' then
        return function(_, file_name, version_key)
          drain_notifications()
          local ok = obj._c.deploy_config_file(tostring(file_name), tostring(version_key)) ~= 0
          drain_notifications()
          return ok
        end
      elseif k == 'sync_user_data' then
        return function(_)
          drain_notifications()
          local ok = obj._c.sync_user_data() ~= 0
          drain_notifications()
          return ok
        end
      elseif k == 'set_option' then
        return function(_, session_id, option, value)
          obj._c.set_option(tosessionid(session_id), tostring(option), value and 1 or 0)
          return nil
        end
      elseif k == 'get_option' then
        return function(_, session_id, option)
          return obj._c.get_option(tosessionid(session_id), tostring(option)) ~= 0
        end
      elseif k == 'set_property' then
        return function(_, session_id, prop, value)
          obj._c.set_property(tosessionid(session_id), tostring(prop), tostring(value))
          return nil
        end
      elseif k == 'get_property' then
        return function(_, session_id, prop, buffer_size)
          buffer_size = buffer_size or 256
          local buf = ffi.new("char[?]", buffer_size)
          local res = obj._c.get_property(tosessionid(session_id), tostring(prop), buf, tonumber(buffer_size))
          return res ~= 0 and safestr(buf) or nil
        end
      elseif k == 'config_open' then
        return function(_, config_id, config_obj)
          local was_borrowed = is_config_borrowed(config_obj)
          if not was_borrowed then obj._c.config_close(config_obj._c) end
          local ret = obj._c.config_open(tostring(config_id), config_obj._c) ~= 0
          set_config_borrowed(config_obj, was_borrowed and (not ret))
          return ret
        end
      elseif k == 'config_close' then
        return function(_, config_obj)
          local ret = false
          if not is_config_borrowed(config_obj) then
            ret = obj._c.config_close(config_obj._c) ~= 0
            cfg_borrowed_set:erase(config_obj)
          end
          return ret
        end
      elseif k == 'schema_open' then
        return function(_, schema_id, config_obj)
          local was_borrowed = is_config_borrowed(config_obj)
          if not was_borrowed then obj._c.config_close(config_obj._c) end
          local ret = obj._c.schema_open(tostring(schema_id), config_obj._c) ~= 0
          set_config_borrowed(config_obj, was_borrowed and (not ret))
          return ret
        end
      elseif k == 'select_schema' then
        return function(_, session_id, schema_id) return obj._c.select_schema(tosessionid(session_id), tostring(schema_id)) ~= 0 end
      elseif k == 'get_current_schema' then
        return function(_, session_id, len)
          len = tonumber(len) or 256
          local schema_id = ffi.new("char[256]")
          local tmp = obj._c.get_current_schema(tosessionid(session_id), schema_id, len)
          return tmp ~= 0 and safestr(schema_id) or nil
        end
      elseif k == 'config_update_signature' then
        return function(_, config_obj, signer) return obj._c.config_update_signature(config_obj._c, tostring(signer)) ~= 0 end
      elseif k == 'config_begin_map' then
        return function(_, iterator_obj, config_obj, key) return obj._c.config_begin_map(iterator_obj._c, config_obj._c, tostring(key)) ~= 0 end
      elseif k == 'config_next' then
        return function(_, iterator_obj) return obj._c.config_next(iterator_obj._c) ~= 0 end
      elseif k == 'config_end' then
        return function(_, iterator_obj) obj._c.config_end(iterator_obj._c) return nil end
      elseif k == 'config_init' then
        return function(_, config_obj) return obj._c.config_init(config_obj._c) ~= 0 end
      elseif k == 'config_load_string' then
        return function(_, config_obj, yaml) return obj._c.config_load_string(config_obj._c, tostring(yaml)) ~= 0 end
      elseif k == 'config_get_cstring' then
        return function(_, config_obj, key) return safestr(obj._c.config_get_cstring(config_obj._c, tostring(key))) end
      elseif k == 'config_get_string' then
        return function(_, config_obj, key, buffer_size)
          buffer_size = buffer_size or 1024
          local buf = ffi.new("char[?]", buffer_size)
          local res = obj._c.config_get_string(config_obj._c, tostring(key), buf, tonumber(buffer_size))
          return res ~= 0 and safestr(buf) or nil
        end
      elseif k == 'config_set_string' then
        return function(_, config_obj, key, value) return obj._c.config_set_string(config_obj._c, tostring(key), tostring(value)) ~= 0 end
      elseif k == 'config_get_int' then
        return function(_, config_obj, key)
          local value = ffi.new("int[1]")
          local res = obj._c.config_get_int(config_obj._c, tostring(key), value)
          return res ~= 0 and tonumber(value[0]) or nil
        end
      elseif k == 'config_set_int' then
        return function(_, config_obj, key, value) return obj._c.config_set_int(config_obj._c, tostring(key), tonumber(value)) ~= 0 end
      elseif k == 'config_get_double' then
        return function(_, config_obj, key)
          local value = ffi.new("double[1]")
          local res = obj._c.config_get_double(config_obj._c, tostring(key), value)
          return res ~= 0 and tonumber(value[0]) or nil
        end
      elseif k == 'config_set_double' then
        return function(_, config_obj, key, value) return obj._c.config_set_double(config_obj._c, tostring(key), tonumber(value)) ~= 0 end
      elseif k == 'config_get_bool' then
        return function(_, config_obj, key)
          local value = ffi.new("int[1]")
          local res = obj._c.config_get_bool(config_obj._c, tostring(key), value)
          if res == 0 then return nil end
          return value[0] ~= 0
        end
      elseif k == 'config_set_bool' then
        return function(_, config_obj, key, value)
          return obj._c.config_set_bool(config_obj._c, tostring(key), value and 1 or 0) ~= 0
        end
      elseif k == 'config_get_item' then
        return function(_, config_obj, key, value_obj) return obj._c.config_get_item(config_obj._c, tostring(key), value_obj._c) ~= 0 end
      elseif k == 'config_set_item' then
        return function(_, config_obj, key, value_obj) return obj._c.config_set_item(config_obj._c, tostring(key), value_obj._c) ~= 0 end
      elseif k == 'config_clear' then
        return function(_, config_obj, key) return obj._c.config_clear(config_obj._c, tostring(key)) ~= 0 end
      elseif k == 'config_create_list' then
        return function(_, config_obj, key) return obj._c.config_create_list(config_obj._c, tostring(key)) ~= 0 end
      elseif k == 'config_create_map' then
        return function(_, config_obj, key) return obj._c.config_create_map(config_obj._c, tostring(key)) ~= 0 end
      elseif k == 'config_list_size' then
        return function(_, config_obj, key) return tonumber(obj._c.config_list_size(config_obj._c, tostring(key))) end
      elseif k == 'config_begin_list' then
        return function(_, iterator_obj, config_obj, key) return obj._c.config_begin_list(iterator_obj._c, config_obj._c, tostring(key)) ~= 0 end
      elseif k == 'get_input' then
        return function(_, session_id) return safestr(obj._c.get_input(tosessionid(session_id))) end
      elseif k == 'get_caret_pos' then
        return function(_, session_id) return tonumber(obj._c.get_caret_pos(tosessionid(session_id))) end
      elseif k == 'set_input' then
        return function(_, session_id, input) return obj._c.set_input(tosessionid(session_id), tostring(input)) ~= 0 end
      elseif k == 'set_caret_pos' then
        return function(_, session_id, caret_pos) obj._c.set_caret_pos(tosessionid(session_id), tonumber(caret_pos)) return nil end
      elseif k == 'select_candidate' then
        return function(_, session_id, index) return obj._c.select_candidate(tosessionid(session_id), tonumber(index)) ~= 0 end
      elseif k == 'select_candidate_on_current_page' then
        return function(_, session_id, index) return obj._c.select_candidate_on_current_page(tosessionid(session_id), tonumber(index)) ~= 0 end
      elseif k == 'candidate_list_from_index' then
        return function(_, session_id, iterator_obj, index) return obj._c.candidate_list_from_index(tosessionid(session_id), iterator_obj._c, tonumber(index)) ~= 0 end
      elseif k == 'get_state_label' then
        return function(_, session_id, option_name, state) return safestr(obj._c.get_state_label(tosessionid(session_id), tostring(option_name), state and 1 or 0)) end
      elseif k == 'delete_candidate' then
        return function(_, session_id, index) return obj._c.delete_candidate(tosessionid(session_id), tonumber(index)) ~= 0 end
      elseif k == 'delete_candidate_on_current_page' then
        return function(_, session_id, index) return obj._c.delete_candidate_on_current_page(tosessionid(session_id), tonumber(index)) ~= 0 end
      elseif k == 'get_state_label_abbreviated' then
        return function(_, session_id, option_name, state, abbreviated)
          local stringSlice = RimeStringSlice()
          local tmp = obj._c.get_state_label_abbreviated(tosessionid(session_id), tostring(option_name), state and 1 or 0, abbreviated and 1 or 0)
          if tmp ~= 0 then
            ffi.copy(stringSlice._c, tmp, ffi.sizeof("RimeStringSlice"))
            return stringSlice
          else
            return nil
          end
        end
      elseif k == 'highlight_candidate' then
        return function(_, session_id, index) return obj._c.highlight_candidate(tosessionid(session_id), tonumber(index)) ~= 0 end
      elseif k == 'highlight_candidate_on_current_page' then
        return function(_, session_id, index) return obj._c.highlight_candidate_on_current_page(tosessionid(session_id), tonumber(index)) ~= 0 end
      elseif k == 'change_page' then
        return function(_, session_id, backward) return obj._c.change_page(tosessionid(session_id), backward and 1 or 0) ~= 0 end
      elseif k == 'run_task' then
        return function(_, task_name) return tonumber(obj._c.run_task(tostring(task_name))) end
      elseif k == 'find_module' then
        return function(_, module_name)
          local module_c = obj._c.find_module(tostring(module_name))
          if module_c == nil then return nil end
          local module_obj = RimeModule()
          ffi.copy(module_obj._c, module_c, ffi.sizeof("RimeModule"))
          return module_obj
        end
      elseif k == 'register_module' then
        return function(_, module_obj) return (obj._c.register_module(module_obj._c) ~= 0) end
      elseif k == 'get_shared_data_dir' then
        return function(_) return safestr(obj._c.get_shared_data_dir()) end
      elseif k == 'get_user_data_dir' then
        return function(_) return safestr(obj._c.get_user_data_dir()) end
      elseif k == 'get_prebuilt_data_dir' then
        return function(_) return safestr(obj._c.get_prebuilt_data_dir()) end
      elseif k == 'get_sync_dir' then
        return function(_) return safestr(obj._c.get_sync_dir()) end
      elseif k == 'get_user_id' then
        return function(_) return safestr(obj._c.get_user_id()) end
      elseif k == 'get_staging_dir' then
        return function(_) return safestr(obj._c.get_staging_dir()) end
      elseif k == 'get_user_data_sync_dir' then
        return function(_, buffer_size) 
          buffer_size = buffer_size or 1024
          local buf = ffi.new("char[?]", buffer_size)
          obj._c.get_user_data_sync_dir(buf, tonumber(buffer_size))
          return safestr(buf)
        end
      elseif k == 'get_user_data_dir_s' then
        return function(_, buffer_size)
          buffer_size = buffer_size or 1024
          local buf = ffi.new("char[?]", buffer_size)
          obj._c.get_user_data_dir_s(buf, tonumber(buffer_size))
          return safestr(buf)
        end
      elseif k == 'get_shared_data_dir_s' then
        return function(_, buffer_size)
          buffer_size = buffer_size or 1024
          local buf = ffi.new("char[?]", buffer_size)
          obj._c.get_shared_data_dir_s(buf, tonumber(buffer_size))
          return safestr(buf)
        end
      elseif k == 'get_prebuilt_data_dir_s' then
        return function(_, buffer_size)
          buffer_size = buffer_size or 1024
          local buf = ffi.new("char[?]", buffer_size)
          obj._c.get_prebuilt_data_dir_s(buf, tonumber(buffer_size))
          return safestr(buf)
        end
      elseif k == 'get_sync_dir_s' then
        return function(_, buffer_size)
          buffer_size = buffer_size or 1024
          local buf = ffi.new("char[?]", buffer_size)
          obj._c.get_sync_dir_s(buf, tonumber(buffer_size))
          return safestr(buf)
        end
      elseif k == 'get_staging_dir_s' then
        return function(_, buffer_size)
          buffer_size = buffer_size or 1024
          local buf = ffi.new("char[?]", buffer_size)
          obj._c.get_staging_dir_s(buf, tonumber(buffer_size))
          return safestr(buf)
        end
      elseif k == 'get_version' then
        return function(_) return safestr(obj._c.get_version()) end
      elseif k == 'user_config_open' then
        return function(_, config_id, config_obj)
          local was_borrowed = is_config_borrowed(config_obj)
          if not was_borrowed then obj._c.config_close(config_obj._c) end
          local ret = obj._c.user_config_open(tostring(config_id), config_obj._c) ~= 0
          set_config_borrowed(config_obj, was_borrowed and (not ret))
          return ret
        end
      elseif k == 'type' then return 'RimeApi'
      else
        error("RimeApi has no such method: " .. tostring(k))
      end
    end,
    __newindex = function(_, k, v) error("RimeApi is read-only") end,
  }
  setmetatable(obj, mt)
  return obj
end

function RimeCustomSettings(ptr)
  return { _c = ffi.cast("RimeCustomSettings*", ptr), type = 'RimeCustomSettings' }
end

function RimeSwitcherSettings(ptr)
  return {_c = ffi.cast("RimeSwitcherSettings*", ptr), type = 'RimeSwitcherSettings' }
end

function RimeUserDictIterator()
  return {_c = ffi.new("RimeUserDictIterator"), type = 'RimeUserDictIterator' }
end

local function wrap_levers_api(get_pointer)
  local function ensure_levers()
    local ptr = get_pointer()
    if ptr == nil or ptr == ffi.NULL then
      error("levers api not available")
    end
    if ptr.data_size ~= levers_data_size then
      ptr.data_size = levers_data_size
    end
    return ptr
  end

  local obj = {}
  local mt = {
    __index = function(_, k)
      if k == '_c' then return ensure_levers() end
      if k == 'type' then return 'RimeLeversApi' end
      if k == 'custom_settings_init' then
        return function(_, config_id, generator_id)
          local cfg = config_id ~= nil and tostring(config_id) or nil
          local generator = generator_id ~= nil and tostring(generator_id) or nil
          local settings_ptr = ensure_levers().custom_settings_init(cfg, generator)
          if settings_ptr == nil or settings_ptr == ffi.NULL then return nil end
          return RimeCustomSettings(settings_ptr)
        end
      elseif k == 'is_first_run' then
        return function(_, settings)
          return ensure_levers().is_first_run(settings._c) ~= 0
        end
      elseif k == 'load_settings' then
        return function(_, settings)
          local settings_ptr = settings._c
          if not ffi.istype('RimeCustomSettings*', settings_ptr) then
            settings_ptr = ffi.cast("RimeCustomSettings*", settings_ptr)
          end
          return ensure_levers().load_settings(settings_ptr) ~= 0
        end
      elseif k == 'customize_int' then
        return function(_, settings, key, value)
          return ensure_levers().customize_int(settings._c, tostring(key), tonumber(value)) ~= 0
        end
      elseif k == 'customize_string' then
        return function(_, settings, key, value)
          return ensure_levers().customize_string(settings._c, tostring(key), tostring(value)) ~= 0
        end
      elseif k == 'customize_bool' then
        return function(_, settings, key, value)
          return ensure_levers().customize_bool(settings._c, tostring(key), value == true and 1 or 0) ~= 0
        end
      elseif k == 'customize_double' then
        return function(_, settings, key, value)
          return ensure_levers().customize_double(settings._c, tostring(key), tonumber(value)) ~= 0
        end
      elseif k == 'customize_item' then
        return function(_, settings, key, value_obj)
          return ensure_levers().customize_item(settings._c, tostring(key), value_obj._c) ~= 0
        end
      elseif k == 'save_settings' then
        return function(_, settings)
          return ensure_levers().save_settings(settings._c) ~= 0
        end
      elseif k == 'custom_settings_destroy' then
        return function(_, settings)
          ensure_levers().custom_settings_destroy(settings._c)
          return nil
        end
      elseif k == 'switcher_settings_init' then
        return function(_)
          local settings_ptr = ensure_levers().switcher_settings_init()
          if settings_ptr == nil or settings_ptr == ffi.NULL then return nil end
          return RimeSwitcherSettings(settings_ptr)
        end
      elseif k == 'get_available_schema_list' then
        return function(_, switcher_settings, schema_list)
          local ret = ensure_levers().get_available_schema_list(switcher_settings._c, schema_list._c) ~= 0
          if ret then schemalist_borrowed_set:insert(schema_list) end
          return ret
        end
      elseif k == 'settings_is_modified' then
        return function(_, switcher_settings)
          return ensure_levers().settings_is_modified(switcher_settings._c) ~= 0
        end
      elseif k == 'settings_get_config' then
        return function(_, switcher_settings, config_obj)
          local ret = ensure_levers().settings_get_config(switcher_settings._c, config_obj._c) ~= 0
          if ret then set_config_borrowed(config_obj, true) end
          return ret
        end
      elseif k == 'user_dict_iterator_init' then
        return function(_, iter)
          return ensure_levers().user_dict_iterator_init(iter._c) ~= 0
        end
      elseif k == 'next_user_dict' then
        return function(_, iter)
          return safestr(ensure_levers().next_user_dict(iter._c))
        end
      elseif k == 'user_dict_iterator_destroy' then
        return function(_, iter)
          ensure_levers().user_dict_iterator_destroy(iter._c)
          return nil
        end
      elseif k == 'export_user_dict' then
        return function(_, dict_name, text_file)
          return ensure_levers().export_user_dict(tostring(dict_name), tostring(text_file))
        end
      elseif k == 'import_user_dict' then
        return function(_, dict_name, text_file)
          return ensure_levers().import_user_dict(tostring(dict_name), tostring(text_file))
        end
      elseif k == 'backup_user_dict' then
        return function(_, dict_name)
          return ensure_levers().backup_user_dict(tostring(dict_name)) ~= 0
        end
      elseif k == 'restore_user_dict' then
        return function(_, snapshot)
          return ensure_levers().restore_user_dict(tostring(snapshot)) ~= 0
        end
      elseif k == 'get_schema_name' then
        return function(_, schema_info)
          return safestr(ensure_levers().get_schema_name(schema_info._c))
        end
      elseif k == 'get_schema_id' then
        return function(_, schema_info)
          return safestr(ensure_levers().get_schema_id(schema_info._c))
        end
      elseif k == 'get_schema_author' then
        return function(_, schema_info)
          return safestr(ensure_levers().get_schema_author(schema_info._c))
        end
      elseif k == 'get_schema_description' then
        return function(_, schema_info)
          return safestr(ensure_levers().get_schema_description(schema_info._c))
        end
      elseif k == 'get_schema_version' then
        return function(_, schema_info)
          return safestr(ensure_levers().get_schema_version(schema_info._c))
        end
      elseif k == 'get_schema_file_path' then
        return function(_, schema_info)
          return safestr(ensure_levers().get_schema_file_path(schema_info._c))
        end
      elseif k == 'get_selected_schema_list' then
        return function(_, switcher_settings, schema_list)
          local ret = ensure_levers().get_selected_schema_list(switcher_settings._c, schema_list._c) ~= 0
          if ret then schemalist_borrowed_set:insert(schema_list) end
          return ret
        end
      elseif k == 'select_schemas' then
        return function(_, switcher_settings, schema_id_array, array_size)
          local count = tonumber(array_size)
          local schema_id_array_c = ffi.new("const char*[?]", count)
          for i = 0, count - 1 do schema_id_array_c[i] = tostring(schema_id_array[i + 1]) end
          return ensure_levers().select_schemas(switcher_settings._c, schema_id_array_c, count) ~= 0
        end
      elseif k == 'get_hotkeys' then
        return function(_, switcher_settings)
          return safestr(ensure_levers().get_hotkeys(switcher_settings._c))
        end
      elseif k == 'set_hotkeys' then
        return function(_, switcher_settings, hotkeys)
          return ensure_levers().set_hotkeys(switcher_settings._c, tostring(hotkeys)) ~= 0
        end
      elseif k == 'schema_list_destroy' then
        return function(_, schema_list)
          ensure_levers().schema_list_destroy(schema_list._c)
          return nil
        end
      else
        error("RimeLeversApi has no such method: " .. tostring(k))
      end
    end,
    __newindex = function(_, k, v) error("RimeLeversApi is read-only") end,
  }
  return setmetatable(obj, mt)
end

function RimeLeversApi(custom_api)
  if custom_api ~= nil then
    return wrap_levers_api(function() return ffi.cast("RimeLeversApi*", custom_api._c) end)
  end
  return wrap_levers_api(function() return get_levers_api() end)
end

function ToRimeLeversApi(custom_api)
  if custom_api == nil or custom_api._c == nil then return nil end
  local ptr = ffi.cast("RimeLeversApi*", custom_api._c)
  return wrap_levers_api(function() return ptr end)
end

if os.isdir == nil or type(os.isdir) ~= 'function' then
  os.isdir = function(path, cp)
    local bit = require("bit")
    if ffi.os == 'Windows' then
      ffi.cdef[[
      typedef unsigned long DWORD;
      DWORD GetFileAttributesA(const char *lpFileName);
      ]]
      local INVALID_FILE_ATTRIBUTES = 0xFFFFFFFF
      local FILE_ATTRIBUTE_DIRECTORY = 0x10
      local real_path = to_acp_path(path, cp)
      local attr = ffi.C.GetFileAttributesA(real_path)
      return attr ~= INVALID_FILE_ATTRIBUTES and bit.band(attr, FILE_ATTRIBUTE_DIRECTORY) ~= 0
    else
      ffi.cdef[[
      typedef struct __dirstream DIR;
      DIR *opendir(const char *name);
      int closedir(DIR *dirp);
      ]]
      local dirp = ffi.C.opendir(path)
      if dirp ~= nil then
        ffi.C.closedir(dirp)
        return true
      end
      return false
    end
  end
end
