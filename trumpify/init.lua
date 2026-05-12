local api = require("trumpify.api")
local selection = require("trumpify.selection")
local prompts = require("trumpify.prompts")

local M = {}

-- ---------------------------------------------------------------------------
-- Config
-- ---------------------------------------------------------------------------
local PROJECT_DIR = "/Users/i589040/Documents/GitHub/Trumpify"

api.loadApiKey(PROJECT_DIR .. "/.env")

-- ---------------------------------------------------------------------------
-- Alert styling (dark translucent overlay)
-- ---------------------------------------------------------------------------
local alertStyle = {
    strokeWidth = 0,
    strokeColor = { white = 0, alpha = 0 },
    fillColor = { white = 0, alpha = 0.75 },
    textColor = { white = 1, alpha = 1 },
    textFont = ".AppleSystemUIFont",
    textSize = 18,
    radius = 10,
    atScreenEdge = 0,
    fadeInDuration = 0.1,
    fadeOutDuration = 0.2,
    padding = 20,
}

-- ---------------------------------------------------------------------------
-- Summary dialog (stays until user clicks OK)
-- ---------------------------------------------------------------------------
local function showSummaryDialog(text)
    local screen = hs.screen.mainScreen()
    local frame = screen:frame()
    local x = frame.x + (frame.w / 2)
    local y = frame.y + (frame.h / 2)

    -- Non-blocking native macOS alert with OK button
    hs.dialog.alert(x, y, function(_) end, "Summary", text, "OK", nil, "informational")
end

-- ---------------------------------------------------------------------------
-- Core transformation handler
-- ---------------------------------------------------------------------------
local function executeTransform(mode, text, clipboardOnly)
    -- Show processing indicator (stays up to 60s, dismissed on completion)
    local label = mode.name .. (clipboardOnly and " (copy)" or "")
    local processingAlert = hs.alert.show(
        label .. "  -  Processing...",
        alertStyle, nil, 60
    )

    api.transform(text, mode.system, function(success, result)
        hs.alert.closeSpecific(processingAlert)

        if not success then
            hs.alert.show(mode.name .. " Error: " .. result, alertStyle, nil, 4)
            return
        end

        if clipboardOnly then
            hs.pasteboard.setContents(result)
            hs.alert.show(mode.name .. "  -  Copied to clipboard!", alertStyle, nil, 2)
        elseif mode.paste_back then
            selection.pasteText(result)
            hs.alert.show(mode.name .. "  -  Done!", alertStyle, nil, 2)
        else
            showSummaryDialog(result)
        end
    end)
end

local function handleTransform(mode, clipboardOnly)
    local text = selection.getSelectedText()
    if text == "" then
        hs.alert.show("No text selected", alertStyle, nil, 2)
        return
    end

    if mode.needs_input then
        local screen = hs.screen.mainScreen()
        local frame = screen:frame()
        local x = frame.x + (frame.w / 2)
        local y = frame.y + (frame.h / 2)

        hs.dialog.textPrompt(
            mode.name,
            mode.input_prompt or "Enter your notes:",
            "",
            "OK", "Cancel",
            true,
            function(result, input)
                if result == "Cancel" or (input and input == "") then return end
                local combined = "ORIGINAL MESSAGE:\n" .. text .. "\n\nMY NOTES:\n" .. input
                executeTransform(mode, combined, clipboardOnly)
            end,
            x, y
        )
    else
        executeTransform(mode, text, clipboardOnly)
    end
end

-- ---------------------------------------------------------------------------
-- Hotkey bindings: Ctrl + Option + <key>
-- With Shift: copy to clipboard only (don't paste)
-- ---------------------------------------------------------------------------
for _, mode in pairs(prompts.modes) do
    -- Normal: transform and paste back (or show dialog)
    hs.hotkey.bind({ "ctrl", "alt" }, mode.key, function()
        handleTransform(mode, false)
    end)
    -- With Shift: transform and copy to clipboard only
    hs.hotkey.bind({ "ctrl", "alt", "shift" }, mode.key, function()
        handleTransform(mode, true)
    end)
end

-- Ctrl+Option+R = reload Hammerspoon config
hs.hotkey.bind({ "ctrl", "alt" }, "r", function()
    hs.reload()
end)

-- ---------------------------------------------------------------------------
-- Chooser menu: Ctrl + Option + Space
-- ---------------------------------------------------------------------------
local chooser = hs.chooser.new(function(choice)
    if not choice then return end
    local mode = prompts.modes[choice.modeKey]
    if mode then
        handleTransform(mode, false)
    end
end)

-- Build chooser rows from all modes
local function buildChooserChoices()
    local choices = {}
    for key, mode in pairs(prompts.modes) do
        table.insert(choices, {
            text = mode.name,
            subText = mode.description .. "  (⌃⌥" .. string.upper(mode.key) .. ")",
            modeKey = key,
        })
    end
    table.sort(choices, function(a, b) return a.text < b.text end)
    return choices
end

chooser:choices(buildChooserChoices)
chooser:searchSubText(true)
chooser:placeholderText("Choose transformation...")

hs.hotkey.bind({ "ctrl", "alt" }, "space", function()
    chooser:show()
end)

-- ---------------------------------------------------------------------------
-- Startup notification
-- ---------------------------------------------------------------------------
hs.alert.show("Trumpify loaded!", alertStyle, nil, 2)

return M
