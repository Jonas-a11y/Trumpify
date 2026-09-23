local constants = require("trumpify.constants")

local M = {}

function M.get_screen_center()
    local screen = hs.screen.mainScreen()
    local frame = screen:frame()
    return {
        x = frame.x + (frame.w / 2),
        y = frame.y + (frame.h / 2),
    }
end

function M.show_alert(message, duration, style)
    hs.alert.show(message, style or constants.ALERT_STYLE, nil, duration or constants.DURATIONS.NOTIFICATION)
end

function M.show_notification(message)
    M.show_alert(message, constants.DURATIONS.NOTIFICATION)
end

function M.show_error(message)
    M.show_alert(constants.NOTIFICATIONS.ERROR_PREFIX .. message, constants.DURATIONS.ERROR)
end

function M.show_success(mode_name)
    M.show_alert(mode_name .. "  -  " .. constants.NOTIFICATIONS.DONE, constants.DURATIONS.SUCCESS)
end

function M.show_clipboard_success(mode_name)
    M.show_alert(mode_name .. "  -  " .. constants.NOTIFICATIONS.COPIED_TO_CLIPBOARD, constants.DURATIONS.SUCCESS)
end

function M.show_processing(label)
    return hs.alert.show(label .. "  -  " .. constants.NOTIFICATIONS.PROCESSING,
        constants.PROCESSING_ALERT_STYLE, nil, 60)
end

function M.show_retry(label, retry)
    local seconds = math.max(1, math.ceil(retry.delay or 0))
    local message = string.format(
        "%s  -  %s\nRetrying in %ds  ·  attempt %d/%d",
        label,
        retry.reason or "LLM connection issue",
        seconds,
        retry.attempt or 1,
        retry.total or 1
    )
    return hs.alert.show(message, constants.PROCESSING_ALERT_STYLE, nil, 60)
end

function M.close_processing(alert_id)
    if alert_id then
        hs.alert.closeSpecific(alert_id)
    end
end

function M.show_summary_dialog(text)
    -- hs.dialog.alert can open behind the application the user is working in.
    -- The webview is explicitly brought above all windows and works for both
    -- short and long summaries, so the result cannot be missed.
    return M.show_scrollable_text("Summary", text)
end

function M.show_scrollable_text(title, text)
    local screen = hs.screen.mainScreen()
    local frame = screen:frame()
    local w = math.min(frame.w * 0.7, 700)
    local h = math.min(frame.h * 0.6, 500)
    local x = frame.x + (frame.w - w) / 2
    local y = frame.y + (frame.h - h) / 2

    local webview = hs.webview.new({ x = x, y = y, w = w, h = h }, {
        developerExtras = false,
    })

    local escaped_text = text
        :gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")

    local html = [[<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  html, body { height: 100%; margin: 0; }
  body {
    font-family: -apple-system, sans-serif;
    font-size: 14px;
    padding: 20px;
    background: #1e1e1e;
    color: #e0e0e0;
    line-height: 1.5;
    box-sizing: border-box;
  }
  pre {
    white-space: pre-wrap;
    word-wrap: break-word;
    margin: 0;
    font-family: -apple-system, sans-serif;
  }
</style>
</head>
<body>
<pre>]] .. escaped_text .. [[</pre>
</body>
</html>]]

    if webview.windowStyle then
        pcall(function()
            webview:windowStyle({ "titled", "closable", "resizable" })
        end)
    end
    if webview.windowTitle then
        pcall(function() webview:windowTitle(title) end)
    end

    webview:html(html)
    if webview.allowNewWindows then webview:allowNewWindows(false) end
    if webview.allowTextEntry then webview:allowTextEntry(true) end

    webview:show()
    if webview.bringToFront then pcall(function() webview:bringToFront(true) end) end

    -- Escape closes the window
    local modal = hs.hotkey.modal.new()
    modal:bind({}, "escape", function()
        modal:exit()
        pcall(function() webview:delete() end)
    end)
    modal:bind({}, "return", function()
        modal:exit()
        pcall(function() webview:delete() end)
    end)
    modal:enter()

    return webview
end

function M.show_text_prompt(title, prompt_text, callback, default_text)
    -- Unlike hs.dialog.alert, textPrompt is synchronous and returns the
    -- pressed button plus the entered text. Passing a callback (and x/y
    -- coordinates) makes Hammerspoon reject the call before a prompt appears.
    local ok, result, input = pcall(
        hs.dialog.textPrompt,
        title,
        prompt_text,
        default_text or "",
        "OK",
        "Cancel",
        false
    )

    if not ok then
        M.show_error("Could not open the additional-input dialog")
        return
    end

    if result == "Cancel" then
        callback(nil, nil)
        return
    end

    if input and input ~= "" then
        callback(result, input)
    end
end

function M.get_focused_element()
    return hs.uielement.focusedElement()
end

function M.check_accessibility_permission()
    local elem = hs.uielement.focusedElement()
    if not elem then
        M.show_error(constants.NOTIFICATIONS.PERMISSION_DENIED .. ". Enable it in System Settings > Privacy & Security > Accessibility.")
        return false
    end
    return true
end

return M
