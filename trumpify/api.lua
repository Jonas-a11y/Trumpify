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

function M.build_payload(model, max_tokens, text, system_prompt)
    local payload = {
        model = model,
        messages = {
            {
                role = "system",
                content = GLOBAL_SYSTEM_INSTRUCTION .. "\n\n" .. system_prompt,
            },
            { role = "user", content = M.sanitize(text) },
        },
    }

    -- Current GPT-5 endpoints use max_completion_tokens, while OpenRouter and
    -- older OpenAI-compatible models commonly use max_tokens.
    local normalized_model = tostring(model):lower()
    local token_field = normalized_model:find("gpt%-5")
        and "max_completion_tokens" or "max_tokens"
    payload[token_field] = max_tokens

    return payload
end

function M.build_headers(api_key, endpoint)
    local headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. api_key,
    }

    if endpoint:find("openrouter.ai", 1, true) then
        headers["X-Title"] = "Trumpify"
    end

    return headers
end

local function message_text(content)
    if type(content) == "string" then
        return content
    end

    if type(content) == "table" then
        local parts = {}
        for _, part in ipairs(content) do
            if type(part) == "string" then
                table.insert(parts, part)
            elseif type(part) == "table" and type(part.text) == "string" then
                table.insert(parts, part.text)
            end
        end
        if #parts > 0 then
            return table.concat(parts, "")
        end
    end

    return nil
end

function M.extract_response(response)
    if type(response) ~= "table" then
        return nil, "Invalid API response"
    end

    local choice = response.choices and response.choices[1]
    local content = choice and choice.message and choice.message.content
    local result = message_text(content)
    if result and result:match("%S") then
        return result:match("^%s*(.-)%s*$")
    end

    if response.error and type(response.error.message) == "string" then
        return nil, response.error.message
    end

    return nil, "Empty response from API"
end

local RETRYABLE_STATUS = {
    [408] = true,
    [409] = true,
    [425] = true,
    [429] = true,
    [500] = true,
    [502] = true,
    [503] = true,
    [504] = true,
}

function M.is_retryable_status(status)
    return status < 0 or RETRYABLE_STATUS[status] == true
end

local function header_value(headers, wanted)
    if type(headers) ~= "table" then return nil end
    wanted = wanted:lower()
    for key, value in pairs(headers) do
        if tostring(key):lower() == wanted then
            return value
        end
    end
    return nil
end

function M.retry_delay(retry_count, response_headers, random_value)
    local retry_after = tonumber(header_value(response_headers, "retry-after"))
    if retry_after and retry_after > 0 then
        return math.min(retry_after, constants.API_RETRY.maxDelaySeconds)
    end

    local base = constants.API_RETRY.baseDelaySeconds * (2 ^ retry_count)
    local jitter = base * constants.API_RETRY.jitterRatio * (random_value or math.random())
    return math.min(base + jitter, constants.API_RETRY.maxDelaySeconds)
end

function M.transform(text, system_prompt, callback, retry_count)
    local api_key = config.get("apiKey")
    if not api_key then
        callback(false, constants.NOTIFICATIONS.API_KEY_MISSING)
        return
    end

    local endpoint = config.get("endpoint") or constants.DEFAULT_API_CONFIG.endpoint
    local model = config.get("model") or constants.DEFAULT_API_CONFIG.model
    local max_tokens = config.get("maxTokens") or constants.DEFAULT_API_CONFIG.maxTokens

    local body = hs.json.encode(M.build_payload(model, max_tokens, text, system_prompt))
    local headers = M.build_headers(api_key, endpoint)

    retry_count = retry_count or 0

    hs.http.asyncPost(endpoint, body, headers, function(status, response_body, response_headers)
        if M.is_retryable_status(status) and retry_count < constants.API_RETRY.maxRetries then
            local delay = M.retry_delay(retry_count, response_headers)
            hs.timer.doAfter(delay, function()
                M.transform(text, system_prompt, callback, retry_count + 1)
            end)
            return
        end

        if status < 0 then
            callback(false, constants.NOTIFICATIONS.NETWORK_ERROR)
            return
        end

        if status == 401 then
            callback(false, constants.NOTIFICATIONS.INVALID_API_KEY)
            return
        end

        if status == 429 then
            callback(false, constants.NOTIFICATIONS.RATE_LIMITED)
            return
        end

        local ok, response = pcall(hs.json.decode, response_body)
        if not ok then
            callback(false, "JSON parse error")
            return
        end

        local result, response_error = M.extract_response(response)
        if status ~= 200 then
            callback(false, response_error or ("HTTP " .. tostring(status)))
            return
        end

        if result then
            callback(true, result)
            return
        end

        callback(false, response_error)
    end)
end

return M
