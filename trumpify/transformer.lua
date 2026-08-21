local constants = require("trumpify.constants")
local config = require("trumpify.config")
local ui = require("trumpify.ui")
local selection = require("trumpify.selection")
local api = require("trumpify.api")
local history = require("trumpify.history")
local tts = require("trumpify.tts")

local M = {}

local _initialized = false

function M.init()
    _initialized = true
end

function M.execute_transform(mode, text, clipboard_only)
    local label = mode.name .. (clipboard_only and " (copy)" or "")

    if mode.tts_only then
        -- TTS only mode: skip API, just speak the selected text
        tts.speak(text)
        history.add(mode.name, text, text)
        ui.show_alert(mode.name .. "  -  " .. constants.NOTIFICATIONS.TTS_SPEAKING,
            constants.DURATIONS.NOTIFICATION)
        return
    end

    local processing_alert = ui.show_processing(label)

    api.transform(text, mode.system, function(success, result)
        ui.close_processing(processing_alert)

        if not success then
            ui.show_error(mode.name .. ": " .. result)
            return
        end

        history.add(mode.name, text, result)

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