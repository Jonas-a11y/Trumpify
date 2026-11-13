local constants = require("trumpify.constants")
local history = require("trumpify.history")
local selection = require("trumpify.selection")
local tts = require("trumpify.tts")
local ui = require("trumpify.ui")

local M = {}

local function save_mode(entry)
    ui.show_text_prompt("Als Modus speichern", "Name für diese Variante:", function(result, name)
        if not result then return end
        local custom_modes = require("trumpify.custom_modes")
        local candidate = { name = name, description = "Saved from " .. entry.mode, system = entry.system }
        candidate.id = custom_modes.normalize_id(name)
        local loader = require("trumpify.prompt_loader")
        local _, errors = custom_modes.merge(loader.get_all_modes(), { candidate })
        if #errors > 0 then ui.show_error(table.concat(errors, "\n")); return end
        local list = custom_modes.load()
        table.insert(list, candidate)
        local ok, err = custom_modes.save(nil, list)
        if not ok then ui.show_error(err); return end
        loader.init()
        local hotkeys = require("trumpify.hotkeys")
        local hotkey_errors = hotkeys.register_all()
        hotkeys.refresh_chooser()
        if #hotkey_errors > 0 then ui.show_error(table.concat(hotkey_errors, "\n")); return end
        ui.show_notification("Mode saved: " .. name)
    end)
end

function M.show_entry(entry, target)
    local actions = { { id = "copy", label = "Kopieren" }, { id = "paste", label = "Einfügen" } }
    table.insert(actions, { id = "speak", label = "Vorlesen" })
    if entry.system then
        table.insert(actions, { id = "rewrite", label = "Neu formulieren" })
        table.insert(actions, { id = "save", label = "Als Modus speichern" })
    end
    return ui.show_scrollable_text(entry.mode, entry.output, {
        original = entry.input, actions = actions,
        on_action = function(action)
            if action == "rewrite" then
                require("trumpify.transformer").execute_transform(entry.mode_definition, entry.input,
                    true, entry.system, function(updated) M.show_entry(updated, target) end)
            elseif action == "save" then
                save_mode(entry)
            elseif action == "paste" and target then
                target:activate()
                hs.timer.doAfter(0.15, function() M.run_action(entry, action) end)
            else
                M.run_action(entry, action)
            end
        end,
    })
end

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

function M.show()
    local target = hs.application.frontmostApplication()
    local entries = history.get_all()
    if #entries == 0 then
        ui.show_notification("No history yet")
        return
    end

    local chooser = hs.chooser.new(function(choice)
        if not choice then return end
        local entry = entries[choice.idx]
        if entry then
            M.show_entry(entry, target)
        end
    end)
    chooser:choices(M.build_choices(entries))
    chooser:searchSubText(true)
    chooser:placeholderText("History - select an entry...")
    chooser:show()
end

return M
