-- Tests for visible retry progress without making real HTTP requests.
-- Run with: busted .

describe("API retry notifications", function()
    local original_hs
    local original_api
    local original_config
    local response_status
    local scheduled

    before_each(function()
        original_hs = _G.hs
        original_api = package.loaded["trumpify.api"]
        original_config = package.loaded["trumpify.config"]
        response_status = 429
        scheduled = nil

        package.loaded["trumpify.api"] = nil
        package.loaded["trumpify.config"] = {
            get = function(key)
                if key == "apiKey" then return "test-key" end
                if key == "endpoint" then return "https://example.test/v1/chat/completions" end
                if key == "model" then return "test-model" end
                if key == "maxTokens" then return 100 end
                return nil
            end,
        }

        _G.hs = {
            json = {
                encode = function() return "{}" end,
            },
            http = {
                asyncPost = function(_, _, _, callback)
                    callback(response_status, "{}", { ["Retry-After"] = "3" })
                end,
            },
            timer = {
                doAfter = function(delay, callback)
                    scheduled = { delay = delay, callback = callback }
                end,
            },
        }
    end)

    after_each(function()
        _G.hs = original_hs
        package.loaded["trumpify.api"] = original_api
        package.loaded["trumpify.config"] = original_config
    end)

    it("reports the reason, delay and next attempt before scheduling a retry", function()
        local api = require("trumpify.api")
        local retry = nil
        local completed = false

        api.transform("Text", "System", function()
            completed = true
        end, function(info)
            retry = info
        end)

        assert.is_false(completed)
        assert.are_equal("LLM rate limit reached", retry.reason)
        assert.are_equal(3, retry.delay)
        assert.are_equal(429, retry.status)
        assert.are_equal(2, retry.attempt)
        assert.are_equal(5, retry.total)
        assert.are_equal(3, scheduled.delay)
        assert.is_function(scheduled.callback)
    end)

    it("returns a useful final error after all retries are exhausted", function()
        response_status = 503
        local api = require("trumpify.api")
        local final = nil
        local retry_called = false

        api.transform("Text", "System", function(success, message)
            final = { success = success, message = message }
        end, 4, function()
            retry_called = true
        end)

        assert.is_false(retry_called)
        assert.is_false(final.success)
        assert.truthy(final.message:find("LLM service temporarily unavailable", 1, true))
        assert.truthy(final.message:find("HTTP 503", 1, true))
    end)
end)
