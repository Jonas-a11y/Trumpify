-- Tests for API requests and visible retry progress without real HTTP requests.
-- Run with: busted .

describe("API requests and retry notifications", function()
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
                    scheduled = { delay = delay, callback = callback, stopped = false,
                        stop = function(self) self.stopped = true end }
                    return scheduled
                end,
            },
        }
    end)

    after_each(function()
        _G.hs = original_hs
        package.loaded["trumpify.api"] = original_api
        package.loaded["trumpify.config"] = original_config
    end)

    it("sends GPT-6 Luna with the configured reasoning effort", function()
        local values = { apiKey = "test-key", model = "gpt-6-luna",
            endpoint = "http://localhost:1234/v1/chat/completions",
            maxTokens = 4096, reasoningEffort = "low" }
        package.loaded["trumpify.config"].get = function(key) return values[key] end
        local payload
        hs.json.encode = function(value)
            payload = value
            return "request-body"
        end
        hs.http.asyncPost = function(endpoint, body)
            assert.are_equal(values.endpoint, endpoint)
            assert.are_equal("request-body", body)
        end

        require("trumpify.api").transform("Text", "System", function() end)

        assert.are_equal("gpt-6-luna", payload.model)
        assert.are_equal("low", payload.reasoning_effort)
        assert.are_equal(4096, payload.max_completion_tokens)
        assert.is_nil(payload.max_tokens)
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
        end, function()
            retry_called = true
        end)
        for _ = 1, 4 do scheduled.callback() end

        assert.is_true(retry_called)
        assert.is_false(final.success)
        assert.truthy(final.message:find("LLM service temporarily unavailable", 1, true))
        assert.truthy(final.message:find("HTTP 503", 1, true))
    end)

    it("stops retries and ignores responses after cancellation", function()
        local completed = false
        local request = require("trumpify.api").transform("Text", "System", function() completed = true end)
        local retry = scheduled
        request.cancel()
        assert.is_true(retry.stopped)
        response_status = 401
        retry.callback()
        assert.is_false(completed)

        local response_callback
        hs.http.asyncPost = function(_, _, _, callback) response_callback = callback end
        request = require("trumpify.api").transform("Other", "System", function() completed = true end)
        request.cancel()
        response_callback(401, "{}", {})
        assert.is_false(completed)
    end)

    it("tests draft settings without changing the active configuration", function()
        local sent
        hs.json.encode = function(payload) sent = payload; return "{}" end
        hs.http.asyncPost = function(endpoint, _, headers)
            assert.are_equal("http://localhost:1234/v1/chat/completions", endpoint)
            assert.are_equal("Bearer draft-key", headers.Authorization)
        end
        require("trumpify.api").transform("Test", "System", function() end, nil, {
            endpoint = "http://localhost:1234/v1/chat/completions", apiKey = "draft-key",
            model = "gpt-6-luna", maxTokens = 128, reasoningEffort = "low",
        })
        assert.are_equal("gpt-6-luna", sent.model)
        assert.are_equal("low", sent.reasoning_effort)
        assert.are_equal("test-model", package.loaded["trumpify.config"].get("model"))
    end)
end)
