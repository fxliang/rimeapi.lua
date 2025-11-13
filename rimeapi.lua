require(type(jit) == 'table' and 'rimeapi_ffi' or 'rimeapi_lua')

local has_linenoise, linenoise = pcall(require, 'linenoise')
if not has_linenoise then linenoise = nil end
local function shell_ok(cmd)
  local r1, r2, r3 = os.execute(cmd)
  if r1 == true then return true end
  if r1 == nil then return false end
  if r1 == false then return false end
  if type(r1) == 'number' then return r1 == 0 end
  if r2 == 'exit' then return r3 == 0 end
  return false
end

local function has_visible_chars(str) return type(str) == 'string' and str:match('%S') ~= nil end

local function beep()
  io.write('\7')
  io.flush()
end

local function create_posix_line_reader()
  if package.config:sub(1,1) == '\\' then return nil end
  local function is_tty() return shell_ok('test -t 0 >/dev/null 2>&1') end
  local function capture_stty_state()
    local pipe = io.popen('stty -g', 'r')
    if not pipe then return nil end
    local state = pipe:read('*l')
    pipe:close()
    return state
  end
  local function restore_stty(state)
    if state and state ~= '' then shell_ok('stty ' .. state) end
  end
  local function set_raw_mode() return shell_ok('stty -icanon -echo min 1 time 0') end
  return function(prompt, history, opts)
    if not is_tty() then
      io.write(prompt)
      io.flush()
      return io.read('*l')
    end

    local stty_state = capture_stty_state()
    if not stty_state or stty_state == '' then
      io.write(prompt)
      io.flush()
      return io.read('*l')
    end

    if not set_raw_mode() then
      restore_stty(stty_state)
      io.write(prompt)
      io.flush()
      return io.read('*l')
    end

    local function reader_loop()
      io.write(prompt)
      io.flush()
      history = history or {}
      local buffer = {}
      local cursor = 0
      local saved_draft = ''
      local saved_draft_valid = false
      local history_index = #history + 1

      local continuation_prompt = (opts and opts.continuation_prompt) or string.rep(' ', #prompt)
      local last_cursor_row = 1
      local function buffer_length() return #buffer end
      local function current_text() return table.concat(buffer) end
      local function set_buffer(text)
        buffer = {}
        for i = 1, #text do buffer[i] = text:sub(i, i) end
        cursor = #buffer
      end

      local function split_lines(text)
        local lines = {}
        local start_idx = 1
        local len = #text
        if len == 0 then return { '' } end
        while true do
          local nl = text:find('\n', start_idx, true)
          if not nl then
            lines[#lines + 1] = text:sub(start_idx)
            break
          end
          lines[#lines + 1] = text:sub(start_idx, nl - 1)
          start_idx = nl + 1
          if start_idx > len then
            lines[#lines + 1] = ''
            break
          end
        end
        return lines
      end

      local function build_display_lines(text)
        local segments = split_lines(text)
        if #segments == 0 then segments = { '' } end
        local lines = {}
        for i, segment in ipairs(segments) do
          if i == 1 then lines[i] = prompt .. segment
          else lines[i] = continuation_prompt .. segment end
        end
        return lines
      end

      local function build_cursor_lines()
        if cursor == 0 then return { prompt } end
        local prefix = table.concat(buffer, '', 1, cursor)
        return build_display_lines(prefix)
      end

      local function refresh_line()
        local display_lines = build_display_lines(current_text())
        if #display_lines == 0 then display_lines = { prompt } end
        local cursor_lines = build_cursor_lines()
        local target_row = #cursor_lines
        local target_col = #cursor_lines[target_row]

        if last_cursor_row > 1 then io.write(string.format('\27[%dF', last_cursor_row - 1)) end
        io.write('\r\27[J')

        for i, line in ipairs(display_lines) do
          if i > 1 then io.write('\r\n') end
          io.write(line)
          io.write('\27[K')
        end

        local total_lines = #display_lines
        if total_lines < 1 then total_lines = 1 end
        last_cursor_row = target_row

        local lines_up = total_lines - target_row
        if lines_up > 0 then io.write(string.format('\27[%dF', lines_up)) end
        io.write('\r')
        if target_col > 0 then io.write(string.format('\27[%dC', target_col)) end
        io.flush()
      end

      local function history_size() return #history end

      local function at_bottom() return history_index == history_size() + 1 end

      local function break_history_navigation() if not at_bottom() then history_index = history_size() + 1 end end

      local function ensure_saved_draft()
        if saved_draft_valid then return end
        saved_draft = current_text()
        saved_draft_valid = true
      end

      local function pull_history(index)
        set_buffer(history[index] or '')
        refresh_line()
      end

      while true do
        local ch = io.stdin:read(1)
        if not ch then return nil, 'eof' end
        local byte = ch:byte()

        if byte == 13 or byte == 10 then
          if cursor < buffer_length() then
            cursor = buffer_length()
            refresh_line()
          else refresh_line() end
          io.write('\n')
          io.flush()
          return current_text()
        elseif byte == 4 then -- Ctrl-D
          if buffer_length() == 0 then
            io.write('\n')
            io.flush()
            return nil, 'eof'
          end
        elseif byte == 3 then -- Ctrl-C
          io.write('\n')
          io.flush()
          return nil, 'interrupt'
        elseif byte == 127 or byte == 8 then -- Backspace/Delete
          if cursor > 0 then
            table.remove(buffer, cursor)
            cursor = cursor - 1
            break_history_navigation()
            saved_draft_valid = false
            refresh_line()
          else beep()
          end
        elseif byte == 27 then -- Escape sequences
          local function read_escape()
            local prefix = io.stdin:read(1)
            if not prefix then return nil end
            if prefix ~= '[' and prefix ~= 'O' then return { prefix = prefix } end
            local params = {}
            while true do
              local next_ch = io.stdin:read(1)
              if not next_ch then return nil end
              if next_ch:match('[0-9;]') then params[#params + 1] = next_ch
              else return { prefix = prefix, params = table.concat(params), final = next_ch }
              end
            end
          end

          local seq = read_escape()
          if not seq then return nil, 'eof' end

          local final = seq.final or ''
          if seq.prefix == '[' or seq.prefix == 'O' then
            if final == 'A' then -- Up arrow
              if history_size() == 0 then beep()
              else
                if at_bottom() then ensure_saved_draft() end
                if history_index > 1 then history_index = history_index - 1
                else history_index = 1 end
                pull_history(history_index)
              end
            elseif final == 'B' then -- Down arrow
              if history_size() == 0 or at_bottom() then beep()
              else
                history_index = history_index + 1
                if at_bottom() then
                  set_buffer(saved_draft_valid and saved_draft or '')
                  saved_draft_valid = false
                  refresh_line()
                else pull_history(history_index) end
              end
            elseif final == 'C' then -- Right arrow
              if cursor < buffer_length() then
                cursor = cursor + 1
                break_history_navigation()
                refresh_line()
              else beep()
              end
            elseif final == 'D' then -- Left arrow
              if cursor > 0 then
                cursor = cursor - 1
                break_history_navigation()
                refresh_line()
              else beep()
              end
            elseif final == 'H' then -- Home
              if cursor > 0 then
                cursor = 0
                break_history_navigation()
                refresh_line()
              else beep()
              end
            elseif final == 'F' then -- End
              if cursor < buffer_length() then
                cursor = buffer_length()
                break_history_navigation()
                refresh_line()
              else beep()
              end
            else
              local params = seq.params or ''
              if final == '~' and params == '3' then -- Delete key
                if cursor < buffer_length() then
                  table.remove(buffer, cursor + 1)
                  break_history_navigation()
                  saved_draft_valid = false
                  refresh_line()
                else beep()
                end
              else beep()
              end
            end
          else beep()
          end
        elseif byte >= 32 and byte <= 126 then
          table.insert(buffer, cursor + 1, ch)
          cursor = cursor + 1
          break_history_navigation()
          saved_draft_valid = false
          refresh_line()
        else beep()
        end
      end
    end

    local ok, line, tag = pcall(reader_loop)
    restore_stty(stty_state)
    if not ok then
      local message = tostring(line or '')
      if message:find('interrupted!') then
        io.write('\n')
        io.flush()
        return nil, 'interrupt'
      end
      error(line)
    end
    return line, tag
  end
end

local posix_line_reader = create_posix_line_reader()

LineEditor = {
  read_line = function(prompt, history, opts)
    if linenoise then
      local line = linenoise.linenoise(prompt)
      if line and has_visible_chars(line) then pcall(linenoise.addhistory, line) end
      if line == nil then return nil, 'interrupt' end
      return line, nil
    end
    if posix_line_reader then
      local line, tag = posix_line_reader(prompt, history or {}, opts)
      return line, tag
    end
    io.write(prompt)
    io.flush()
    local line = io.read('*l')
    if line == nil then return nil, 'eof' end
    return line, nil
  end,
  has_visible_chars = has_visible_chars,
}
