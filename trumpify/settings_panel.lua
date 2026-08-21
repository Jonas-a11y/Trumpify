local config = require("trumpify.config")
local constants = require("trumpify.constants")
local prompt_loader = require("trumpify.prompt_loader")
local tts = require("trumpify.tts")
local ui = require("trumpify.ui")

local M = {}

M._deps = { on_apply = nil }
M._webview = nil
M._usercontent = nil
M._modal = nil
M._voices_cache = nil

local EDGE_TTS_PATH = "/opt/homebrew/bin/edge-tts"

local SAMPLE_TEXT = "Hello! This is a Trumpify voice test. Dies ist ein Sprachtest."

local FALLBACK_VOICES = {
    "de-DE-KatjaNeural",
    "de-DE-ConradNeural",
    "de-DE-AmalaNeural",
    "en-US-JennyNeural",
    "en-US-AriaNeural",
    "en-US-GuyNeural",
    "en-US-EmmaNeural",
    "en-US-BrianNeural",
    "en-US-MichelleNeural",
    "en-US-ChristopherNeural",
}

local DEFAULT_TTS = { rate = "+0%", volume = "+0%", pitch = "+0Hz", fallback = true }

function M.init(deps)
    M._deps = deps or M._deps
end

-- Pure validation logic (no hs dependency, unit-testable).
-- mode_list: array of { id = "...", key = "default key or nil" }
-- keymap: table mode_id -> key string
-- reserved: table lowercase key -> purpose string
-- Returns array of error strings; empty means valid.
function M.validate_keymap(mode_list, keymap, reserved)
    local errors = {}
    local used = {}
    for _, m in ipairs(mode_list) do
        local k = keymap and keymap[m.id]
        if k and k ~= "" then
            if type(k) ~= "string" or #k ~= 1 then
                table.insert(errors, m.id .. ": key must be a single character")
            else
                local lk = k:lower()
                if reserved and reserved[lk] then
                    table.insert(errors, m.id .. ": key '" .. k .. "' is reserved (" .. reserved[lk] .. ")")
                elseif used[lk] then
                    table.insert(errors, m.id .. ": key '" .. k .. "' collides with '" .. used[lk] .. "'")
                else
                    used[lk] = m.id
                end
            end
        end
    end
    return errors
end

local function _push_js(fn, data)
    if not M._webview then return end
    local ok, json = pcall(hs.json.encode, data)
    if not ok or not json then return end
    local js = "window.trumpifyPanel && window.trumpifyPanel." .. fn .. "(" .. json .. ");"
    pcall(function() M._webview:evaluateJavaScript(js) end)
end

local function _sorted_modes()
    local modes = prompt_loader.get_all_modes()
    local list = {}
    for id, mode in pairs(modes) do
        table.insert(list, { id = id, name = mode.name, key = mode.key })
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

local function _pct_num(value)
    return tonumber(tostring(value or ""):match("%-?%d+")) or 0
end

local function _handle_close()
    M.close()
end

local function _handle_test_voice(data)
    local p = data.payload or {}
    tts.preview(SAMPLE_TEXT, {
        voice = p.voice,
        rate = p.rate,
        volume = p.volume,
        pitch = p.pitch,
    })
end

local function _handle_save(data)
    local payload = data.payload or {}
    local tts_cfg = payload.tts or {}
    local keymap = payload.keymap or {}
    local disabled = payload.disabled or {}
    local advanced = payload.advanced or {}

    local mode_list = {}
    for _, m in ipairs(_sorted_modes()) do
        table.insert(mode_list, { id = m.id, key = m.key })
    end

    local hotkeys = require("trumpify.hotkeys")
    local errors = M.validate_keymap(mode_list, keymap, hotkeys.get_reserved_keys())
    if #errors > 0 then
        _push_js("showErrors", errors)
        return
    end

    -- Advanced/API validation (mirrors the client-side checks)
    local endpoint = tostring(advanced.endpoint or "")
    local model = tostring(advanced.model or "")
    local max_tokens = tonumber(advanced.maxTokens) or 0
    if not endpoint:match("^https?://") then
        _push_js("showErrors", { "Endpoint must be an http(s) URL" })
        return
    end
    if model == "" or max_tokens < 1 or max_tokens > 100000 then
        _push_js("showErrors", { "Model must not be empty; Max Tokens must be 1-100000" })
        return
    end

    local clean_tts = {
        voice = (tts_cfg.voice and tts_cfg.voice ~= "" and tts_cfg.voice ~= "auto") and tts_cfg.voice or nil,
        rate = tts_cfg.rate or DEFAULT_TTS.rate,
        volume = tts_cfg.volume or DEFAULT_TTS.volume,
        pitch = tts_cfg.pitch or DEFAULT_TTS.pitch,
        fallback = tts_cfg.fallback and true or false,
    }

    local clean_keymap = {}
    for id, k in pairs(keymap) do
        if type(k) == "string" and k ~= "" then
            -- Normalize to lowercase: the panel displays uppercase, but
            -- hs.hotkey.bind expects lowercase key names.
            clean_keymap[id] = k:lower()
        end
    end

    local clean_disabled = {}
    if type(disabled) == "table" then
        for _, id in ipairs(disabled) do
            table.insert(clean_disabled, id)
        end
    end

    config.set("tts", clean_tts)
    config.set("keymap", clean_keymap)
    config.set("disabledModes", clean_disabled)
    config.set("endpoint", endpoint)
    config.set("model", model)
    config.set("maxTokens", max_tokens)

    local ok, err = config.save()
    if not ok then
        _push_js("showErrors", { "Could not save config: " .. tostring(err) })
        return
    end

    if M._deps.on_apply then
        pcall(M._deps.on_apply)
    end
    _push_js("showStatus", "Settings saved")
end

local function _parse_voices(output)
    local voices = {}
    for line in output:gmatch("[^\r\n]+") do
        local name = line:match("^(%a%a%-%a%a%-%w+Neural)%s")
        if name and (name:sub(1, 3) == "de-" or name:sub(1, 3) == "en-") then
            table.insert(voices, name)
        end
    end
    table.sort(voices)
    return voices
end

local function _load_voices_async()
    if M._voices_cache then
        _push_js("setVoices", M._voices_cache)
        return
    end

    local ok, task = pcall(hs.task.new, EDGE_TTS_PATH, function(code, stdout)
        if code == 0 and stdout and #stdout > 0 then
            local voices = _parse_voices(stdout)
            if #voices > 0 then
                M._voices_cache = voices
                _push_js("setVoices", voices)
            end
        end
    end, { "--list-voices" })

    if ok and task then
        task:start()
    end
end

local function _handle_message(data)
    local action = data.action
    if action == "close" then
        _handle_close()
    elseif action == "testVoice" then
        _handle_test_voice(data)
    elseif action == "save" then
        _handle_save(data)
    elseif action == "ready" then
        _load_voices_async()
    end
end

-- Exposed on the module table so tests can exercise HTML generation.
function M._build_html()
    local modes = _sorted_modes()

    local keymap = config.get("keymap")
    if type(keymap) ~= "table" then keymap = {} end

    local disabled = config.get("disabledModes")
    if type(disabled) ~= "table" then disabled = {} end
    local disabled_map = {}
    for _, id in ipairs(disabled) do
        disabled_map[id] = true
    end

    local tts_cfg = config.get("tts")
    if type(tts_cfg) ~= "table" then tts_cfg = {} end

    local defaults = constants.DEFAULT_API_CONFIG

    local advanced = {
        endpoint = config.get("endpoint") or defaults.endpoint,
        model = config.get("model") or defaults.model,
        maxTokens = tonumber(config.get("maxTokens")) or defaults.maxTokens,
    }

    local hotkeys = require("trumpify.hotkeys")
    local reserved = hotkeys.get_reserved_keys()

    local mode_states = {}
    for _, m in ipairs(modes) do
        table.insert(mode_states, {
            id = m.id,
            name = m.name,
            defaultKey = m.key or "",
            currentKey = keymap[m.id] or "",
            enabled = not disabled_map[m.id],
        })
    end

    local state = {
        modes = mode_states,
        reserved = reserved,
        tts = {
            voice = tts_cfg.voice or "auto",
            rate = _pct_num(tts_cfg.rate),
            volume = _pct_num(tts_cfg.volume),
            pitch = _pct_num(tts_cfg.pitch),
            fallback = (tts_cfg.fallback == nil) and true or tts_cfg.fallback and true or false,
        },
        advanced = advanced,
        defaults = {
            endpoint = defaults.endpoint,
            model = defaults.model,
            maxTokens = defaults.maxTokens,
        },
        fallbackVoices = FALLBACK_VOICES,
    }

    local ok, state_json = pcall(hs.json.encode, state)
    if not ok or not state_json then
        state_json = "{}"
    end
    state_json = state_json:gsub("</", "<\\/")

    return [==[<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  * { box-sizing: border-box; }
  html, body { height: 100%; margin: 0; }
  body {
    font-family: -apple-system, sans-serif;
    font-size: 13px;
    background: #1e1e1e;
    color: #e0e0e0;
    padding: 16px 20px 12px 20px;
    overflow-y: auto;
  }
  h1 { font-size: 16px; margin: 0 0 12px 0; color: #fff; }
  h2 {
    font-size: 12px; text-transform: uppercase; letter-spacing: 1px;
    color: #888; border-bottom: 1px solid #333;
    padding-bottom: 4px; margin: 18px 0 10px 0;
  }
  .row { display: flex; align-items: center; margin: 8px 0; gap: 10px; }
  .row label.main { flex: 0 0 160px; }
  select {
    flex: 1; background: #2a2a2a; color: #e0e0e0;
    border: 1px solid #444; border-radius: 5px; padding: 4px 6px;
  }
  input[type="text"] {
    width: 46px; background: #2a2a2a; color: #e0e0e0;
    border: 1px solid #444; border-radius: 5px; padding: 4px 6px;
    text-align: center; text-transform: uppercase;
  }
  input[type="text"].invalid { border-color: #e05555; background: #3a2222; }
  input[type="range"] { flex: 1; }
  .val { flex: 0 0 52px; text-align: right; color: #aaa; font-variant-numeric: tabular-nums; }
  .hint { color: #666; font-size: 11px; }
  .modes-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 4px 20px; }
  .modes-grid label { display: flex; align-items: center; gap: 8px; padding: 2px 0; }
  .errors { color: #ff7b7b; font-size: 12px; white-space: pre-line; min-height: 16px; margin: 8px 0; }
  .status { color: #7bd88f; font-size: 12px; min-height: 16px; margin: 8px 0; }
  .footer {
    position: sticky; bottom: -12px; background: #1e1e1e;
    display: flex; justify-content: space-between; align-items: center;
    padding: 10px 0 12px 0; margin-top: 10px;
  }
  button {
    background: #333; color: #e0e0e0; border: 1px solid #555;
    border-radius: 6px; padding: 6px 16px; font-size: 13px; cursor: pointer;
  }
  button:hover { background: #3d3d3d; }
  button.primary { background: #2d5a88; border-color: #3a6ea5; color: #fff; }
  button.primary:hover { background: #35699f; }
  .spacer { flex: 1; }
</style>
</head>
<body>
  <h1>Trumpify Settings</h1>
  <div id="content"></div>
  <div class="errors" id="errors"></div>
  <div class="status" id="status"></div>
  <div class="footer">
    <button id="btn-reset">Reset to Defaults</button>
    <span class="spacer"></span>
    <button id="btn-close">Close</button>
    <button id="btn-save" class="primary">Save</button>
  </div>
<script>
window.__STATE__ = ]==] .. state_json .. [==[;

(function() {
  var S = window.__STATE__;
  var content = document.getElementById('content');

  function fmtPct(v) { return (v >= 0 ? '+' : '') + v + '%'; }
  function fmtHz(v)  { return (v >= 0 ? '+' : '') + v + 'Hz'; }

  function el(tag, attrs, text) {
    var e = document.createElement(tag);
    if (attrs) for (var k in attrs) e.setAttribute(k, attrs[k]);
    if (text) e.textContent = text;
    return e;
  }

  function section(title) {
    content.appendChild(el('h2', null, title));
  }

  function row(labelText, input, hint) {
    var r = el('div', {class: 'row'});
    var l = el('label', {class: 'main'}, labelText);
    r.appendChild(l);
    r.appendChild(input);
    if (hint) r.appendChild(el('span', {class: 'hint'}, hint));
    return r;
  }

  // ---- TTS section ----
  section('Text-to-Speech');

  var voiceSelect = el('select', {id: 'tts-voice'});
  voiceSelect.appendChild(el('option', {value: 'auto'}, 'Automatisch (Sprache erkennen)'));
  S.fallbackVoices.forEach(function(v) {
    voiceSelect.appendChild(el('option', {value: v}, v));
  });
  if (S.tts.voice && S.tts.voice !== 'auto') {
    var exists = Array.prototype.some.call(voiceSelect.options, function(o) { return o.value === S.tts.voice; });
    if (!exists) voiceSelect.appendChild(el('option', {value: S.tts.voice}, S.tts.voice));
    voiceSelect.value = S.tts.voice;
  } else {
    voiceSelect.value = 'auto';
  }
  content.appendChild(row('Voice', voiceSelect));

  function slider(id, min, max, step, value, fmt) {
    var input = el('input', {type: 'range', id: id, min: min, max: max, step: step, value: value});
    var val = el('span', {class: 'val'}, fmt(value));
    input.addEventListener('input', function() { val.textContent = fmt(Number(input.value)); });
    var wrap = el('div');
    wrap.style.display = 'contents';
    wrap.appendChild(input);
    wrap.appendChild(val);
    return wrap;
  }
  content.appendChild(row('Rate', slider('tts-rate', -50, 100, 5, S.tts.rate, fmtPct)));
  content.appendChild(row('Volume', slider('tts-volume', -50, 50, 5, S.tts.volume, fmtPct)));
  content.appendChild(row('Pitch', slider('tts-pitch', -50, 50, 5, S.tts.pitch, fmtHz)));

  var fbWrap = el('div', {class: 'row'});
  var fbLabel = el('label', {class: 'main'}, 'macOS fallback');
  var fbCheck = el('input', {type: 'checkbox', id: 'tts-fallback'});
  if (S.tts.fallback) fbCheck.checked = true;
  fbWrap.appendChild(fbLabel);
  fbWrap.appendChild(fbCheck);
  fbWrap.appendChild(el('span', {class: 'hint'}, 'use macOS voice if edge-tts fails'));
  content.appendChild(fbWrap);

  var testBtn = el('button', null, 'Test Voice');
  testBtn.style.marginTop = '6px';
  testBtn.addEventListener('click', function() {
    post('testVoice', { payload: collectTts() });
  });
  content.appendChild(testBtn);

  // ---- Shortcuts section ----
  section('Shortcuts (Ctrl+Option + key)');
  var shortcutsDiv = el('div');
  var keyInputs = {};
  S.modes.forEach(function(m) {
    var input = el('input', {type: 'text', maxlength: '1', 'data-mode': m.id});
    input.value = m.currentKey;
    input.placeholder = m.defaultKey;
    keyInputs[m.id] = input;
    var r = el('div', {class: 'row'});
    r.appendChild(el('label', {class: 'main'}, m.name));
    r.appendChild(input);
    r.appendChild(el('span', {class: 'hint'}, 'default: ' + (m.defaultKey || 'none')));
    shortcutsDiv.appendChild(r);
    input.addEventListener('input', function() {
      input.value = input.value.toUpperCase();
      input.classList.remove('invalid');
    });
  });
  content.appendChild(shortcutsDiv);
  content.appendChild(el('div', {class: 'hint', style: 'margin-top:4px'},
    'Reserved: R (reload), Space (chooser), . (stop TTS)'));

  // ---- Modes section ----
  section('Modes');
  var modesGrid = el('div', {class: 'modes-grid'});
  var modeChecks = {};
  S.modes.forEach(function(m) {
    var check = el('input', {type: 'checkbox', 'data-mode': m.id});
    if (m.enabled) check.checked = true;
    modeChecks[m.id] = check;
    var label = el('label');
    label.appendChild(check);
    label.appendChild(document.createTextNode(m.name));
    modesGrid.appendChild(label);
  });
  content.appendChild(modesGrid);

  // ---- Advanced section ----
  section('Advanced (API)');
  var endpointInput = el('input', {type: 'text', id: 'adv-endpoint', style: 'flex:1; width:auto; text-transform:none;'});
  endpointInput.value = S.advanced.endpoint;
  content.appendChild(row('Endpoint', endpointInput));

  var modelInput = el('input', {type: 'text', id: 'adv-model', style: 'flex:1; width:auto; text-transform:none;'});
  modelInput.value = S.advanced.model;
  content.appendChild(row('Model', modelInput));

  var maxTokensInput = el('input', {type: 'text', id: 'adv-maxtokens', style: 'width:90px; text-transform:none;'});
  maxTokensInput.value = S.advanced.maxTokens;
  content.appendChild(row('Max Tokens', maxTokensInput));

  // ---- collect / validate / post ----
  function collectTts() {
    return {
      voice: voiceSelect.value,
      rate: fmtPct(Number(document.getElementById('tts-rate').value)),
      volume: fmtPct(Number(document.getElementById('tts-volume').value)),
      pitch: fmtHz(Number(document.getElementById('tts-pitch').value)),
      fallback: document.getElementById('tts-fallback').checked
    };
  }

  function collectKeymap() {
    var km = {};
    S.modes.forEach(function(m) { km[m.id] = keyInputs[m.id].value.trim(); });
    return km;
  }

  function collectDisabled() {
    var out = [];
    S.modes.forEach(function(m) {
      if (!modeChecks[m.id].checked) out.push(m.id);
    });
    return out;
  }

  function collectAdvanced() {
    return {
      endpoint: endpointInput.value.trim(),
      model: modelInput.value.trim(),
      maxTokens: parseInt(maxTokensInput.value, 10) || 0
    };
  }

  function validateAdvanced(adv) {
    var errors = [];
    if (!adv.endpoint || (adv.endpoint.indexOf('http://') !== 0 && adv.endpoint.indexOf('https://') !== 0)) {
      errors.push('Endpoint must be an http(s) URL');
      endpointInput.classList.add('invalid');
    }
    if (!adv.model) {
      errors.push('Model must not be empty');
      modelInput.classList.add('invalid');
    }
    if (!adv.maxTokens || adv.maxTokens < 1 || adv.maxTokens > 100000) {
      errors.push('Max Tokens must be between 1 and 100000');
      maxTokensInput.classList.add('invalid');
    }
    return errors;
  }

  function validateLocal() {
    var km = collectKeymap();
    var used = {};
    var valid = true;
    S.modes.forEach(function(m) {
      var input = keyInputs[m.id];
      var k = km[m.id];
      input.classList.remove('invalid');
      if (!k) return;
      if (k.length !== 1) { input.classList.add('invalid'); valid = false; return; }
      var lk = k.toLowerCase();
      if (S.reserved[lk]) { input.classList.add('invalid'); valid = false; return; }
      if (used[lk]) {
        input.classList.add('invalid');
        keyInputs[used[lk]].classList.add('invalid');
        valid = false;
        return;
      }
      used[lk] = m.id;
    });
    return valid;
  }

  function post(action, data) {
    data = data || {};
    data.action = action;
    try {
      window.webkit.messageHandlers.trumpifySettings.postMessage(JSON.stringify(data));
    } catch (err) {
      document.getElementById('errors').textContent =
        'Bridge error: ' + err + ' (is the userContentController attached?)';
    }
  }

  document.getElementById('btn-save').addEventListener('click', function() {
    document.getElementById('errors').textContent = '';
    document.getElementById('status').textContent = '';
    endpointInput.classList.remove('invalid');
    modelInput.classList.remove('invalid');
    maxTokensInput.classList.remove('invalid');

    var advErrors = validateAdvanced(collectAdvanced());
    var keymapValid = validateLocal();
    if (advErrors.length > 0 || !keymapValid) {
      var msgs = advErrors.slice();
      if (!keymapValid) msgs.push('Please fix the highlighted shortcuts.');
      document.getElementById('errors').textContent = msgs.join('\\n');
      return;
    }
    post('save', { payload: {
      tts: collectTts(),
      keymap: collectKeymap(),
      disabled: collectDisabled(),
      advanced: collectAdvanced()
    } });
  });

  document.getElementById('btn-close').addEventListener('click', function() { post('close'); });

  document.getElementById('btn-reset').addEventListener('click', function() {
    voiceSelect.value = 'auto';
    document.getElementById('tts-rate').value = 0;
    document.getElementById('tts-volume').value = 0;
    document.getElementById('tts-pitch').value = 0;
    document.getElementById('tts-rate').dispatchEvent(new Event('input'));
    document.getElementById('tts-volume').dispatchEvent(new Event('input'));
    document.getElementById('tts-pitch').dispatchEvent(new Event('input'));
    document.getElementById('tts-fallback').checked = true;
    S.modes.forEach(function(m) {
      keyInputs[m.id].value = '';
      keyInputs[m.id].classList.remove('invalid');
      modeChecks[m.id].checked = true;
    });
    endpointInput.value = S.defaults.endpoint;
    modelInput.value = S.defaults.model;
    maxTokensInput.value = S.defaults.maxTokens;
    endpointInput.classList.remove('invalid');
    modelInput.classList.remove('invalid');
    maxTokensInput.classList.remove('invalid');
    document.getElementById('errors').textContent = '';
    document.getElementById('status').textContent = 'Reset to defaults (not saved yet)';
  });

  // ---- Lua bridge targets ----
  window.trumpifyPanel = {
    setVoices: function(voices) {
      var current = voiceSelect.value;
      voiceSelect.innerHTML = '';
      voiceSelect.appendChild(el('option', {value: 'auto'}, 'Automatisch (Sprache erkennen)'));
      voices.forEach(function(v) { voiceSelect.appendChild(el('option', {value: v}, v)); });
      if (current !== 'auto' && voices.indexOf(current) === -1) {
        voiceSelect.appendChild(el('option', {value: current}, current));
      }
      voiceSelect.value = current;
    },
    showErrors: function(errors) {
      document.getElementById('status').textContent = '';
      document.getElementById('errors').textContent = errors.join('\\n');
    },
    showStatus: function(text) {
      document.getElementById('errors').textContent = '';
      document.getElementById('status').textContent = text;
    }
  };

  post('ready');
})();
</script>
</body>
</html>]==]
end

function M.show()
    if M._webview then
        M.close()
    end

    local screen = hs.screen.mainScreen()
    local frame = screen:frame()
    local w, h = 720, 560
    local x = frame.x + (frame.w - w) / 2
    local y = frame.y + (frame.h - h) / 2

    local ok_uc, uc = pcall(hs.webview.usercontent.new, "trumpifySettings")
    if not ok_uc or not uc then
        ui.show_error("Settings panel: could not create user content controller")
        return
    end
    M._usercontent = uc

    uc:setCallback(function(msg)
        -- The message may arrive as a plain string or wrapped in a table
        -- with a "body" field, depending on the Hammerspoon version.
        local body = msg
        if type(msg) == "table" then body = msg.body end
        if type(body) == "string" and body ~= "" then
            local ok, decoded = pcall(hs.json.decode, body)
            if ok and type(decoded) == "table" then
                local ok_handle, err = pcall(_handle_message, decoded)
                if not ok_handle then
                    print("trumpify settings panel error: " .. tostring(err))
                end
            end
        end
    end)

    -- NOTE: the user content controller must be reachable at the position
    -- Hammerspoon expects: if arg 2 is a table it reads prefs from it and
    -- takes the controller from arg 3; otherwise it treats ARG 2 as the
    -- controller. Passing an explicit nil as arg 2 therefore fails - we must
    -- pass an EMPTY TABLE as preferences and the controller as arg 3.
    local ok_wv, webview_or_err = pcall(hs.webview.new, { x = x, y = y, w = w, h = h }, {}, uc)
    if not ok_wv or not webview_or_err then
        print("trumpify settings panel: webview creation failed: "
            .. tostring(webview_or_err))
        ui.show_error("Settings panel: could not create webview")
        return
    end
    local webview = webview_or_err
    M._webview = webview

    pcall(function() webview:windowStyle({ "titled", "closable", "resizable" }) end)
    pcall(function() webview:windowTitle("Trumpify Settings") end)
    pcall(function() webview:allowTextEntry(true) end)
    webview:html(M._build_html())
    webview:show()
    pcall(function() webview:bringToFront(true) end)

    local modal = hs.hotkey.modal.new()
    modal:bind({}, "escape", function()
        M.close()
    end)
    modal:enter()
    M._modal = modal
end

function M.close()
    if M._modal then
        pcall(function() M._modal:exit() end)
        M._modal = nil
    end
    if M._webview then
        pcall(function() M._webview:delete() end)
        M._webview = nil
    end
    M._usercontent = nil
end

return M