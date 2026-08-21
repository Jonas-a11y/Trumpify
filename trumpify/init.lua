local constants = require("trumpify.constants")
local config = require("trumpify.config")
local ui = require("trumpify.ui")
local prompt_loader = require("trumpify.prompt_loader")
local transformer = require("trumpify.transformer")
local hotkeys = require("trumpify.hotkeys")
local tts = require("trumpify.tts")
local settings_panel = require("trumpify.settings_panel")

config.init()

local project_dir = constants.get_project_dir()
local api_key = config.get("apiKey")

if api_key then
    ui.show_notification(constants.NOTIFICATIONS.LOADED)
else
    ui.show_error(
        "API key not found. Checked:\n" ..
        "- " .. constants.get_config_dir() .. "/config.json\n" ..
        "- " .. project_dir .. "/config.json\n" ..
        "- " .. project_dir .. "/.env\n" ..
        "- $HAIPROXY_API_KEY"
    )
end

tts.init()

local prompt_errors = prompt_loader.init()
if prompt_errors and #prompt_errors > 0 then
    ui.show_error("Prompt load issues:\n" .. table.concat(prompt_errors, "\n"))
end

transformer.init()

local hotkey_errors = hotkeys.init()
if hotkey_errors and #hotkey_errors > 0 then
    ui.show_error("Hotkey issues:\n" .. table.concat(hotkey_errors, "\n"))
end

hotkeys.create_chooser()

settings_panel.init({
    on_apply = function()
        tts.init()
        hotkeys.register_all()
        hotkeys.refresh_chooser()
    end,
})
