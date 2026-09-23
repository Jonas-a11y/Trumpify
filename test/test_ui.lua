-- Tests for UI helpers whose Hammerspoon APIs can be stubbed.
-- Run with: busted .

describe("text prompt", function()
    local original_hs

    before_each(function()
        original_hs = _G.hs
        package.loaded["trumpify.ui"] = nil
    end)

    after_each(function()
        _G.hs = original_hs
        package.loaded["trumpify.ui"] = nil
    end)

    it("uses the synchronous Hammerspoon API and forwards the result", function()
        local received = nil
        local call = nil
        _G.hs = {
            dialog = {
                textPrompt = function(...)
                    call = { n = select("#", ...), ... }
                    return "OK", "Use these talking points"
                end,
            },
        }

        local ui = require("trumpify.ui")
        ui.show_text_prompt("Reply (guided)", "What would you like to say?", function(result, input)
            received = { result = result, input = input }
        end)

        assert.are_equal(6, call.n)
        assert.are_equal("Reply (guided)", call[1])
        assert.are_equal("What would you like to say?", call[2])
        assert.are_equal("", call[3])
        assert.are_equal("OK", call[4])
        assert.are_equal("Cancel", call[5])
        assert.is_false(call[6])
        assert.are_equal("OK", received.result)
        assert.are_equal("Use these talking points", received.input)
    end)

    it("passes the default text and treats Cancel as no input", function()
        local received = false
        _G.hs = {
            dialog = {
                textPrompt = function(_, _, default_text)
                    assert.are_equal("Existing notes", default_text)
                    return "Cancel", "Existing notes"
                end,
            },
        }

        local ui = require("trumpify.ui")
        ui.show_text_prompt("Title", "Prompt", function(result, input)
            received = { result = result, input = input }
        end, "Existing notes")

        assert.is_nil(received.result)
        assert.is_nil(received.input)
    end)

    it("shows an error instead of failing silently when the dialog cannot open", function()
        local shown_error = nil
        _G.hs = {
            dialog = {
                textPrompt = function()
                    error("invalid arguments")
                end,
            },
            alert = {
                show = function(message)
                    shown_error = message
                end,
            },
        }

        local ui = require("trumpify.ui")
        ui.show_text_prompt("Title", "Prompt", function() end)

        assert.truthy(shown_error:find("Could not open the additional%-input dialog"))
    end)

    it("shows retry reason, rounded delay and attempt progress", function()
        local alert_message = nil
        _G.hs = {
            alert = {
                show = function(message)
                    alert_message = message
                    return "alert-id"
                end,
            },
        }

        local ui = require("trumpify.ui")
        local alert_id = ui.show_retry("Reply (guided)", {
            reason = "LLM rate limit reached",
            delay = 2.2,
            attempt = 3,
            total = 5,
        })

        assert.are_equal("alert-id", alert_id)
        assert.truthy(alert_message:find("LLM rate limit reached", 1, true))
        assert.truthy(alert_message:find("Retrying in 3s", 1, true))
        assert.truthy(alert_message:find("attempt 3/5", 1, true))
    end)

    it("shows short summaries through the foreground webview", function()
        _G.hs = {}
        local ui = require("trumpify.ui")
        local shown = nil
        ui.show_scrollable_text = function(title, text)
            shown = { title = title, text = text }
            return "webview"
        end

        local result = ui.show_summary_dialog("A short summary")

        assert.are_equal("webview", result)
        assert.are_equal("Summary", shown.title)
        assert.are_equal("A short summary", shown.text)
    end)
end)
