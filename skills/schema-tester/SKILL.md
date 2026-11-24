---
name: schema-tester
description: Author and fix rimeapi.lua schema test configs for rimeapi.lua's schema_tester.lua. Use when the user asks to write, generate, extend, or debug a schema_tester config (for example schema_tester_config.lua), to test a Rime schema's candidates, options, properties, or patches.
---

# Writing schema_tester configs

`schema_tester.lua` runs declarative, data-driven tests against a Rime schema
using librime. A config is a plain Lua file that **returns a table**; it is
executed with `loadfile`, not `require`.

## Workflow

1. Read the target schema and identify its `schema_id`, key sequence(s) to test,
   and expected candidate/option/property behavior.
2. Write or extend the config table (see template below).
3. Run it and read the result table:

   ```sh
   ./schema_tester.lua path/to/config.lua
   ```

4. Each row is `send | assert | passed/failed`. The process exits non-zero if
   any assertion fails, so fix failing rows and re-run until it passes.
5. Do not invent expected output: derive candidate text from the schema/dictionary
   or from a first `run`/print pass rather than guessing.

## Minimal template

```lua
return {
  schema_id = 'luna_pinyin',
  user_data_dir = 'schema_test_user_data_dir', -- relative to the working directory
  -- shared_data_dir = 'shared',               -- default: <script_dir>/shared
  -- log_dir = 'log',                          -- default: <script_dir>/log
  deploy = {
    default = {
      tests = {
        { send = 'a', assert = "cand[1].text == '啊'" },
        -- run a helper for its output, without pass/fail:
        { send = 'wei', run = [[print(ctx.composition.preedit)]] },
      },
    },
  },
}
```

## Field reference

Top-level:

- `schema_id` — schema to select (default `luna_pinyin`).
- `user_data_dir` — writable user-data dir. A provided relative path resolves
  against the current working directory; when omitted it defaults to
  `<script_dir>/schema_tester`. Use a dedicated directory.
- `shared_data_dir` — default `<script_dir>/shared`. Set it when the schema is
  not in the default shared data.
- `log_dir` — default `<script_dir>/log`.
- `deploy` — map of group name to a group table. **Group order is not
  guaranteed** (`pairs`); never depend on one group running before another.

Each `deploy.<group>`:

- `tests` — array of test tables, executed in order.
- `options` — `{ name = boolean }` set before the group, restored after.
- `properties` — `{ name = string }` set before the group, restored after.
- `patch` — array of `{ key = 'path/in/config', value = 'yaml string' }`,
  applied through librime levers before the group and removed after.

Each test:

- `send` — required Rime key sequence passed to `simulate_key_sequence`.
- `assert` — Lua expression or function, evaluated after `send`. It must
  evaluate to **boolean `true`** to pass; anything else fails.
- `run` — Lua expression or function run in a side-effect/dry-run pass (e.g. to
  print candidates). `run` does not affect pass/fail, and its `send` is replayed.
- `options` / `properties` — array of names to expose as variables in
  `assert`/`run` (values are read from the session).

Inside `assert`/`run` the environment exposes:

- `cand` — candidate array (`ctx.menu.candidates`); `cand[1].text`, `#cand`, ...
- `ctx` — `RimeContext` (`ctx.composition.preedit`, ...).
- `status` — `RimeStatus` (`status.is_ascii_mode`, ...).
- `commit` — `RimeCommit` (`commit.text`).
- every option/property name listed in the test's `options`/`properties`.
- every top-level function defined in the config table, by name.

## Key sequence notation

`send` uses librime key notation:

- plain text is typed as-is: `'wei'`, `'zhishiyunxing'`
- named keys are braced: `'{space}'`, `'{Return}'`, `'{Escape}'`
- chords use `+`: `'{Shift_L}{Release+Shift_L}'`, `'{Control+space}'`

Composition is cleared after every test, so each test starts from a clean
session; options/properties/patch persist for the whole group.

## Common patterns

Setting and checking options:

```lua
deploy = {
  ascii = {
    options = { ascii_mode = true },
    tests = {
      { send = 'a', options = { 'ascii_mode' }, assert = 'ascii_mode == true' },
    },
  },
}
```

Using a patch for the group (removed automatically afterwards):

```lua
patch = {
  patch = {
    { key = 'engine/translators', value = '[]' },
  },
  tests = {
    { send = 'ceshi', assert = '#cand == 0' },
  },
}
```

Reusing functions defined in the config:

```lua
local function is_a()
  return cand[1].text == '啊'
end

return {
  schema_id = 'luna_pinyin',
  deploy = {
    default = {
      tests = {
        { send = 'a', assert = is_a },
        { send = 'a', assert = "cand[1].text == '啊'" },
      },
    },
  },
}
```

## Gotchas

- The config must `return` a table; do not use `module(...)` or return nothing.
- `assert` must be true, not merely truthy: return a boolean comparison.
- Tests within a group are independent because composition is cleared per test;
  do not chain state across `send` entries.
- Do not rely on group ordering or on a group's options/patch leaking into
  another group; they are restored/removed per group, and the schema userdb is
  deleted after each group.
- Prefer relative `user_data_dir`; absolute/Windows path handling differs.
- `run` is for inspection only. If a test needs both output and verification,
  use `run` for the side effect and a separate `assert` test for the check.
- Always finish by running the config and confirming a zero exit status.
