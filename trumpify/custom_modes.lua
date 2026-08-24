-- Custom modes module for Trumpify
-- User-defined transformation modes stored as JSON outside the repo.

local constants = require("trumpify.constants")

local M = {}

local ID_PREFIX = "custom_"

-- ---------------------------------------------------------------------------
-- Pure helpers (unit-testable, no hs dependency)
-- ---------------------------------------------------------------------------

function M.normalize_id(name)
    if type(name) ~= "string" then return "mode" end
    local slug = name:lower()
        :gsub("[^%w]+", "_")
        :gsub("^_+", "")
        :gsub("_+$", "")
        :gsub("__+", "_")
    if slug == "" then return "mode" end
    return slug
end

function M.validate(mode)
    if type(mode) ~= "table" then
        return false, "mode must be a table"
    end
    local name = mode.name
    if type(name) ~= "string" or name:match("^%s*$") then
        return false, "missing or empty 'name'"
    end
    if type(mode.description) ~= "string" or mode.description:match("^%s*$") then
        return false, "'" .. name .. "': missing or empty 'description'"
    end
    if type(mode.system) ~= "string" or mode.system:match("^%s*$") then
        return false, "'" .. name .. "': missing or empty 'system' prompt"
    end
    if mode.key ~= nil then
        if type(mode.key) ~= "string" or #mode.key ~= 1 then
            return false, "'" .. name .. "': 'key' must be nil or a single character"
        end
    end
    return true, nil
end

function M.assign_ids(list)
    local out = {}
    local used = {}
    for _, entry in ipairs(list or {}) do
        local id = M.normalize_id(entry.name)
        while used[id] do
            id = id .. "_2"
        end
        used[id] = true
        local copy = {}
        for k, v in pairs(entry) do copy[k] = v end
        copy.id = id
        table.insert(out, copy)
    end
    return out
end

-- ---------------------------------------------------------------------------
-- JSON encoding/decoding: hs.json when available, dkjson as fallback
-- ---------------------------------------------------------------------------

function M.decode(text)
    if not text or text == "" then return nil, "empty input" end
    -- A bare 'null' is valid JSON but some decoders reject it at the top level
    if text:match("^%s*null%s*$") then return {}, nil end
    if hs and hs.json and hs.json.decode then
        local ok, decoded = pcall(hs.json.decode, text)
        if ok then
            return decoded or {}, nil
        end
        return nil, "json decode failed"
    end
    local has_dkjson, dkjson = pcall(require, "dkjson")
    if has_dkjson and dkjson and dkjson.decode then
        local decoded, err = dkjson.decode(text)
        if decoded == nil and err then return nil, err end
        return decoded or {}, nil
    end
    return nil, "no json decoder available"
end

function M.encode(value)
    if hs and hs.json and hs.json.encode then
        local ok, encoded = pcall(hs.json.encode, value)
        if ok then return encoded, nil end
        return nil, "json encode failed"
    end
    local has_dkjson, dkjson = pcall(require, "dkjson")
    if has_dkjson and dkjson and dkjson.encode then
        local encoded, err = dkjson.encode(value)
        if encoded == nil and err then return nil, err end
        return encoded, nil
    end
    return nil, "no json encoder available"
end

-- ---------------------------------------------------------------------------
-- Storage
-- ---------------------------------------------------------------------------

local function read_text_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

local function extract_array(payload)
    if type(payload) ~= "table" then return {} end
    -- Already an array of modes?
    if payload[1] ~= nil or #payload > 0 then
        local list = {}
        for _, entry in ipairs(payload) do
            if type(entry) == "table" then table.insert(list, entry) end
        end
        return list
    end
    -- Wrapped as { modes = [...] }?
    if type(payload.modes) == "table" then
        local list = {}
        for _, entry in ipairs(payload.modes) do
            if type(entry) == "table" then table.insert(list, entry) end
        end
        return list
    end
    return {}
end

function M.get_path()
    return constants.get_config_dir() .. "/" .. constants.CUSTOM_MODES_FILE_NAME
end

--- Load the user's custom modes. Returns a flat list of mode tables.
function M.load(path)
    path = path or M.get_path()
    local content = read_text_file(path)
    if not content then return {} end
    local payload = M.decode(content)
    if not payload then return {} end
    return extract_array(payload)
end

--- Persist a mode list. Returns ok, err.
function M.save(path, list)
    if path and type(path) == "table" then
        list = path
        path = nil
    end
    path = path or M.get_path()
    list = list or {}

    -- Strip derived fields; keep only what the editor needs back
    local clean = {}
    for _, mode in ipairs(list) do
        table.insert(clean, {
            id = mode.id,
            name = mode.name,
            description = mode.description,
            key = mode.key,
            system = mode.system,
        })
    end

    local encoded, err = M.encode(clean)
    if not encoded then
        return false, err or "json encode failed"
    end

    local f, open_err = io.open(path, "w")
    if not f then
        return false, open_err or "cannot open file for writing"
    end
    f:write(encoded)
    f:close()
    return true
end

-- ---------------------------------------------------------------------------
-- Merging into the prompt loader's mode table
-- ---------------------------------------------------------------------------

--- Merge a list of custom modes into an existing mode table (id -> mode).
--- Conflicting/invalid entries are skipped and reported. Returns the merged
--- table (a new table; `existing` is never mutated) and an error list.
function M.merge(existing, list)
    local merged = {}
    for k, v in pairs(existing or {}) do
        merged[k] = v
    end

    local errors = {}
    local names = {}
    for key, mode in pairs(merged) do
        names[mode.name] = key
    end

    for _, mode in ipairs(list or {}) do
        local ok, err = M.validate(mode)
        if not ok then
            table.insert(errors, "Custom mode '" .. tostring(mode.name or "?") .. "': " .. tostring(err))
        elseif names[mode.name] then
            table.insert(errors, "Custom mode '" .. mode.name ..
                "' conflicts with '" .. names[mode.name] .. "' (duplicate name), skipped.")
        else
            local id = ID_PREFIX .. (mode.id or M.normalize_id(mode.name))
            if merged[id] then
                table.insert(errors, "Custom mode '" .. mode.name ..
                    "' conflicts with existing id '" .. id .. "', skipped.")
            else
                local copy = {}
                for k, v in pairs(mode) do copy[k] = v end
                if copy.paste_back == nil then copy.paste_back = true end
                merged[id] = copy
                names[copy.name] = id
            end
        end
    end

    return merged, errors
end

return M
