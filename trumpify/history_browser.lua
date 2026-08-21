local constants = require("trumpify.constants")
local history = require("trumpify.history")
local selection = require("trumpify.selection")
local tts = require("trumpify.tts")
local ui = require("trumpify.ui")

local M = {}

-- Pure helper: build chooser choices from history entries (testable).
function M.build_choices(entries)
    local choices = {}
    for i, entry in ipairs(entries or {}) do
        local time_str = os.date("%H:%M:%S", entry.timestamp or os.time())
        local preview = tostring(entry.output or "")
        if #preview > 120 then
            preview = preview:sub(1, 120) .. "..."
        end
        table.insert(choices, {
            text = entry.mode .. "  (" .. time_str .. ")",
            subText = preview:gsub("\n", " "),
            idx = i,
        })
    end
    return choices
end

-- Execute an action on a history entry.
function M.run_action(entry, action)
    if not entry or not entry.output then return end

    if action == "copy" then
        selection.copy_to_clipboard(entry.output)
        ui.show_notification(constants.NOTIFICATIONS.COPIED_TO_CLIPBOARD)
    elseif action == "paste" then
        selection.paste_text(entry.output)
        ui.show_notification(constants.NOTIFICATIONS.DONE)
    elseif action == "speak" then
        tts.speak(entry.output)
        ui.show_alert("Read Aloud  -  " .. constants.NOTIFICATIONS.TTS_SPEAKING,
            constants.DURATIONS.NOTIFICATION)
    end
end

function M._show_action_chooser(entry)
    local actions = {
        { text = "Copy",       subText = "Copy the result to the clipboard", action = "copy" },
        { text = "Paste",      subText = "Paste the result at the cursor",   action = "paste" },
        { text = "Read Aloud", subText = "Speak the result",                 action = "speak" },
    }

    local chooser = hs.chooser.new(function(choice)
        if not choice then return end
        M.run_action(entry, choice.action)
    end)
    chooser:choices(actions)
    chooser:placeholderText("What do you want to do with this result?")
    chooser:show()
end

function M.show()
    local entries = history.get_all()
    if #entries == 0 then
        ui.show_notification("No history yet")
        return
    end

    local chooser = hs.chooser.new(function(choice)
        if not choice then return end
        local entry = entries[choice.idx]
        if entry then
            M._show_action_chooser(entry)
        end
    end)
    chooser:choices(M.build_choices(entries))
    chooser:searchSubText(true)
    chooser:placeholderText("History - select an entry...")
    chooser:show()
end

return M