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
  { 'Shift' }, { 'Control' }, { 'Alt' }, { 'Super' },
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
}

local console = {}
for _, item in ipairs(console_commands) do
  console[#console + 1] = item
end
for _, item in ipairs(rime_keys) do
  console[#console + 1] = item
end

M.rime_keys = rime_keys
M.keys = rime_keys
M.console_commands = console_commands
M.console = console

return M
