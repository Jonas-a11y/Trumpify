local M = {}

function M.getSelectedText()
    -- Try accessibility API first (instant, no clipboard side-effects)
    local elem = hs.uielement.focusedElement()
    local sel = nil
    if elem then
        sel = elem:selectedText()
    end

    -- Fallback: simulate Cmd+C and read clipboard
    if (not sel) or (sel == "") then
        hs.eventtap.keyStroke({"cmd"}, "c")
        hs.timer.usleep(50000) -- 50ms for copy to propagate
        sel = hs.pasteboard.getContents()
    end

    return (sel or "")
end

function M.pasteText(text)
    hs.pasteboard.setContents(text)
    hs.timer.usleep(10000) -- 10ms
    hs.eventtap.keyStroke({"cmd"}, "v")
end

return M
