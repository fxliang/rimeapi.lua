-- Completion catalogs for the interactive readline frontends.
local M = {}

-- Named keys accepted by librime's key_sequence parser. Named keys must be
-- wrapped in braces when mixed with printable text.
local rime_keys = {
  '{Escape}', '{Return}', '{space}', '{Tab}', '{BackSpace}',
  '{Left}', '{Right}', '{Up}', '{Down}', '{Home}', '{End}',
  '{Page_Up}', '{Page_Down}', '{Prior}', '{Next}', '{Begin}',
  '{Delete}', '{Insert}', '{Clear}', '{Linefeed}', '{Pause}',
  '{Scroll_Lock}', '{Sys_Req}', '{Print}', '{Execute}', '{Select}',
  '{Undo}', '{Redo}', '{Menu}', '{Find}', '{Cancel}', '{Help}',
  '{Break}', '{Num_Lock}', '{Caps_Lock}', '{KP_Equal}',
  '{Shift_L}', '{Shift_R}', '{Control_L}', '{Control_R}',
  '{Alt_L}', '{Alt_R}', '{Super_L}', '{Super_R}',
  '{Meta_L}', '{Meta_R}', '{Hyper_L}', '{Hyper_R}',
  '{Multi_key}', '{Mode_switch}', '{ISO_Level3_Shift}',
  '{ISO_Level3_Latch}', '{ISO_Level3_Lock}',
  '{grave}', '{minus}', '{equal}', '{plus}', '{underscore}',
  '{parenleft}', '{parenright}', '{bracketleft}', '{bracketright}',
  '{braceleft}', '{braceright}', '{less}', '{greater}',
  '{colon}', '{semicolon}', '{comma}', '{period}', '{slash}',
  '{backslash}', '{bar}', '{question}', '{exclam}', '{quotedbl}',
  '{apostrophe}', '{quoteleft}', '{quoteright}', '{numbersign}',
  '{dollar}', '{percent}', '{ampersand}', '{asterisk}', '{at}',
  '{asciitilde}', '{asciicircum}',

  -- Frequently used combinations.
  '{Shift+Tab}', '{Shift+Escape}', '{Shift+Return}', '{Shift+space}',
  '{Shift+Left}', '{Shift+Right}', '{Shift+Up}', '{Shift+Down}',
  '{Shift+Home}', '{Shift+End}', '{Shift+Delete}', '{Shift+Insert}',
  '{Control+Tab}', '{Control+Escape}', '{Control+Return}', '{Control+space}',
  '{Control+Left}', '{Control+Right}', '{Control+Up}', '{Control+Down}',
  '{Control+Home}', '{Control+End}', '{Control+Delete}', '{Control+Insert}',
  '{Control+a}', '{Control+c}', '{Control+v}', '{Control+x}', '{Control+z}',
  '{Alt+Tab}', '{Alt+Escape}', '{Alt+Return}', '{Alt+space}',
  '{Alt+Left}', '{Alt+Right}', '{Alt+Up}', '{Alt+Down}', '{Alt+a}',

  -- Modifier prefixes for building combined keys.
  '{Shift+}', '{Control+}', '{Alt+}', '{Super+}', '{Lock+}', '{Release+}',
}

for i = 1, 12 do
  rime_keys[#rime_keys + 1] = '{F' .. i .. '}'
end

for c = string.byte('a'), string.byte('z') do
  rime_keys[#rime_keys + 1] = '{' .. string.char(c) .. '}'
end
for d = 0, 9 do
  rime_keys[#rime_keys + 1] = '{' .. tostring(d) .. '}'
end

for _, name in ipairs({
  'KP_0', 'KP_1', 'KP_2', 'KP_3', 'KP_4', 'KP_5', 'KP_6', 'KP_7',
  'KP_8', 'KP_9', 'KP_Add', 'KP_Subtract', 'KP_Multiply', 'KP_Divide',
  'KP_Decimal', 'KP_Separator', 'KP_Enter', 'KP_Space', 'KP_Tab',
  'KP_Home', 'KP_Left', 'KP_Up', 'KP_Right', 'KP_Down', 'KP_Page_Up',
  'KP_Page_Down', 'KP_End', 'KP_Begin', 'KP_Insert', 'KP_Delete',
}) do
  rime_keys[#rime_keys + 1] = '{' .. name .. '}'
end

-- Generate modifier combinations as well, so typing "{Control+Shi" can
-- suggest something like "{Control+Shift+grave}".
local seen = {}
for _, key in ipairs(rime_keys) do
  seen[key] = true
end

local function add(key)
  if not seen[key] then
    seen[key] = true
    rime_keys[#rime_keys + 1] = key
  end
end

local combo_keys = {
  'Shift_L', 'Shift_R', 'Control_L', 'Control_R',
  'Alt_L', 'Alt_R', 'Super_L', 'Super_R',
  'Meta_L', 'Meta_R', 'Hyper_L', 'Hyper_R',
  'grave', 'space', 'Tab', 'Return', 'BackSpace', 'Escape',
  'Left', 'Right', 'Up', 'Down', 'Home', 'End',
  'Page_Up', 'Page_Down', 'Delete', 'Insert',
  'minus', 'equal', 'plus', 'underscore',
  'parenleft', 'parenright', 'bracketleft', 'bracketright',
  'braceleft', 'braceright', 'less', 'greater',
  'colon', 'semicolon', 'comma', 'period', 'slash', 'backslash',
  'bar', 'question', 'exclam', 'quotedbl', 'apostrophe',
  'quoteleft', 'quoteright', 'numbersign', 'dollar', 'percent',
  'ampersand', 'asterisk', 'at', 'asciitilde', 'asciicircum',
}

for c = string.byte('a'), string.byte('z') do
  combo_keys[#combo_keys + 1] = string.char(c)
end
for d = 0, 9 do
  combo_keys[#combo_keys + 1] = tostring(d)
end
for i = 1, 12 do
  combo_keys[#combo_keys + 1] = 'F' .. i
end

local modifier_orders = {
  { 'Shift' }, { 'Control' }, { 'Alt' }, { 'Super' }, { 'Release' },
  { 'Shift', 'Control' }, { 'Control', 'Shift' },
  { 'Shift', 'Alt' }, { 'Alt', 'Shift' },
  { 'Control', 'Alt' }, { 'Alt', 'Control' },
  { 'Shift', 'Super' }, { 'Super', 'Shift' },
  { 'Control', 'Super' }, { 'Super', 'Control' },
  { 'Alt', 'Super' }, { 'Super', 'Alt' },
  { 'Control', 'Shift', 'Alt' }, { 'Control', 'Alt', 'Shift' },
  { 'Shift', 'Control', 'Alt' }, { 'Shift', 'Alt', 'Control' },
  { 'Alt', 'Control', 'Shift' }, { 'Alt', 'Shift', 'Control' },
  { 'Control', 'Shift', 'Super' }, { 'Control', 'Super', 'Shift' },
  { 'Shift', 'Control', 'Super' }, { 'Shift', 'Super', 'Control' },
  { 'Super', 'Control', 'Shift' }, { 'Super', 'Shift', 'Control' },
  { 'Control', 'Shift', 'Alt', 'Super' },
}

for _, modifiers in ipairs(modifier_orders) do
  local prefix = '{' .. table.concat(modifiers, '+') .. '+'
  for _, key in ipairs(combo_keys) do
    add(prefix .. key .. '}')
  end
end

local console_commands = {
  'reload',
  'exit',
  'print candidate list',
  'print schema list',
  'select candidate ',
  'select schema ',
  'set option ',
  'delete ',
  'delete on current page ',
  'synchronize',
}

local console = {}
for _, item in ipairs(console_commands) do
  console[#console + 1] = {
    text = item,
    display = item,
    detail = 'console command',
    kind = 'command',
  }
end
for _, item in ipairs(rime_keys) do
  console[#console + 1] = {
    text = item,
    display = item,
    kind = 'key',
  }
end

local function append_schema_completions(api, out)
  local schemas = RimeSchemaList()
  if not api:get_schema_list(schemas) then
    return
  end
  for _, schema in ipairs(schemas.list) do
    local schema_id = schema.schema_id
    if schema_id and schema_id ~= '' then
      out[#out + 1] = {
        text = 'select schema ' .. schema_id,
        display = schema_id,
        detail = schema.name or '',
        kind = 'schema',
      }
    end
  end
end

local function append_option(out, option)
  out[#out + 1] = {
    text = 'set option ' .. option,
    display = option,
    detail = 'schema option',
    kind = 'option',
  }
end

local function append_option_completions(api, schema_id, out)
  if not schema_id or schema_id == '' then
    return
  end
  local config = RimeConfig()
  if not api:schema_open(schema_id, config) then
    return
  end
  local iterator = RimeConfigIterator()
  if api:config_begin_list(iterator, config, 'switches') then
    while api:config_next(iterator) do
      local item_path = iterator.path or ''
      local name = api:config_get_cstring(config, item_path .. '/name')
      if name and name ~= '' then
        append_option(out, name)
      else
        local option_iterator = RimeConfigIterator()
        if api:config_begin_list(option_iterator, config, item_path .. '/options') then
          while api:config_next(option_iterator) do
            local option = api:config_get_cstring(config, option_iterator.path)
            if option and option ~= '' then
              append_option(out, option)
            end
          end
          api:config_end(option_iterator)
        end
      end
    end
    api:config_end(iterator)
  end
  api:config_close(config)
end

function M.build(api, schema_id)
  local out = {}
  for i = 1, #console do
    out[i] = console[i]
  end
  if api then
    append_schema_completions(api, out)
    append_option_completions(api, schema_id, out)
  end
  return out
end

local lua_keywords = {}
for word in ('and break do else elseif end false for function goto if in local nil not or repeat return then true until while'):gmatch('%S+') do
  lua_keywords[word] = true
end

local lua_classes

function M.build_lua(environment)
  environment = environment or _G
  if not lua_classes then
    lua_classes = {}
    local source = debug.getinfo(1, 'S').source:sub(2)
    local base = source:match('^(.*[/\\])') or ''
    local file = io.open(base .. 'rimeapi.annotation.lua', 'r')
    if file then
      -- Read declarations as data; executing this file would replace constructors.
      local fields
      for line in file:lines() do
        local class = line:match('^%-%-%-@class%s+(%w+)')
        if class then
          fields = {}
          lua_classes[class] = fields
        elseif fields then
          local name, detail = line:match('^%-%-%-@field%s+([%w_]+)%s+(.+)')
          if name then fields[name] = detail end
        end
      end
      file:close()
    end
  end

  local out, seen, ancestors = {}, {}, {}
  local function append(text, detail)
    if seen[text] or #out >= 4096 then return end
    seen[text] = true
    out[#out + 1] = { text = text, display = text, detail = detail, kind = 'lua' }
  end
  for word in next, lua_keywords do append(word, 'Lua keyword') end

  local function visit(value, prefix, depth, limit)
    if ancestors[value] or #out >= limit then return end
    ancestors[value] = true
    local members, inherited = {}, {}
    local function member(name, item, detail, method)
      if type(name) ~= 'string' or not name:match('^[%a_][%w_]*$') or lua_keywords[name] then return end
      if prefix ~= '' and name:sub(1, 1) == '_' then return end
      if not members[name] then
        members[name] = { value = item, detail = detail, method = method }
      end
    end
    local function collect(object)
      if inherited[object] then return end
      inherited[object] = true
      if type(object) == 'table' then
        for name, item in next, object do member(name, item, type(item), type(item) == 'function') end
      end
      local mt = debug.getmetatable(object)
      if type(mt) ~= 'table' then return end
      local index = rawget(mt, '__index')
      if type(index) == 'table' then collect(index) end
      local methods, getters = rawget(mt, 'methods'), rawget(mt, 'vars_get')
      if type(methods) == 'table' then
        for name, item in next, methods do member(name, item, 'method', true) end
      end
      if type(getters) == 'table' then
        for name in next, getters do member(name, nil, 'field', false) end
      end
      local class = rawget(mt, '__name')
      for name, detail in next, lua_classes[class] or {} do
        member(name, nil, detail, detail:match('^fun%s*%(') ~= nil)
      end
    end
    collect(value)
    local names = {}
    for name in next, members do names[#names + 1] = name end
    table.sort(names)
    local children = {}
    for _, name in ipairs(names) do
      if #out >= limit then break end
      local item = members[name]
      local text = prefix .. name
      append(text, item.detail)
      if prefix ~= '' and item.method and #out < limit then
        append(prefix:sub(1, -2) .. ':' .. name, item.detail)
      end
      -- Bound traversal and inspect raw members only, without invoking getters.
      local kind = type(item.value)
      if depth < 2 and (kind == 'table' or kind == 'userdata') then
        children[#children + 1] = { value = item.value, prefix = text .. '.' }
      end
    end
    -- Reserve names before expanding children, sharing the remaining budget.
    for i, child in ipairs(children) do
      local budget = math.floor((limit - #out) / (#children - i + 1))
      if budget > 0 then
        visit(child.value, child.prefix, depth + 1, #out + budget)
      end
    end
    ancestors[value] = nil
  end
  visit(environment, '', 0, 4096)
  table.sort(out, function(a, b) return a.text < b.text end)
  return out
end

M.rime_keys = rime_keys
M.keys = rime_keys
M.console_commands = console_commands
M.console = console

return M
