describe("creative controls", function()
    local config, creative, original_creative
    before_each(function()
        original_creative = package.loaded["trumpify.creative"]
        package.loaded["trumpify.creative"] = nil
        config = require("trumpify.config")
        config.init()
        config.set("creative", nil)
        creative = require("trumpify.creative")
    end)
    after_each(function()
        config.set("creative", nil)
        package.loaded["trumpify.creative"] = original_creative
    end)

    it("applies the chosen Trumpify intensity and length", function()
        config.set("creative", { intensity = "subtle", length = "short" })
        local system = creative.build_system(assert(loadfile("prompts/trumpify.lua"))())
        assert.truthy(system:find("restrained parody", 1, true))
        assert.truthy(system:find("at most three sentences", 1, true))
    end)

    it("chooses a surprise form and applies the selected constraints", function()
        config.set("creative", { maxSentences = 2, officeSafe = true, preserveFacts = true })
        local mode = assert(loadfile("prompts/surprise.lua"))()
        local system = creative.build_system(mode)
        assert.truthy(system:find("Chosen form:", 1, true))
        assert.truthy(system:find("at most 2 sentences", 1, true))
        assert.truthy(system:find("suitable for work", 1, true))
        assert.truthy(system:find("Preserve all names", 1, true))
        config.set("creative", { officeSafe = false, preserveFacts = false })
        system = creative.build_system(mode)
        assert.falsy(system:find("suitable for work", 1, true))
        assert.falsy(system:find("Preserve all names", 1, true))
    end)

    it("rejects invalid style choices and non-integer sentence limits", function()
        local settings = creative.settings()
        settings.intensity = "unknown"
        assert.is_false(creative.validate(settings))
        settings.intensity = "subtle"
        settings.maxSentences = 2.5
        assert.is_false(creative.validate(settings))
        settings.maxSentences = 4
        assert.is_true(creative.validate(settings))
    end)
end)
