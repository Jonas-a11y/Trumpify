local constants = require("trumpify.constants")
local config = require("trumpify.config")

local M = {}

local GLOBAL_SYSTEM_INSTRUCTION = [[Global style rule: do not use em dashes in the output. Use commas, semicolons, parentheses, or a normal hyphen-minus (-) if needed.]]

function M.sanitize(text)
    local sanitized = text:gsub("%z", "")

    sanitized = sanitized:gsub("[%c]", function(c)
        if c == "\n" or c == "\t" or c == "\r" then
            return c
        end
        return ""
    end)

    if #sanitized > constants.MAX_TEXT_LENGTH then
        sanitized = sanitized:sub(1, constants.MAX_TEXT_LENGTH)
    end

    return sanitized
end

function M.transform(text, system_prompt, callback, retry_count)
    local api_key = config.get("apiKey")
    if not api_key then
        callback(false, constants.NOTIFICATIONS.API_KEY_MISSING)
        return
    end

    local sanitized_text = M.sanitize(text)
    local endpoint = config.get("endpoint") or constants.DEFAULT_API_CONFIG.endpoint
    local model = config.get("model") or constants.DEFAULT_API_CONFIG.model
    local max_tokens = config.get("maxTokens") or constants.DEFAULT_API_CONFIG.maxTokens

    local body = hs.json.encode({
        model = model,
        max_tokens = max_tokens,
        system = GLOBAL_SYSTEM_INSTRUCTION .. "\n\n" .. system_prompt,
        messages = { { role = "user", content = sanitized_text } },
    })

    local headers = {
        ["Content-Type"] = "application/json",
        ["x-api-key"] = api_key,
        ["anthropic-version"] = "2023-06-01",
    }

    retry_count = retry_count or 0
    local max_retries = 2

    hs.http.asyncPost(endpoint, body, headers, function(status, response_body)
        if status < 0 then
            if retry_count < max_retries then
                hs.timer.doAfter(1, function()
                    M.transform(text, system_prompt, callback, retry_count + 1)
                end)
                return
            end
            callback(false, constants.NOTIFICATIONS.NETWORK_ERROR)
            return
        end

        if status == 401 then
            callback(false, constants.NOTIFICATIONS.INVALID_API_KEY)
            return
        end

        if status == 429 then
            if retry_count < max_retries then
                local delay = 2 ^ (retry_count + 1)
                hs.timer.doAfter(delay, function()
                    M.transform(text, system_prompt, callback, retry_count + 1)
                end)
                return
            end
            callback(false, constants.NOTIFICATIONS.RATE_LIMITED)
            return
        end

        if status ~= 200 then
            callback(false, "HTTP " .. tostring(status))
            return
        end

        local ok, response = pcall(hs.json.decode, response_body)
        if not ok then
            callback(false, "JSON parse error")
            return
        end

        if response and response.content and #response.content > 0 then
            local result = response.content[1].text or ""
            result = result:match("^%s*(.-)%s*$") or result
            callback(true, result)
        else
            callback(false, "Empty response from API")
        end
    end)
end

return M
