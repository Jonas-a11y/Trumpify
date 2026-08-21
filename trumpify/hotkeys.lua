local constants = require("trumpify.constants")
local config = require("trumpify.config")
local prompt_loader = require("trumpify.prompt_loader")
local transformer = require("trumpify.transformer")
local tts = require("trumpify.tts")
local ui = require("trumpify.ui")

local M = {}

local _registered_hotkeys = {}
local _reserved_keys = { r = "reload", space = "chooser", ["."] = "stop_tts", [","] = "reserved" }
local _chooser = nil

function M.get_reserved_keys()
    local copy = {}
    for k, v in pairs(_reserved_keys) do
        copy[k] = v
    end
    return copy
end

function M._get_key_for_mode(mode_id, mode)
    local keymap = config.get("keymap")
    local key = mode.key
    if keymap and keymap[mode_id] then
        key = keymap[mode_id]
    end
    -- Normalize: hs.hotkey.bind expects lowercase key names; the settings
    -- panel displays uppercase but must save lowercase.
    if type(key) == "string" then
        return key:lower()
    end
    return key
end

function M.register_all()
    M.unregister_all()

    local errors = {}
    local used_keys = {}

    local modes = prompt_loader.get_modes()
    local ordered = {}
    for mode_id, mode in pairs(modes) do
        table.insert(ordered, { id = mode_id, mode = mode })
    end
    table.sort(ordered, function(a, b) return a.id < b.id end)

    for _, entry in ipairs(ordered) do
        local mode_id = entry.id
        local mode = entry.mode
        local key = M._get_key_for_mode(mode_id, mode)

        if key and type(key) == "string" and #key == 1 then
            local lkey = key:lower()

            if _reserved_keys[lkey] then
                table.insert(errors, "Mode '" .. mode_id ..
                    "' key '" .. key .. "' collides with reserved key (" ..
                    _reserved_keys[lkey] .. "), skipped.")
            elseif used_keys[lkey] then
                table.insert(errors, "Mode '" .. mode_id ..
                    "' key '" .. key .. "' collides with mode '" ..
                    used_keys[lkey] .. "', skipped.")
            else
                local ok_bind, hk = pcall(hs.hotkey.bind, constants.MODIFIERS, key, function()
                    transformer.handle_transform(mode, false)
                end)
                local ok_bind_s, hk_shift = pcall(hs.hotkey.bind, constants.MODIFIERS_SHIFT, key, function()
                    transformer.handle_transform(mode, true)
                end)
                if ok_bind and ok_bind_s then
                    _registered_hotkeys[mode_id] = { normal = hk, shift = hk_shift }
                    used_keys[lkey] = mode_id
                else
                    table.insert(errors, "Mode '" .. mode_id ..
                        "': hs.hotkey.bind failed for key '" .. key .. "'")
                end
            end
        end
    end

    return errors
end

function M.unregister_all()
    for _, hotkeys in pairs(_registered_hotkeys) do
        if hotkeys.normal then pcall(function() hotkeys.normal:delete() end) end
        if hotkeys.shift then pcall(function() hotkeys.shift:delete() end) end
    end
    _registered_hotkeys = {}
end

function M.register_reload_hotkey()
    hs.hotkey.bind(constants.MODIFIERS, "r", function()
        hs.reload()
    end)
end

function M.register_stop_tts_hotkey()
    hs.hotkey.bind(constants.MODIFIERS, ".", function()
        tts.stop()
        ui.show_notification("TTS stopped")
    end)
end

local function _build_choices()
    local choices = prompt_loader.get_chooser_choices()
    table.insert(choices, {
        text = "Settings",
        subText = "Configure Trumpify",
        modeKey = "__settings__",
    })
    return choices
end

function M.create_chooser()
    local chooser = hs.chooser.new(function(choice)
        if not choice then return end
        if choice.modeKey == "__settings__" then
            local settings_panel = require("trumpify.settings_panel")
            settings_panel.show()
            return
        end
        local modes = prompt_loader.get_modes()
        local mode = modes[choice.modeKey]
        if mode then
            transformer.handle_transform(mode, false)
        end
    end)

    chooser:choices(_build_choices())
    chooser:searchSubText(true)
    chooser:placeholderText("Choose transformation...")

    _chooser = chooser

    hs.hotkey.bind(constants.MODIFIERS, "space", function()
        chooser:show()
    end)

    return chooser
end

function M.refresh_chooser()
    if _chooser then
        pcall(function() _chooser:choices(_build_choices()) end)
    end
end

function M.init()
    local errors = M.register_all()
    M.register_reload_hotkey()
    M.register_stop_tts_hotkey()
    return errors
end

return M
