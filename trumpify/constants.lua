-- Constants module for Trumpify
-- Centralized configuration values and path resolution

local M = {}

function M.get_project_dir()
    local info = debug.getinfo(1, "S")
    local source = info.source
    if source:sub(1, 1) == "@" then
        source = source:sub(2)
    end
    local module_dir = source:match("^(.*)/[^/]*$")
    if not module_dir then
        return "."
    end

    local project_dir = module_dir:match("^(.*)/[^/]*$")
    if not project_dir then
        return module_dir
    end

    return project_dir
end

function M.get_config_dir()
    local home = os.getenv("HOME")
    if home then
        return home .. "/.config/" .. M.CONFIG_DIR_NAME
    end
    return M.get_project_dir()
end

-- Modifier key combinations
M.MODIFIERS = { "ctrl", "alt" }
M.MODIFIERS_SHIFT = { "ctrl", "alt", "shift" }

-- Alert styling (dark translucent overlay)
M.ALERT_STYLE = {
    strokeWidth = 0,
    strokeColor = { white = 0, alpha = 0 },
    fillColor = { white = 0, alpha = 0.75 },
    textColor = { white = 1, alpha = 1 },
    textFont = ".AppleSystemUIFont",
    textSize = 18,
    radius = 10,
    atScreenEdge = 0,
    fadeInDuration = 0.1,
    fadeOutDuration = 0.2,
    padding = 20,
}

-- Processing alert style (longer timeout, no auto-dismiss)
M.PROCESSING_ALERT_STYLE = {
    strokeWidth = 0,
    strokeColor = { white = 0, alpha = 0 },
    fillColor = { white = 0, alpha = 0.85 },
    textColor = { white = 1, alpha = 1 },
    textFont = ".AppleSystemUIFont",
    textSize = 18,
    radius = 10,
    atScreenEdge = 0,
    fadeInDuration = 0.1,
    fadeOutDuration = 0.2,
    padding = 20,
}

-- Default API configuration
M.DEFAULT_API_CONFIG = {
    endpoint = "http://localhost:6655/anthropic/v1/messages",
    model = "anthropic--claude-sonnet-latest",
    maxTokens = 32000,
    apiKey = nil,
}

-- Text processing limits
M.MAX_TEXT_LENGTH = 35000  -- ~maxTokens * 3 characters
M.LARGE_TEXT_WARNING_THRESHOLD = 25000

-- Timing constants (microseconds)
M.CLIPBOARD_COPY_DELAY = 100000   -- 100ms for copy to propagate
M.CLIPBOARD_RETRY_DELAY = 50000   -- 50ms between retries
M.CLIPBOARD_MAX_RETRIES = 3
M.PASTE_DELAY = 15000             -- 15ms before paste
M.PASTE_VERIFY_DELAY = 50000      -- 50ms before verifying paste

-- History
M.MAX_HISTORY_ENTRIES = 20

-- Config file paths
M.CONFIG_DIR_NAME = "trumpify"
M.CONFIG_FILE_NAME = "config.json"

-- Prompt directories
M.PROMPTS_DIR_NAME = "prompts"

-- Custom modes file (stored in the user config dir)
M.CUSTOM_MODES_FILE_NAME = "custom_modes.json"

-- Message durations (seconds)
M.DURATIONS = {
    NOTIFICATION = 2,
    SUCCESS = 2,
    ERROR = 10,
    WARNING = 4,
    DEBUG = 4,
}

-- Notification messages
M.NOTIFICATIONS = {
    LOADED = "Trumpify loaded!",
    RELOADED = "Trumpify reloaded!",
    NO_TEXT_SELECTED = "No text selected",
    PROCESSING = "Processing...",
    COPIED_TO_CLIPBOARD = "Copied to clipboard!",
    DONE = "Done!",
    ERROR_PREFIX = "Error: ",
    API_KEY_MISSING = "API key not configured. Check ~/.config/trumpify/config.json or .env",
    HAI_PROXY_NOT_RUNNING = "HAI Proxy not running. Start with: hai proxy start",
    INVALID_API_KEY = "Invalid API key",
    RATE_LIMITED = "Rate limited. Please wait.",
    NETWORK_ERROR = "Connection failed. Is HAI Proxy running?",
    PERMISSION_DENIED = "Accessibility permission required for Hammerspoon",
    LARGE_TEXT_WARNING = "Large text selected ({chars} chars). Processing may take longer.",
    TTS_SPEAKING = "Speaking... (⌃⌥. to stop)",
}

return M
