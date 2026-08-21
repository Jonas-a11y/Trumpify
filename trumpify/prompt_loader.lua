local constants = require("trumpify.constants")
local config = require("trumpify.config")

local M = {}

local _modes = {}
local _loaded_from = nil

local function _is_enabled(mode_id)
    local disabled = config.get("disabledModes")
    if type(disabled) ~= "table" then return true end
    for _, id in ipairs(disabled) do
        if id == mode_id then return false end
    end
    return true
end

local function validate_mode(key, mode)
    if not mode.name or type(mode.name) ~= "string" then
        return false, "Mode '" .. tostring(key) .. "' missing 'name' (string)"
    end
    if not mode.description or type(mode.description) ~= "string" then
        return false, "Mode '" .. key .. "' missing 'description' (string)"
    end
    if mode.key ~= nil and (type(mode.key) ~= "string" or #mode.key ~= 1) then
        return false, "Mode '" .. key .. "' 'key' must be nil or a single character"
    end
    if not mode.tts_only and (not mode.system or type(mode.system) ~= "string" or mode.system == "") then
        return false, "Mode '" .. key .. "' missing 'system' prompt (non-empty string)"
    end
    if mode.paste_back == nil then
        mode.paste_back = true
    end

    for k, existing in pairs(_modes) do
        if k ~= key and (existing.name == mode.name) then
            return false, "Mode '" .. key .. "' conflicts with '" .. k .. "' (duplicate name)"
        end
        if k ~= key and mode.key and existing.key == mode.key then
            return false, "Mode '" .. key .. "' conflicts with '" .. k .. "' (duplicate key '" .. mode.key .. "')"
        end
    end

    return true, nil
end

local function list_lua_files(prompts_dir)
    local files = {}

    -- Prefer hs.fs.dir if available
    if hs and hs.fs and hs.fs.dir then
        local ok, iter, dir_obj = pcall(hs.fs.dir, prompts_dir)
        if ok and iter then
            for name in iter, dir_obj do
                if type(name) == "string" and name:match("%.lua$") then
                    table.insert(files, prompts_dir .. "/" .. name)
                end
            end
            return files
        end
    end

    -- Fallback: io.popen ls
    local ls_cmd = "ls -1 " .. prompts_dir .. "/*.lua 2>/dev/null"
    local f = io.popen(ls_cmd, "r")
    if not f then return files end
    for file in f:lines() do
        table.insert(files, file)
    end
    f:close()
    return files
end

local function load_from_dir(prompts_dir)
    local files = list_lua_files(prompts_dir)
    if #files == 0 then return nil end

    local modes = {}
    local errors = {}

    for _, filepath in ipairs(files) do
        local filename = filepath:match("/([^/]+)%.lua$") or filepath:match("([^/]+)%.lua$")
        if filename and filename ~= "init" then
            local ok, mod = pcall(dofile, filepath)
            if ok and type(mod) == "table" then
                local mode_key = filename:lower():gsub("[^a-z0-9_]", "_")
                local validate_ok, err = validate_mode(mode_key, mod)
                if validate_ok then
                    modes[mode_key] = mod
                else
                    table.insert(errors, err)
                end
            else
                table.insert(errors, "Failed to load '" .. filepath .. "': invalid return value")
            end
        end
    end

    if next(modes) == nil then return nil, errors end
    return modes, errors
end

local function load_from_embedded()
    local ok, prompts = pcall(require, "trumpify.prompts")
    if ok and prompts and prompts.modes then
        local modes = {}
        for key, mode in pairs(prompts.modes) do
            local validate_ok, err = validate_mode(key, mode)
            if validate_ok then
                modes[key] = mode
            end
        end
        if next(modes) ~= nil then
            return modes
        end
    end
    return nil
end

function M.init()
    local project_dir = constants.get_project_dir()
    local prompts_dir = project_dir .. "/" .. constants.PROMPTS_DIR_NAME

    local dir_modes, dir_errors = load_from_dir(prompts_dir)
    if dir_modes then
        _modes = dir_modes
        _loaded_from = "directory"
        return dir_errors
    end

    local embedded_modes = load_from_embedded()
    if embedded_modes then
        _modes = embedded_modes
        _loaded_from = "embedded"
        return nil
    end

    _modes = {}
    _loaded_from = "none"
    return { "No prompts found in '" .. prompts_dir .. "' or embedded prompts.lua" }
end

function M.get_modes()
    local out = {}
    for id, mode in pairs(_modes) do
        if _is_enabled(id) then
            out[id] = mode
        end
    end
    return out
end

function M.get_all_modes()
    return _modes
end

function M.get_mode(key)
    if not _is_enabled(key) then return nil end
    return _modes[key]
end

function M.get_loaded_from()
    return _loaded_from
end

function M.get_chooser_choices()
    local choices = {}
    local keymap = config.get("keymap")
    for key_id, mode in pairs(_modes) do
        if _is_enabled(key_id) then
            -- Show the effective key (keymap override wins over the default)
            local key = (keymap and keymap[key_id]) or mode.key
            local key_hint = key and " (⌃⌥" .. string.upper(key) .. ")" or ""
            table.insert(choices, {
                text = mode.name,
                subText = mode.description .. key_hint,
                modeKey = key_id,
            })
        end
    end
    table.sort(choices, function(a, b) return a.text < b.text end)
    return choices
end

return M