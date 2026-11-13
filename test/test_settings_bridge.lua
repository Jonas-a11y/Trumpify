describe("settings connection feedback", function()
    it("tests draft settings and sends string feedback through the Hammerspoon bridge", function()
        local saved_hs = _G.hs
        local names = { "settings_panel", "config", "prompt_loader", "hotkeys", "tts", "custom_modes", "creative" }
        local saved = {}
        for _, name in ipairs(names) do saved[name] = package.loaded["trumpify." .. name] end
        local values = { apiKey = "stored-key", model = "active-model" }
        package.loaded["trumpify.settings_panel"] = nil
        package.loaded["trumpify.config"] = { get = function(key) return values[key] end }
        package.loaded["trumpify.creative"] = nil
        package.loaded["trumpify.prompt_loader"] = { get_all_modes = function() return {} end }
        package.loaded["trumpify.hotkeys"] = { get_reserved_keys = function() return {} end }
        package.loaded["trumpify.tts"] = {}
        package.loaded["trumpify.custom_modes"] = { load = function() return {} end }
        local json = require("dkjson")
        local callback, sent_js, request_body
        local view = {}
        for _, method in ipairs({ "windowStyle", "windowTitle", "allowTextEntry", "html", "show", "bringToFront" }) do
            view[method] = function() return view end
        end
        view.evaluateJavaScript = function(_, js) sent_js = js end
        local controller = { setCallback = function(_, fn) callback = fn end }
        _G.hs = {
            json = {
                encode = function(value)
                    -- Native hs.json cannot encode a top-level string.
                    assert.is_table(value)
                    return json.encode(value)
                end,
                decode = json.decode,
            },
            screen = { mainScreen = function() return { frame = function() return { x = 0, y = 0, w = 1280, h = 720 } end } end },
            webview = { usercontent = { new = function() return controller end }, new = function() return view end },
            hotkey = { modal = { new = function() return { bind = function() end, enter = function() end } end } },
            task = { new = function() return nil end },
            http = { asyncPost = function(endpoint, body, headers, fn)
                assert.are_equal("http://localhost:1234/v1/chat/completions", endpoint)
                assert.are_equal("Bearer draft-key", headers.Authorization)
                request_body = json.decode(body)
                fn(200, json.encode({ model = "gpt-6-luna-2026-09-22",
                    choices = { { message = { content = "OK" } } } }), {})
            end },
        }
        local ok, err = pcall(function()
            require("trumpify.settings_panel").show()
            callback({ body = json.encode({ action = "testConnection", payload = {
                endpoint = "http://localhost:1234/v1/chat/completions", apiKey = "draft-key",
                model = "gpt-6-luna", maxTokens = 128, reasoningEffort = "low",
            } }) })
            assert.truthy(sent_js:find("Connected", 1, true))
            assert.truthy(sent_js:find("gpt-6-luna-2026-09-22", 1, true))
            assert.are_equal("low", request_body.reasoning_effort)
            assert.are_equal("active-model", values.model)
        end)
        _G.hs = saved_hs
        for _, name in ipairs(names) do package.loaded["trumpify." .. name] = saved[name] end
        if not ok then error(err) end
    end)
end)
