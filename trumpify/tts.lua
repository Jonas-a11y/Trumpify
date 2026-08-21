local config = require("trumpify.config")
local ui = require("trumpify.ui")

local M = {}

M._voice = nil
M._rate = nil
M._volume = nil
M._pitch = nil
M._fallback = true
M._speaker = nil

-- Pipeline state (chunked playback)
M._chunks = nil          -- array of remaining chunk texts
M._gen_idx = nil         -- index of next chunk to generate
M._playlist = nil        -- generated files waiting for playback
M._all_files = nil       -- every tmpfile created for the current run
M._generator = nil       -- running edge-tts task
M._player = nil          -- running afplay task
M._generating_done = nil

local EDGE_TTS_PATH = "/opt/homebrew/bin/edge-tts"
local AFPLAY_PATH = "/usr/bin/afplay"
local FFPLAY_PATH = "/opt/homebrew/bin/ffplay"
local TMP_DIR = "/tmp"
local CHUNK_MAX_LEN = 1800

local DEFAULT_VOICES = {
    de = "de-DE-KatjaNeural",
    en = "en-US-JennyNeural",
}

-- Common function words used for lightweight DE/EN language detection.
-- German words are stored in transliterated form (ae/oe/ue/ss) because
-- tokenization replaces umlauts before matching.
local GERMAN_WORDS = {
    der = true, die = true, das = true, und = true, nicht = true,
    ist = true, ein = true, eine = true, einen = true, einem = true,
    einer = true, dem = true, den = true, des = true, ich = true,
    du = true, er = true, sie = true, es = true, wir = true,
    ihr = true, mit = true, fuer = true, auf = true, auch = true,
    aber = true, sich = true, noch = true, nur = true, wie = true,
    was = true, wer = true, wenn = true, dann = true, sehr = true,
    ueber = true, unter = true, werden = true, kann = true,
    muss = true, hat = true, haben = true, war = true, sind = true,
    im = true, vom = true, zum = true, zur = true, bei = true,
    aus = true, dass = true, diese = true, dieser = true,
    dieses = true, man = true, schon = true, mehr = true, durch = true,
}

local ENGLISH_WORDS = {
    ["the"] = true, ["and"] = true, ["is"] = true, ["are"] = true,
    ["you"] = true, ["he"] = true, ["she"] = true, ["it"] = true,
    ["we"] = true, ["they"] = true, ["with"] = true, ["for"] = true,
    ["on"] = true, ["not"] = true, ["this"] = true, ["that"] = true,
    ["have"] = true, ["has"] = true, ["was"] = true, ["were"] = true,
    ["will"] = true, ["can"] = true, ["from"] = true, ["of"] = true,
    ["to"] = true, ["be"] = true, ["been"] = true, ["there"] = true,
    ["their"] = true, ["would"] = true, ["could"] = true,
    ["should"] = true, ["about"] = true, ["which"] = true,
    ["when"] = true, ["what"] = true, ["who"] = true, ["its"] = true,
    ["an"] = true, ["as"] = true, ["by"] = true, ["or"] = true,
    ["if"] = true, ["than"] = true, ["then"] = true,
}

local function _load_settings()
    local cfg = config.get("tts")
    if type(cfg) ~= "table" then cfg = {} end

    M._voice = cfg.voice
    if M._voice == "" then M._voice = nil end
    M._rate = cfg.rate or "+0%"
    M._volume = cfg.volume or "+0%"
    M._pitch = cfg.pitch or "+0Hz"
    local fb = cfg.fallback
    if fb == nil then fb = true end
    M._fallback = fb
end

-- Remove leftover audio files from crashed/killed sessions.
local function _cleanup_orphan_tmpfiles()
    pcall(function()
        for name in hs.fs.dir(TMP_DIR) do
            if type(name) == "string"
                and (name:match("^trumpify_tts_%d+_%d+%.mp3$")
                    or name:match("^trumpify_tts_%d+_%d+%.fifo$")) then
                os.remove(TMP_DIR .. "/" .. name)
            end
        end
    end)
end

function M.init()
    _load_settings()
    _cleanup_orphan_tmpfiles()
    if hs and hs.speech then
        M._speaker = hs.speech.new()
    end
    return M
end

-- Lightweight DE/EN detection via function-word scoring plus an umlaut
-- bonus. Returns "de" or "en".
function M.detect_language(text)
    if not text or text == "" then return "en" end
    local lower = text:lower()

    local de_score, en_score = 0, 0
    for _ in lower:gmatch("ä") do de_score = de_score + 2 end
    for _ in lower:gmatch("ö") do de_score = de_score + 2 end
    for _ in lower:gmatch("ü") do de_score = de_score + 2 end
    for _ in lower:gmatch("ß") do de_score = de_score + 3 end

    -- Transliterate umlauts so %a+ tokenization keeps whole words
    local ascii = lower
        :gsub("ä", "ae"):gsub("ö", "oe"):gsub("ü", "ue"):gsub("ß", "ss")

    for word in ascii:gmatch("%a+") do
        if GERMAN_WORDS[word] then de_score = de_score + 1 end
        if ENGLISH_WORDS[word] then en_score = en_score + 1 end
    end

    if de_score > en_score then return "de" end
    return "en"
end

-- Split long text into chunks at sentence boundaries (fallback: whitespace,
-- then raw byte cuts that respect UTF-8 sequences).
function M.chunk_text(text, max_len)
    max_len = max_len or CHUNK_MAX_LEN
    if not text or text == "" then return {} end
    if #text <= max_len then return { text } end

    local chunks = {}
    local pos = 1
    local len = #text
    local min_cut = math.floor(max_len / 2)

    while pos <= len do
        local remaining = len - pos + 1
        if remaining <= max_len then
            table.insert(chunks, text:sub(pos))
            break
        end

        local window = text:sub(pos, pos + max_len - 1)
        local cut = 0

        -- Prefer the last sentence boundary in the window's second half
        for i = #window, min_cut, -1 do
            local b = window:byte(i)
            if b == 46 or b == 33 or b == 63 or b == 10 then -- . ! ? \n
                cut = i
                break
            end
        end

        -- Fall back to the last whitespace boundary
        if cut == 0 then
            for i = #window, min_cut, -1 do
                local b = window:byte(i)
                if b == 32 or b == 9 then -- space, tab
                    cut = i
                    break
                end
            end
        end

        -- Last resort: hard cut, backing off UTF-8 continuation bytes
        if cut == 0 then
            cut = max_len
            while cut > 1 do
                local b = window:byte(cut)
                if b < 128 or b >= 192 then break end
                cut = cut - 1
            end
        else
            -- Include trailing spaces after the boundary
            while cut < #window and window:byte(cut + 1) == 32 do
                cut = cut + 1
            end
        end

        table.insert(chunks, window:sub(1, cut))
        pos = pos + cut
    end

    return chunks
end

local function _pick_voice(text)
    if M._voice then return M._voice end
    local lang = M.detect_language(text)
    return DEFAULT_VOICES[lang]
end

local function _edge_tts_available()
    return hs.fs.attributes and hs.fs.attributes(EDGE_TTS_PATH) ~= nil
end

local function _ffplay_available()
    return hs.fs.attributes and hs.fs.attributes(FFPLAY_PATH) ~= nil
end

local function _make_tmpfile(idx)
    return TMP_DIR .. "/trumpify_tts_" .. tostring(os.time())
        .. "_" .. tostring(idx) .. ".mp3"
end

-- Create a named pipe for streaming playback (used with ffplay).
local function _make_fifo(idx)
    local path = TMP_DIR .. "/trumpify_tts_" .. tostring(os.time())
        .. "_" .. tostring(idx) .. ".fifo"
    pcall(os.remove, path)
    local ok = pcall(hs.execute, "mkfifo " .. path)
    if ok then return path end
    return nil
end

local function _remove_file(file)
    if file then pcall(os.remove, file) end
end

local function _reset_pipeline()
    M._chunks = nil
    M._gen_idx = nil
    M._playlist = nil
    M._all_files = nil
    M._generator = nil
    M._player = nil
    M._generating_done = nil
    M._cur_idx = nil
    M._current_fifo = nil
    M._chunk_done = nil
    M._completed_any = nil
end

local function _fallback_speak(text)
    if not M._speaker then
        if hs and hs.speech then M._speaker = hs.speech.new() end
    end
    if M._speaker then
        pcall(function() M._speaker:rate(200) end)
        M._speaker:speak(text)
    end
end

local function _handle_failure(message)
    local had_audio = M._completed_any
        or (M._playlist and #M._playlist > 0)
        or (M._player ~= nil)
    local full_text = M._chunks and table.concat(M._chunks, " ") or nil
    local files = M._all_files
    _reset_pipeline()
    if files then
        for _, f in ipairs(files) do _remove_file(f) end
    end

    -- Let already-started playback finish naturally; only report/fallback
    -- when nothing was audible yet.
    if not had_audio then
        if M._fallback and full_text then
            _fallback_speak(full_text)
        else
            ui.show_error("TTS failed: " .. (message or "unknown error"))
        end
    end
end

-- ===== Streaming mode (ffplay + named pipe) =====
-- Audio starts playing as soon as the first bytes of a chunk arrive,
-- instead of waiting for the whole chunk to be generated. Chunks play
-- strictly one after another; if ffplay is unavailable the file-based
-- pipeline below is used instead.

local _stream_chunk  -- forward declaration (mutual recursion with _on_chunk_done)

local function _on_chunk_done(success, message)
    if not M._chunks or M._chunk_done then return end
    M._chunk_done = true

    if M._generator then
        pcall(function() M._generator:terminate() end)
        M._generator = nil
    end
    if M._player then
        pcall(function() M._player:terminate() end)
        M._player = nil
    end
    _remove_file(M._current_fifo)
    M._current_fifo = nil

    if not success then
        _handle_failure(message)
        return
    end

    M._completed_any = true
    local next_idx = (M._cur_idx or 0) + 1
    if next_idx > #M._chunks then
        _reset_pipeline()
    else
        M._cur_idx = next_idx
        _stream_chunk(next_idx)
    end
end

_stream_chunk = function(idx)
    M._chunk_done = false

    local text = M._chunks[idx]
    local fifo = _make_fifo(idx)
    if not fifo then
        _on_chunk_done(false, "could not create named pipe")
        return
    end
    M._current_fifo = fifo
    table.insert(M._all_files, fifo)

    -- Reader first: ffplay blocks on open until the writer appears.
    local ok_p, player = pcall(hs.task.new, FFPLAY_PATH, function(exitCode)
        M._player = nil
        -- Completion is driven by whichever task finishes last; if the
        -- writer already finished, this is the final signal.
        if M._chunks and M._generator == nil then
            _on_chunk_done(exitCode == 0, "ffplay exited with " .. tostring(exitCode))
        end
    end, { "-nodisp", "-autoexit", "-loglevel", "error", fifo })
    if not ok_p or not player then
        _on_chunk_done(false, "ffplay could not start")
        return
    end
    M._player = player
    player:start()

    local args = {
        "--voice", _pick_voice(text),
        "--rate", M._rate,
        "--volume", M._volume,
        "--pitch", M._pitch,
        "--text", text,
        "--write-media", fifo,
    }
    local ok_g, gen = pcall(hs.task.new, EDGE_TTS_PATH, function(exitCode)
        M._generator = nil
        if exitCode ~= 0 then
            _on_chunk_done(false, "edge-tts exited with " .. tostring(exitCode))
        elseif M._player == nil then
            -- Very short chunk: player already drained and exited.
            _on_chunk_done(true)
        end
        -- Otherwise wait for ffplay to drain; its callback completes.
    end, args)
    if not ok_g or not gen then
        _on_chunk_done(false, "edge-tts could not start")
        return
    end
    M._generator = gen
    gen:start()
end

-- ===== File pipeline mode (fallback when ffplay is unavailable) =====

local function _pump()
    if M._player then return end
    if not M._playlist then return end

    local file = table.remove(M._playlist, 1)
    if not file then
        if M._generating_done and not M._generator then
            _reset_pipeline()
        end
        return
    end

    local ok_play, play = pcall(hs.task.new, AFPLAY_PATH, function()
        M._player = nil
        _remove_file(file)
        _pump()
    end, { file })

    if ok_play and play then
        M._player = play
        play:start()
    else
        _remove_file(file)
        _handle_failure("audio player could not start")
    end
end

local function _generate_next()
    if not M._chunks then return end

    local i = M._gen_idx
    if i > #M._chunks then
        M._generating_done = true
        _pump()
        return
    end
    M._gen_idx = i + 1

    local voice = _pick_voice(M._chunks[i])
    local file = _make_tmpfile(i)
    table.insert(M._all_files, file)

    local args = {
        "--voice", voice,
        "--rate", M._rate,
        "--volume", M._volume,
        "--pitch", M._pitch,
        "--text", M._chunks[i],
        "--write-media", file,
    }

    local ok, task = pcall(hs.task.new, EDGE_TTS_PATH, function(exitCode)
        M._generator = nil
        if exitCode == 0 then
            table.insert(M._playlist, file)
            _pump()
            _generate_next()
        else
            _handle_failure("edge-tts exited with code " .. tostring(exitCode))
        end
    end, args)

    if ok and task then
        M._generator = task
        task:start()
    else
        _handle_failure("edge-tts task could not start")
    end
end

function M.speak(text)
    if not text or text == "" then return end

    M.stop()

    if not _edge_tts_available() then
        if M._fallback then
            _fallback_speak(text)
        else
            ui.show_error("TTS failed: edge-tts not found at " .. EDGE_TTS_PATH)
        end
        return
    end

    M._chunks = M.chunk_text(text)
    M._all_files = {}

    if _ffplay_available() then
        -- Streaming mode: playback starts while each chunk is generated
        M._cur_idx = 1
        _stream_chunk(1)
    else
        -- File pipeline mode
        M._gen_idx = 1
        M._playlist = {}
        M._generating_done = false
        _generate_next()
    end
end

-- Speak text with temporary overrides (used by the settings panel test
-- button). Does not persist anything.
function M.preview(text, opts)
    opts = opts or {}
    local saved = {
        voice = M._voice,
        rate = M._rate,
        volume = M._volume,
        pitch = M._pitch,
    }
    if opts.voice ~= nil then
        M._voice = (opts.voice ~= "" and opts.voice ~= "auto") and opts.voice or nil
    end
    if opts.rate ~= nil then M._rate = opts.rate end
    if opts.volume ~= nil then M._volume = opts.volume end
    if opts.pitch ~= nil then M._pitch = opts.pitch end
    M.speak(text)
    M._voice = saved.voice
    M._rate = saved.rate
    M._volume = saved.volume
    M._pitch = saved.pitch
end

function M.stop()
    if M._generator then
        pcall(function() M._generator:terminate() end)
    end
    if M._player then
        pcall(function() M._player:terminate() end)
    end
    if M._speaker then
        pcall(function() M._speaker:stop() end)
    end
    local files = M._all_files
    local playlist = M._playlist
    _reset_pipeline()
    if playlist then
        for _, f in ipairs(playlist) do _remove_file(f) end
    end
    if files then
        for _, f in ipairs(files) do _remove_file(f) end
    end
end

function M.isSpeaking()
    if M._generator or M._player then return true end
    if M._playlist and #M._playlist > 0 then return true end
    if M._speaker then
        local ok, result = pcall(function() return M._speaker:isSpeaking() end)
        return ok and result or false
    end
    return false
end

local function _persist()
    config.set("tts", {
        voice = M._voice,
        rate = M._rate,
        volume = M._volume,
        pitch = M._pitch,
        fallback = M._fallback,
    })
    config.save()
end

function M.setVoice(voice)
    M._voice = (voice and voice ~= "") and voice or nil
    _persist()
end

function M.setRate(rate)
    M._rate = rate or "+0%"
    _persist()
end

function M.setVolume(volume)
    M._volume = volume or "+0%"
    _persist()
end

function M.setPitch(pitch)
    M._pitch = pitch or "+0Hz"
    _persist()
end

function M.setFallback(enabled)
    M._fallback = enabled and true or false
    _persist()
end

return M