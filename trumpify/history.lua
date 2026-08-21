local constants = require("trumpify.constants")

local M = {}

local _history = {}
local _max_entries = constants.MAX_HISTORY_ENTRIES

function M.add(mode_name, input, output)
    table.insert(_history, 1, {
        mode = mode_name,
        input = input,
        output = output,
        timestamp = os.time(),
    })

    if #_history > _max_entries then
        table.remove(_history)
    end
end

function M.get_all()
    return _history
end

function M.get_latest()
    return _history[1]
end

function M.clear()
    _history = {}
end

function M.get_summary()
    local summary = {}
    for i, entry in ipairs(_history) do
        local time_str = os.date("%H:%M:%S", entry.timestamp)
        local preview = entry.output:sub(1, 80)
        if #entry.output > 80 then
            preview = preview .. "..."
        end
        table.insert(summary, {
            text = entry.mode .. " (" .. time_str .. ")",
            subText = preview,
        })
    end
    return summary
end

return M