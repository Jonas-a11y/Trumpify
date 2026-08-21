local constants = require("trumpify.constants")

local M = {}

function M.get_selected_text()
    local sel = nil

    local ok, elem = pcall(hs.uielement.focusedElement)
    if ok and elem then
        local ok_sel, s = pcall(function() return elem:selectedText() end)
        if ok_sel then sel = s end
    end

    if (not sel) or (sel == "") then
        sel = M._clipboard_fallback()
    end

    return (sel or "")
end

function M._clipboard_fallback()
    local original_clipboard = hs.pasteboard.getContents()
    local original_change_count = hs.pasteboard.changeCount()

    for i = 1, constants.CLIPBOARD_MAX_RETRIES do
        hs.eventtap.keyStroke({ "cmd" }, "c")
        hs.timer.usleep(constants.CLIPBOARD_COPY_DELAY)

        local copied_text = hs.pasteboard.getContents()
        local new_change_count = hs.pasteboard.changeCount()

        if copied_text and new_change_count > original_change_count and copied_text ~= "" then
            -- Restore only if user has not modified clipboard since
            local restore_change_count = new_change_count
            if original_clipboard then
                hs.timer.doAfter(0.15, function()
                    if hs.pasteboard.changeCount() == restore_change_count then
                        hs.pasteboard.setContents(original_clipboard)
                    end
                end)
            end
            return copied_text
        end

        if i < constants.CLIPBOARD_MAX_RETRIES then
            hs.timer.usleep(constants.CLIPBOARD_RETRY_DELAY)
        end
    end

    return ""
end

function M.paste_text(text)
    hs.pasteboard.setContents(text)
    hs.timer.usleep(constants.PASTE_DELAY)
    hs.eventtap.keyStroke({ "cmd" }, "v")
end

function M.copy_to_clipboard(text)
    hs.pasteboard.setContents(text)
end

return M
