-- Tests for the settings panel integration
-- Run with: busted .

describe("settings integration", function()
    describe("keymap validation", function()
        local panel
        before_each(function()
            local ok, mod = pcall(require, "trumpify.settings_panel")
            if not ok then pending("settings_panel not loadable outside Hammerspoon") end
            panel = mod
        end)

        it("accepts unique valid keys", function()
            local modes = {
                { id = "alpha", key = "a" },
                { id = "beta", key = "b" },
            }
            local errors = panel.validate_keymap(modes, { alpha = "x", beta = "y" }, {})
            assert.are_equal(0, #errors)
        end)

        it("rejects collisions between modes", function()
            local modes = {
                { id = "alpha", key = "a" },
                { id = "beta", key = "b" },
            }
            local errors = panel.validate_keymap(modes, { alpha = "x", beta = "x" }, {})
            assert.are_equal(1, #errors)
        end)

        it("is case-insensitive when detecting collisions", function()
            local modes = {
                { id = "alpha", key = "a" },
                { id = "beta", key = "b" },
            }
            local errors = panel.validate_keymap(modes, { alpha = "A", beta = "a" }, {})
            assert.are_equal(1, #errors)
        end)

        it("rejects reserved keys", function()
            local modes = { { id = "alpha", key = "a" } }
            local errors = panel.validate_keymap(modes, { alpha = "r" }, { r = "reload" })
            assert.are_equal(1, #errors)
        end)

        it("rejects multi-character keys", function()
            local modes = { { id = "alpha", key = "a" } }
            local errors = panel.validate_keymap(modes, { alpha = "xy" }, {})
            assert.are_equal(1, #errors)
        end)

        it("allows empty keys (fall back to defaults)", function()
            local modes = { { id = "alpha", key = "a" } }
            local errors = panel.validate_keymap(modes, { alpha = "" }, {})
            assert.are_equal(0, #errors)
        end)
    end)

    describe("config save", function()
        local config
        before_each(function()
            local ok, mod = pcall(require, "trumpify.config")
            if not ok then pending("config not loadable") end
            config = mod
            config.init()
        end)

        it("writes managed keys and preserves unmanaged ones", function()
            local tmp = os.tmpname()
            local f = io.open(tmp, "w")
            f:write('{"_comment":"keep me","apiKey":"secret-key","endpoint":"http://localhost:1234"}')
            f:close()

            config.set("tts", { voice = nil, rate = "+10%", volume = "+0%", pitch = "+0Hz", fallback = false })
            config.set("disabledModes", { "email" })

            local ok, err = config.save_to(tmp)
            assert.is_true(ok)
            if not ok then print(err) end

            local fh = io.open(tmp, "r")
            local saved = fh:read("*a")
            fh:close()

            -- unmanaged keys preserved
            assert.truthy(saved:find("secret%-key"))
            if hs then
                -- comment preservation requires hs.json; the pure-Lua fallback
                -- parser strips _comment keys
                assert.truthy(saved:find("keep me", 1, true))
            end
            -- managed keys written
            assert.truthy(saved:find('"rate":"+10%"', 1, true))
            assert.truthy(saved:find('"email"', 1, true))
            -- fallback=false must be explicit (not dropped as null)
            assert.truthy(saved:find('"fallback":false', 1, true))

            os.remove(tmp)
        end)

        it("round-trips through set/get", function()
            config.set("tts", { rate = "-25%" })
            local tts_cfg = config.get("tts")
            assert.are_equal("-25%", tts_cfg.rate)
        end)
    end)

    describe("disabled modes", function()
        local config, prompt_loader
        before_each(function()
            local ok_c, c = pcall(require, "trumpify.config")
            local ok_p, p = pcall(require, "trumpify.prompt_loader")
            if not ok_c or not ok_p then pending("modules not loadable") end
            config, prompt_loader = c, p
            config.init()
            prompt_loader.init()
        end)

        after_each(function()
            config.set("disabledModes", {})
        end)

        it("hides disabled modes from get_modes but keeps them in get_all_modes", function()
            local all = prompt_loader.get_all_modes()
            assert.is_not_nil(all["email"])

            config.set("disabledModes", { "email" })

            local filtered = prompt_loader.get_modes()
            assert.is_nil(filtered["email"])
            assert.is_not_nil(filtered["summarize"])
            assert.is_not_nil(prompt_loader.get_all_modes()["email"])
        end)

        it("shows all modes again after clearing the list", function()
            config.set("disabledModes", { "email" })
            config.set("disabledModes", {})
            assert.is_not_nil(prompt_loader.get_modes()["email"])
        end)

        it("chooser choices reflect keymap overrides in the hint", function()
            config.set("keymap", { summarize = "z" })
            local choices = prompt_loader.get_chooser_choices()
            local found = false
            for _, choice in ipairs(choices) do
                if choice.modeKey == "summarize" then
                    found = true
                    assert.truthy(choice.subText:find("⌃⌥Z"))
                end
            end
            assert.is_true(found)
            config.set("keymap", {})
        end)
    end)

    describe("language detection", function()
        local tts
        before_each(function()
            local ok, mod = pcall(require, "trumpify.tts")
            if not ok then pending("tts not loadable") end
            tts = mod
        end)

        it("detects German text", function()
            assert.are_equal("de", tts.detect_language(
                "Der schnelle Fuchs springt über den Zaun und die Hunde bellen nicht mehr."))
        end)

        it("detects English text", function()
            assert.are_equal("en", tts.detect_language(
                "The quick brown fox jumps over the lazy dog and nothing else matters."))
        end)

        it("falls back to English for empty or neutral text", function()
            assert.are_equal("en", tts.detect_language(""))
            assert.are_equal("en", tts.detect_language("12345 67890"))
        end)
    end)

    describe("chunking", function()
        local tts
        before_each(function()
            local ok, mod = pcall(require, "trumpify.tts")
            if not ok then pending("tts not loadable") end
            tts = mod
        end)

        it("returns a single chunk for short text", function()
            local chunks = tts.chunk_text("Hello world", 100)
            assert.are_equal(1, #chunks)
            assert.are_equal("Hello world", chunks[1])
        end)

        it("splits long text at sentence boundaries", function()
            local sentence = "This is a test sentence. "
            local text = sentence:rep(200) -- ~5000 chars
            local chunks = tts.chunk_text(text, 500)
            assert.is_true(#chunks > 1)
            -- reassembling must preserve the full text
            local joined = table.concat(chunks, "")
            assert.are_equal(#text, #joined)
            -- no chunk exceeds the limit
            for _, c in ipairs(chunks) do
                assert.is_true(#c <= 500)
            end
        end)

        it("handles empty input", function()
            assert.are_equal(0, #tts.chunk_text(""))
            assert.are_equal(0, #tts.chunk_text(nil))
        end)
    end)
end)
