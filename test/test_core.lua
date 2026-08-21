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
        assert.are_equal("history", reserved["h"])
    end)
end)

describe("history browser", function()
    local hb

    before_each(function()
        local ok, mod = pcall(require, "trumpify.history_browser")
        if not ok then pending("history_browser not loadable") end
        hb = mod
    end)

    it("builds one choice per entry with index back-reference", function()
        local entries = {
            { mode = "Summary", output = "short result", timestamp = 1700000000 },
            { mode = "Email",   output = "email result", timestamp = 1700000100 },
        }
        local choices = hb.build_choices(entries)
        assert.are_equal(2, #choices)
        assert.are_equal(1, choices[1].idx)
        assert.are_equal(2, choices[2].idx)
        assert.truthy(choices[1].text:find("Summary"))
        assert.truthy(choices[2].text:find("Email"))
    end)

    it("truncates long previews and strips newlines", function()
        local entries = {
            { mode = "X", output = string.rep("a", 200) .. "\nsecond line", timestamp = 0 },
        }
        local choices = hb.build_choices(entries)
        assert.is_true(#choices[1].subText <= 130)
        assert.falsy(choices[1].subText:find("\n"))
        assert.truthy(choices[1].subText:find("%.%.%."))
    end)

    it("handles empty or nil input", function()
        assert.are_equal(0, #hb.build_choices({}))
        assert.are_equal(0, #hb.build_choices(nil))
    end)
end)
