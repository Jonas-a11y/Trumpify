local M = {}

M.config = {
    endpoint = "http://localhost:6655/anthropic/v1/messages",
    model = "anthropic--claude-4.6-opus",
    maxTokens = 4096,
    apiKey = nil,
}

function M.loadApiKey(envPath)
    local f = io.open(envPath, "r")
    if not f then
        hs.alert.show("Trumpify: Cannot read .env file")
        return false
    end
    local content = f:read("*all")
    f:close()
    local key = content:match("HAIPROXY_API_KEY=([^\n%s]+)")
    if not key then
        hs.alert.show("Trumpify: API key not found in .env")
        return false
    end
    M.config.apiKey = key
    return true
end

function M.transform(text, systemPrompt, callback)
    if not M.config.apiKey then
        callback(false, "API key not configured")
        return
    end

    local body = hs.json.encode({
        model = M.config.model,
        max_tokens = M.config.maxTokens,
        system = systemPrompt,
        messages = { { role = "user", content = text } },
    })

    local headers = {
        ["Content-Type"] = "application/json",
        ["x-api-key"] = M.config.apiKey,
        ["anthropic-version"] = "2023-06-01",
    }

    hs.http.asyncPost(M.config.endpoint, body, headers, function(status, responseBody, responseHeaders)
        if status < 0 then
            callback(false, "Connection failed - is HAI proxy running?")
            return
        end
        if status ~= 200 then
            callback(false, "HTTP " .. tostring(status))
            return
        end

        local ok, response = pcall(hs.json.decode, responseBody)
        if not ok then
            callback(false, "JSON parse error")
            return
        end

        if response and response.content and #response.content > 0 then
            callback(true, response.content[1].text)
        else
            callback(false, "Empty response from API")
        end
    end)
end

return M
