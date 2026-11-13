local constants = require("trumpify.constants")
local config = require("trumpify.config")
local ui = require("trumpify.ui")
local selection = require("trumpify.selection")
local api = require("trumpify.api")
local history = require("trumpify.history")
local tts = require("trumpify.tts")
local creative = require("trumpify.creative")

local M = {}

local _initialized = false
local _active = nil

local AUTO_TARGET_LANGUAGE =
    "German if the text is German, otherwise English (detect the source language first)"

--- Resolve a mode's system prompt. Supports the {target_language} placeholder,
--- which is replaced with the configured translation target
--- (config key "translate" -> { target = "..." }).
function M.build_system(mode)
    local system = creative.build_system(mode)
    if type(system) ~= "string" or not system:find("{target_language}", 1, true) then
        return system
    end

    local target = nil
    local translate_cfg = config.get("translate")
    if type(translate_cfg) == "table" and type(translate_cfg.target) == "string" then
        local trimmed = translate_cfg.target:match("^%s*(.-)%s*$")
        if trimmed ~= "" then target = trimmed end
    end

    return system:gsub("{target_language}", target or AUTO_TARGET_LANGUAGE)
end

function M.init()
    _initialized = true
end

function M.cancel(notify)
    if not _active then return false end
    if _active.request then _active.request.cancel() end
    ui.close_processing(_active.alert)
    _active = nil
    if notify then ui.show_notification("Transformation cancelled") end
    return true
end

function M.execute_transform(mode, text, clipboard_only, system_override, on_complete)
    local label = mode.name .. (clipboard_only and " (copy)" or "")

    if mode.tts_only then
        -- TTS only mode: skip API, just speak the selected text
        tts.speak(text)
        history.add(mode.name, text, text)
        ui.show_alert(mode.name .. "  -  " .. constants.NOTIFICATIONS.TTS_SPEAKING,
            constants.DURATIONS.NOTIFICATION)
        return
    end

    if _active and _active.name == mode.name and _active.text == text
        and _active.clipboard_only == clipboard_only and _active.system_override == system_override then
        ui.show_notification("Already processing this text (⌃⌥. to cancel)")
        return
    end
    M.cancel(false)
    local system = system_override or M.build_system(mode)
    local job = { name = mode.name, text = text, clipboard_only = clipboard_only,
        system_override = system_override, alert = ui.show_processing(label) }
    _active = job

    job.request = api.transform(text, system, function(success, result)
        if _active ~= job then return end
        _active = nil
        ui.close_processing(job.alert)

        if not success then
            ui.show_error(mode.name .. ": " .. result)
            return
        end

        history.add(mode.name, text, result, { mode = mode, system = system })

        if clipboard_only then
            selection.copy_to_clipboard(result)
            ui.show_clipboard_success(mode.name)
        elseif mode.paste_back then
            selection.paste_text(result)
            ui.show_success(mode.name)
        else
            if mode.read_summary then
                tts.speak(result)
                ui.show_alert(mode.name .. "  -  " .. constants.NOTIFICATIONS.TTS_SPEAKING,
                    constants.DURATIONS.NOTIFICATION)
            end
            ui.show_summary_dialog(result)
        end
        if on_complete then on_complete(history.get_latest()) end
    end, function(retry)
        if _active ~= job then return end
        ui.close_processing(job.alert)
        job.alert = ui.show_retry(label, retry)
    end)
end

function M.handle_transform(mode, clipboard_only)
    if not _initialized then
        ui.show_error("Transformer not initialized")
        return
    end

    local text = selection.get_selected_text()
    if text == "" then
        ui.show_error(constants.NOTIFICATIONS.NO_TEXT_SELECTED)
        return
    end

    if #text > constants.LARGE_TEXT_WARNING_THRESHOLD then
        ui.show_alert(constants.NOTIFICATIONS.LARGE_TEXT_WARNING:gsub("{chars}", tostring(#text)), 2)
    end

    if mode.needs_input then
        ui.show_text_prompt(
            mode.name,
            mode.input_prompt or "Enter your notes:",
            function(result, input)
                if not result or not input then return end
                local combined = "ORIGINAL MESSAGE:\n" .. text .. "\n\nMY NOTES:\n" .. input
                M.execute_transform(mode, combined, clipboard_only)
            end
        )
    else
        M.execute_transform(mode, text, clipboard_only)
    end
end

return M
