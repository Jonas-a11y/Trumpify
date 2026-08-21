-- Tests for the history ring buffer and hotkey key resolution
-- Run with: busted .

describe("history", function()
    local history

    before_each(function()
        local ok, mod = pcall(require, "trumpify.history")
        if not ok then pending("history not loadable") end
        history = mod
        history.clear()
    end)

    it("starts empty", function()
        assert.are_equal(0, #history.get_all())
        assert.is_nil(history.get_latest())
    end)

    it("adds entries with mode, input, output and timestamp", function()
        history.add("Summary", "input text", "output text")
        local latest = history.get_latest()
        assert.is_not_nil(latest)
        assert.are_equal("Summary", latest.mode)
        assert.are_equal("input text", latest.input)
        assert.are_equal("output text", latest.output)
        assert.is_number(latest.timestamp)
    end)

    it("returns newest entry first", function()
        history.add("First", "a", "b")
        history.add("Second", "c", "d")
        assert.are_equal("Second", history.get_latest().mode)
        assert.are_equal("First", history.get_all()[2].mode)
    end)

    it("evicts the oldest entry beyond the limit", function()
        for i = 1, 8 do
            history.add("Mode" .. i, "in", "out")
        end
        local all = history.get_all()
        assert.are_equal(5, #all)
        -- newest five kept: Mode8..Mode4
        assert.are_equal("Mode8", all[1].mode)
        assert.are_equal("Mode4", all[5].mode)
    end)

    it("clear() empties the buffer", function()
        history.add("X", "a", "b")
        history.clear()
        assert.are_equal(0, #history.get_all())
    end)

    it("get_summary builds display entries with preview", function()
        history.add("Email", "in", string.rep("x", 100))
        local summary = history.get_summary()
        assert.are_equal(1, #summary)
        assert.truthy(summary[1].text:find("Email"))
        -- preview is truncated to 80 chars + ellipsis
        assert.truthy(summary[1].subText:find("%.%.%."))
    end)
end)

describe("hotkeys key resolution", function()
    local hotkeys, config

    before_each(function()
        local ok_h, h = pcall(require, "trumpify.hotkeys")
        local ok_c, c = pcall(require, "trumpify.config")
        if not ok_h or not ok_c then pending("modules not loadable") end
        hotkeys, config = h, c
        config.init()
    end)

    it("uses the keymap override when present", function()
        config.set("keymap", { summarize = "z" })
        local key = hotkeys._get_key_for_mode("summarize", { key = "s" })
        assert.are_equal("z", key)
    end)

    it("falls back to the mode default without override", function()
        config.set("keymap", {})
        local key = hotkeys._get_key_for_mode("summarize", { key = "s" })
        assert.are_equal("s", key)
    end)

    it("normalizes uppercase overrides to lowercase", function()
        config.set("keymap", { summarize = "Z" })
        local key = hotkeys._get_key_for_mode("summarize", { key = "s" })
        assert.are_equal("z", key)
    end)

    it("exposes reserved keys including stop_tts", function()
        local reserved = hotkeys.get_reserved_keys()
        assert.are_equal("stop_tts", reserved["."])
        assert.are_equal("reload", reserved["r"])
        assert.are_equal("chooser", reserved["space"])
    end)
end)
