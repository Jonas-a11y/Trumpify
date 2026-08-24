local constants = require("trumpify.constants")

local M = {}

local _config = nil

local function read_text_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

local function extract_json_string(content, key)
    local pattern = '"' .. key .. '"%s*:%s*"([^"]+)"'
    return content:match(pattern)
end

local function extract_json_number(content, key)
    local pattern = '"' .. key .. '"%s*:%s*(%-?%d+%.?%d*)'
    local val = content:match(pattern)
    if val then return tonumber(val) end
    return nil
end

local function extract_keymap(content)
    -- Find "keymap": { ... }
    local block = content:match('"keymap"%s*:%s*(%b{})')
    if not block then return nil end
    local map = {}
    for k, v in block:gmatch('"([%w_]+)"%s*:%s*"([^"]+)"') do
        map[k] = v
    end
    if next(map) == nil then return nil end
    return map
end

local function parse_config_string(content)
    if not content or content == "" then return nil end

    -- Try hs.json.decode first (most robust)
    if hs and hs.json and hs.json.decode then
        local ok, decoded = pcall(hs.json.decode, content)
        if ok and type(decoded) == "table" then
            local clean = {}
            for k, v in pairs(decoded) do
                -- Skip _comment fields to keep example config compatible
                if not tostring(k):match("^_") then
                    clean[k] = v
                end
            end
            if next(clean) ~= nil then
                return clean
            end
        end
    end

    -- Fallback: pure Lua pattern matching
    local cfg = {}
    local api_key = extract_json_string(content, "apiKey")
    if api_key then cfg.apiKey = api_key end

    local endpoint = extract_json_string(content, "endpoint")
    if endpoint then cfg.endpoint = endpoint end

    local model = extract_json_string(content, "model")
    if model then cfg.model = model end

    local max_tokens = extract_json_number(content, "maxTokens")
    if max_tokens then cfg.maxTokens = max_tokens end

    local keymap = extract_keymap(content)
    if keymap then cfg.keymap = keymap end

    if next(cfg) == nil then return nil end
    return cfg
end

local function load_config_file(path)
    local content = read_text_file(path)
    return parse_config_string(content)
end

local function load_env_file(env_path)
    local content = read_text_file(env_path)
    if not content then return nil end
    return content:match("HAIPROXY_API_KEY=([^\n%s]+)")
end

local function merge(base, overrides)
    local result = {}
    for k, v in pairs(base) do
        if type(v) == "table" then
            local copy = {}
            for kk, vv in pairs(v) do copy[kk] = vv end
            result[k] = copy
        else
            result[k] = v
        end
    end
    for k, v in pairs(overrides) do
        if type(v) == "table" and type(result[k]) == "table" then
            local merged = {}
            for kk, vv in pairs(result[k]) do merged[kk] = vv end
            for kk, vv in pairs(v) do merged[kk] = vv end
            result[k] = merged
        else
            result[k] = v
        end
    end
    return result
end

function M.init()
    local config_dir = constants.get_config_dir()
    local project_dir = constants.get_project_dir()

    _config = {}
    for k, v in pairs(constants.DEFAULT_API_CONFIG) do
        _config[k] = v
    end

    -- Load project config as base
    local project_config_path = project_dir .. "/" .. constants.CONFIG_FILE_NAME
    local project_config = load_config_file(project_config_path)
    if project_config then
        _config = merge(_config, project_config)
    end

    -- User config overrides project config
    local user_config_path = config_dir .. "/" .. constants.CONFIG_FILE_NAME
    local user_config = load_config_file(user_config_path)
    if user_config then
        _config = merge(_config, user_config)
    end

    -- .env fallback for API key
    if not _config.apiKey then
        local env_path = project_dir .. "/.env"
        local env_key = load_env_file(env_path)
        if env_key then
            _config.apiKey = env_key
        end
    end

    -- Environment variable last-resort
    if not _config.apiKey then
        _config.apiKey = os.getenv("HAIPROXY_API_KEY")
    end
end

function M.get(key)
    if _config == nil then return nil end
    return _config[key]
end

function M.get_all()
    return _config
end

-- Keys managed by the settings panel; only these are written back on save.
local MANAGED_KEYS = { "tts", "keymap", "disabledModes", "endpoint", "model",
    "maxTokens", "apiKey", "translate" }

function M.set(key, value)
    if _config == nil then
        return false, "config not initialized"
    end
    _config[key] = value
    return true
end

local function encode_json(value)
    -- Pure-Lua JSON encoder fallback (handles strings, numbers, booleans,
    -- arrays and string-keyed tables; sufficient for the managed keys)
    local vtype = type(value)
    if value == nil then
        return "null"
    elseif vtype == "boolean" then
        return tostring(value)
    elseif vtype == "number" then
        return tostring(value)
    elseif vtype == "string" then
        local escaped = value
            :gsub("\\", "\\\\")
            :gsub('"', '\\"')
            :gsub("\n", "\\n")
            :gsub("\r", "\\r")
            :gsub("\t", "\\t")
            :gsub("%c", function(c) return string.format("\\u%04x", c:byte()) end)
        return '"' .. escaped .. '"'
    elseif vtype == "table" then
        -- Detect array-like tables
        local is_array = true
        local n = 0
        for k, _ in pairs(value) do
            n = n + 1
            if type(k) ~= "number" or k ~= n then
                is_array = false
            end
        end
        if is_array then
            local parts = {}
            for i = 1, n do
                table.insert(parts, encode_json(value[i]))
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, v in pairs(value) do
                table.insert(parts, encode_json(tostring(k)) .. ":" .. encode_json(v))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

function M.save_to(path)
    if not path or path == "" then
        return false, "no path given"
    end
    if _config == nil then
        return false, "config not initialized"
    end

    -- Read existing file to preserve unmanaged keys (e.g. apiKey, comments)
    local raw = read_text_file(path)
    local disk = nil
    if raw and raw ~= "" then
        if hs and hs.json and hs.json.decode then
            local ok, decoded = pcall(hs.json.decode, raw)
            if ok and type(decoded) == "table" then
                disk = decoded
            end
        end
        if not disk then
            -- Fallback: recover known flat keys via pattern matching
            disk = parse_config_string(raw)
        end
    end
    if not disk or type(disk) ~= "table" then
        disk = {}
    end

    -- Overwrite only the managed keys; nil removes them from disk
    for _, key in ipairs(MANAGED_KEYS) do
        disk[key] = _config[key]
    end

    local encoded
    if hs and hs.json and hs.json.encode then
        local ok, result = pcall(hs.json.encode, disk, true)
        if not ok or not result then
            return false, "json encode failed"
        end
        encoded = result
    else
        encoded = encode_json(disk)
    end

    local f, err = io.open(path, "w")
    if not f then
        return false, err or "cannot open file for writing"
    end
    f:write(encoded)
    f:close()
    return true
end

function M.save()
    local path = constants.get_project_dir() .. "/" .. constants.CONFIG_FILE_NAME
    return M.save_to(path)
end

return M
