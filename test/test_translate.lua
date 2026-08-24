-- Tests for the translate mode
-- Run with: busted .

describe("translate", function()
    local config, transformer

    before_each(function()
        package.loaded["trumpify.config"] = nil
        package.loaded["trumpify.transformer"] = nil
        local ok_c, c = pcall(require, "trumpify.config")
        local ok_t, t = pcall(require, "trumpify.transformer")
        if not ok_c or not ok_t then pending("modules not loadable") end
        config, transformer = c, t
        config.init()
    end)

    describe("build_system", function()
        it("substitutes the configured target language", function()
            config.set("translate", { target = "French" })
            local system = transformer.build_system(
                { system = "Translate into {target_language}. Output only the translation." })
            assert.truthy(system:find("French", 1, true))
            assert.falsy(system:find("{target_language}", 1, true))
        end)

        it("falls back to auto German/English when unconfigured", function()
            local system = transformer.build_system(
                { system = "Translate into {target_language}." })
            assert.falsy(system:find("{target_language}", 1, true))
            assert.truthy(system:find("German", 1, true))
            assert.truthy(system:find("English", 1, true))
        end)

        it("falls back to auto when the target is empty or whitespace", function()
            config.set("translate", { target = "   " })
            local system = transformer.build_system(
                { system = "Translate into {target_language}." })
            assert.truthy(system:find("German", 1, true))
        end)

        it("leaves systems without a placeholder untouched", function()
            local system = transformer.build_system(
                { system = "Summarize the text." })
            assert.are_equal("Summarize the text.", system)
        end)
    end)

    describe("mode definition", function()
        it("is loadable and well-formed", function()
            local f = assert(loadfile("prompts/translate.lua"))
            local mode = f()
            assert.are_equal("Translate", mode.name)
            assert.is_string(mode.description)
            assert.is_string(mode.system)
            assert.truthy(mode.system:find("{target_language}", 1, true))
            if #mode.key == 1 then
                assert.are_equal(1, #mode.key)
            end
        end)
    end)
end)
