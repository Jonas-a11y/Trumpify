local config = require("trumpify.config")

local M = {}

M.intensities = {
    { value = "subtle", label = "Dezent", instruction = "Use restrained parody and occasional exaggeration." },
    { value = "exaggerated", label = "Überzogen", instruction = "Use strong exaggeration and recognizable comic rhetoric." },
    { value = "maximal", label = "Maximal", instruction = "Use maximal absurd exaggeration and rambling comic tangents." },
}
M.lengths = {
    { value = "short", label = "Kurz", instruction = "Keep the result concise, at most three sentences." },
    { value = "original", label = "Ursprüngliche Länge", instruction = "Keep approximately the same length as the input." },
    { value = "expansive", label = "Ausschweifend", instruction = "Expand into a longer, rambling monologue." },
}
M.defaults = { intensity = "exaggerated", length = "original", maxSentences = 4,
    officeSafe = true, preserveFacts = true }

local forms = { "a haiku", "a dramatic speech", "a medieval herald's announcement",
    "an absurdly formal administrative notice", "a sports commentary", "a space mission briefing" }

local function instruction(choices, value)
    for _, choice in ipairs(choices) do
        if choice.value == value then return choice.instruction end
    end
end

function M.settings()
    local settings = {}
    for key, value in pairs(M.defaults) do settings[key] = value end
    for key, value in pairs(config.get("creative") or {}) do settings[key] = value end
    return settings
end

function M.validate(settings)
    if not instruction(M.intensities, settings.intensity) or not instruction(M.lengths, settings.length) then
        return false, "Choose a valid intensity and length"
    end
    if type(settings.maxSentences) ~= "number" or settings.maxSentences % 1 ~= 0
        or settings.maxSentences < 1 or settings.maxSentences > 20 then
        return false, "Surprise length must be 1–20 sentences"
    end
    if type(settings.officeSafe) ~= "boolean" or type(settings.preserveFacts) ~= "boolean" then
        return false, "Surprise constraints must be enabled or disabled"
    end
    return true
end

function M.build_system(mode)
    if not mode.creative then return mode.system end
    local settings = M.settings()
    if mode.creative == "trumpify" then
        return mode.system .. "\n\nThese user preferences override any conflicting style or length instructions above:\n"
            .. (instruction(M.intensities, settings.intensity) or M.intensities[2].instruction) .. "\n"
            .. (instruction(M.lengths, settings.length) or M.lengths[2].instruction)
    end
    local system = mode.system .. "\n\nChosen form: " .. forms[math.random(#forms)]
        .. ". Use at most " .. tostring(settings.maxSentences) .. " sentences."
    if settings.officeSafe then
        system = system .. " Keep it suitable for work: no profanity, personal insults or sexual content."
    end
    if settings.preserveFacts then
        system = system .. " Preserve all names, numbers, dates, decisions and commitments. Do not invent factual claims."
    end
    return system
end

return M
