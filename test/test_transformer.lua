describe("transformation lifecycle", function()
    local originals, transformer, requests, pasted, copied, entries, spoken
    local modules = { "transformer", "api", "ui", "selection", "history", "tts", "creative" }

    before_each(function()
        originals = {}
        for _, name in ipairs(modules) do
            originals[name] = package.loaded["trumpify." .. name]
            package.loaded["trumpify." .. name] = nil
        end
        requests, pasted, copied, entries, spoken = {}, {}, {}, {}, {}
        package.loaded["trumpify.api"] = { transform = function(text, system, callback)
            local request = { text = text, system = system, complete = callback, cancelled = false }
            request.cancel = function() request.cancelled = true end
            table.insert(requests, request)
            return request
        end }
        package.loaded["trumpify.ui"] = { show_processing = function() return "alert" end,
            close_processing = function() end, show_notification = function() end,
            show_clipboard_success = function() end, show_success = function() end,
            show_error = function(message) error(message) end }
        package.loaded["trumpify.selection"] = {
            paste_text = function(text) table.insert(pasted, text) end,
            copy_to_clipboard = function(text) table.insert(copied, text) end,
        }
        package.loaded["trumpify.history"] = {
            add = function(name, input, output, details)
                table.insert(entries, { mode = name, input = input, output = output,
                    system = details.system, mode_definition = details.mode })
            end,
            get_latest = function() return entries[#entries] end,
        }
        package.loaded["trumpify.tts"] = { speak = function(text) table.insert(spoken, text) end }
        package.loaded["trumpify.creative"] = { build_system = function(mode) return mode.system end }
        transformer = require("trumpify.transformer")
        transformer.init()
    end)

    after_each(function()
        for _, name in ipairs(modules) do package.loaded["trumpify." .. name] = originals[name] end
    end)

    it("does not submit duplicate Surprise shortcuts with randomly chosen forms", function()
        local forms = { "Chosen form: a haiku", "Chosen form: a sports commentary" }
        package.loaded["trumpify.creative"].build_system = function() return table.remove(forms, 1) end
        local mode = assert(loadfile("prompts/surprise.lua"))()
        transformer.execute_transform(mode, "Input", false)
        transformer.execute_transform(mode, "Input", false)
        assert.are_equal(1, #requests)
        requests[1].complete(true, "Output")
        assert.same({ "Output" }, pasted)
    end)

    it("only applies the newest request's result", function()
        local mode = { name = "Email", system = "Rewrite", paste_back = true }
        transformer.execute_transform(mode, "First", false)
        transformer.execute_transform(mode, "Second", false)
        assert.is_true(requests[1].cancelled)
        requests[2].complete(true, "Current result")
        requests[1].complete(true, "Obsolete result")
        assert.same({ "Current result" }, pasted)
        assert.are_equal(1, #entries)
    end)

    it("does not paste or record a cancelled transformation", function()
        transformer.execute_transform({ name = "Email", system = "Rewrite", paste_back = true }, "Input", false)
        assert.is_true(transformer.cancel(true))
        requests[1].complete(true, "Late result")
        assert.same({}, pasted)
        assert.same({}, entries)
    end)

    it("replaces the selection with a dialogue without speaking", function()
        transformer.execute_transform(assert(loadfile("prompts/dialog.lua"))(), "Input", false)
        requests[1].complete(true, "Moderator: Hello!\nExpert: Really?")
        assert.same({ "Moderator: Hello!\nExpert: Really?" }, pasted)
        assert.same({}, spoken)
    end)

    it("reuses the saved prompt and returns a history entry when rewriting", function()
        local updated
        transformer.execute_transform({ name = "Surprise", system = "Different prompt" }, "Original", true,
            "Saved form and constraints", function(entry) updated = entry end)
        assert.are_equal("Saved form and constraints", requests[1].system)
        requests[1].complete(true, "New variation")
        assert.same({ "New variation" }, copied)
        assert.are_equal("Original", updated.input)
        assert.are_equal("Saved form and constraints", updated.system)
    end)

    it("supersedes a history rewrite when the chosen saved prompt differs", function()
        local mode = { name = "Surprise", system = "Choose a form" }
        transformer.execute_transform(mode, "Original", true, "Chosen form: a haiku")
        transformer.execute_transform(mode, "Original", true, "Chosen form: a sports commentary")
        assert.are_equal(2, #requests)
        assert.is_true(requests[1].cancelled)
        requests[2].complete(true, "Sports result")
        requests[1].complete(true, "Haiku result")
        assert.same({ "Sports result" }, copied)
        assert.are_equal(1, #entries)
        assert.are_equal("Chosen form: a sports commentary", entries[1].system)
    end)
end)
