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
        assert.are_equal("https://openrouter.ai/api/v1/chat/completions",
            constants.DEFAULT_API_CONFIG.endpoint)
        assert.are_equal("openai/gpt-4.1-mini", constants.DEFAULT_API_CONFIG.model)
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

    it("should build an OpenAI-compatible request", function()
        local api = require("trumpify.api")
        local payload = api.build_payload("openai/gpt-4.1-mini", 1234, "Hello", "Rewrite it.")
        assert.are_equal("openai/gpt-4.1-mini", payload.model)
        assert.are_equal(1234, payload.max_tokens)
        assert.are_equal("system", payload.messages[1].role)
        assert.truthy(payload.messages[1].content:find("Rewrite it.", 1, true))
        assert.are_equal("user", payload.messages[2].role)
        assert.are_equal("Hello", payload.messages[2].content)
        assert.is_nil(payload.max_completion_tokens)
    end)

    it("should use the current token-limit field for GPT-5 models", function()
        local api = require("trumpify.api")
        local payload = api.build_payload("gpt-5.6-luna", 2048, "Hello", "Rewrite it.")
        assert.are_equal(2048, payload.max_completion_tokens)
        assert.is_nil(payload.max_tokens)
    end)

    it("should use bearer authentication for OpenAI-compatible endpoints", function()
        local api = require("trumpify.api")
        local headers = api.build_headers("test-key", "https://openrouter.ai/api/v1/chat/completions")
        assert.are_equal("Bearer test-key", headers.Authorization)
        assert.are_equal("Trumpify", headers["X-Title"])
        assert.is_nil(headers["x-api-key"])
    end)

    it("should parse OpenAI-compatible responses", function()
        local api = require("trumpify.api")
        local result, err = api.extract_response({
            choices = { { message = { content = "  Rewritten text  " } } },
        })
        assert.is_nil(err)
        assert.are_equal("Rewritten text", result)
    end)

    it("should surface API errors", function()
        local api = require("trumpify.api")
        local result, err = api.extract_response({ error = { message = "Model unavailable" } })
        assert.is_nil(result)
        assert.are_equal("Model unavailable", err)
    end)

    it("should retry only temporary failures", function()
        local api = require("trumpify.api")
        assert.is_true(api.is_retryable_status(-1))
        assert.is_true(api.is_retryable_status(429))
        assert.is_true(api.is_retryable_status(503))
        assert.is_false(api.is_retryable_status(400))
        assert.is_false(api.is_retryable_status(401))
    end)

    it("should calculate bounded exponential backoff and honor Retry-After", function()
        local api = require("trumpify.api")
        assert.are_equal(1, api.retry_delay(0, nil, 0))
        assert.are_equal(5, api.retry_delay(1, { ["Retry-After"] = "5" }, 0))
        assert.are_equal(30, api.retry_delay(9, nil, 1))
    end)

    it("should describe retryable failures for the user", function()
        local api = require("trumpify.api")
        assert.are_equal("LLM connection issue", api.retry_reason(-1))
        assert.are_equal("LLM request timed out", api.retry_reason(408))
        assert.are_equal("LLM rate limit reached", api.retry_reason(429))
        assert.are_equal("LLM service temporarily unavailable", api.retry_reason(503))
    end)

    it("should explicitly define Trumpify as a Donald Trump parody", function()
        local external = assert(loadfile("prompts/trumpify.lua"))()
        local embedded = require("trumpify.prompts").modes.trumpify

        for _, mode in ipairs({ external, embedded }) do
            assert.truthy(mode.system:find("Donald Trump", 1, true))
            assert.truthy(mode.system:find("satirical parody", 1, true))
            assert.truthy(mode.description:find("Donald Trump", 1, true))
        end
    end)
end)
