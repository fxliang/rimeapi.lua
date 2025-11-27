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
    simplification = {
      options = { zh_simp = true, zh_trad = false },
      tests = {
        { send = 'wei', assert = "cand[1].text == '为'" }
      },
    },
    patch = {
      -- one line patch supported only for now
      patch = { 'engine/translators: []' },
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
