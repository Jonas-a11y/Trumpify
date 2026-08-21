-- Basic test to verify Lua environment works for testing
-- Run with: busted .

describe("Trumpify self-test", function()
    it("should load the constants module", function()
        local ok, constants = pcall(require, "trumpify.constants")
        assert.is_true(ok)
        assert.is_not_nil(constants.MODIFIERS)
        assert.is_not_nil(constants.ALERT_STYLE)
        assert.is_not_nil(constants.get_project_dir)
    end)

    it("should have valid API defaults", function()
        local ok, constants = pcall(require, "trumpify.constants")
        assert.is_true(ok)
        assert.are_equal(4096, constants.DEFAULT_API_CONFIG.maxTokens)
        assert.is_string(constants.DEFAULT_API_CONFIG.endpoint)
        assert.is_string(constants.DEFAULT_API_CONFIG.model)
    end)

    it("should have notification constants", function()
        local ok, constants = pcall(require, "trumpify.constants")
        assert.is_true(ok)
        assert.are_equal("No text selected", constants.NOTIFICATIONS.NO_TEXT_SELECTED)
        assert.are_equal("Trumpify loaded!", constants.NOTIFICATIONS.LOADED)
    end)

    it("should sanitize text correctly", function()
        local ok, api = pcall(require, "trumpify.api")
        if ok then
            local result = api.sanitize("Hello\nWorld\tTest")
            assert.is_string(result)
            assert.are_equal("Hello\nWorld\tTest", result)

            local with_nulls = "Hello\0World"
            local sanitized = api.sanitize(with_nulls)
            assert.are_equal("HelloWorld", sanitized)
        end
    end)
end)
