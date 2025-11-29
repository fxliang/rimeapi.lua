return {
  schema_id = 'luna_pinyin',
  user_data_dir = 'schema_test_user_data_dir',
  shared_data_dir = 'shared',
  deploy = {
    default = {
      tests = {
        { send = 'a', assert = "cand[1].text == '啊'" },
        { send = 'b', assert = "cand[1].text == '不'" },
        { send = 'wei', assert = "cand[1].text == '爲'" },
      },
    },
    opt_and_prop = {
      options = { zh_simp = true, zh_trad = false }, -- set options before tests, reset after tests
      properties = { mode = '简化字模式' },          -- set properties before tests, reset empty after tests
      tests = {
        -- test table struct
        --[[
          { 
            send = 'key_sequence_to_send',
            assert = 'lua_expression_to_assert',  -- lua expression string to be evaluated, ctx, status, commit, cand are exposed
                                                  -- property names and option names in the following tables are also exposed
            properties = { 'prop1', 'prop2' },    -- table_of_props_to_expose
            options = { 'opt1', 'opt2' },         -- table_of_opts_to_expose
          }
        --]]
        { send = 'wei', assert = "cand[1].text == '为'" },
        { send = 'a', assert = "mode == '简化字模式'", properties = { 'mode' }, options = { 'zh_simp', 'zh_trad' } },
        { send = 'a', assert = "zh_simp == true", properties = { 'mode' }, options = { 'zh_simp', 'zh_trad' } },
        { send = 'a', assert = "zh_trad == false", properties = { 'mode' }, options = { 'zh_simp', 'zh_trad' } },
        { send = 'wei', assert = "ctx.composition.preedit == 'wei'" },
        { send = 'wei', assert = "status.is_ascii_mode == false" },
        { send = 'a', assert = "ascii_mode == false", options = {'ascii_mode'} },
        { send = '{Shift_L}{Release+Shift_L}', assert = "status.is_ascii_mode == true" },
        { send = '{Shift_L}{Release+Shift_L}', assert = "status.is_ascii_mode == false" },
      },
    },
    patch = {
      patch = {
        -- example patch lines table of { key = key_name value = yaml_string }
        { key = 'engine/translators', value = '[]' },
      },
      tests = {
        { send = 'ceshi', assert = "#cand == 0" }
      },
    },
    --[[
    failed = {
      tests = {
        { send = 'shibai', assert = "cand[1].text == '失败测试'"}
      }
    },
    --]]
  },
}
