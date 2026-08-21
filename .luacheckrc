-- Luacheck configuration for Trumpify
-- See: https://github.com/mpeterv/luacheck

std = "lua54"

globals = { "hs" }
read_globals = { "hs" }

exclude_files = {
    "test/",
}

-- Silence common noisy warnings for a Hammerspoon script
ignore = {
    "212", -- unused argument
    "213", -- unused loop variable
    "631", -- line too long
}
