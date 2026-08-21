# Trumpify

A macOS text transformation tool powered by Hammerspoon and Claude. Highlight text anywhere, press a shortcut, and get it rewritten instantly — as Trump, a professional email, bullet points, and more.

## Prerequisites

- **macOS**
- **[Hammerspoon](https://www.hammerspoon.org/)** — install via `brew install --cask hammerspoon` or from the website
- **HAI Proxy** — running locally (`hai proxy start`)
- **edge-tts** (optional, for high-quality text-to-speech) — `pip install edge-tts` or `pipx install edge-tts`. Without it, TTS falls back to the built-in macOS voice.

## Installation

1. **Clone this repo:**

   ```bash
   git clone https://github.com/YOUR_USER/Trumpify.git ~/Documents/GitHub/Trumpify
   ```

2. **Configure your API key** using one of these methods:
   - **Config file**: Copy `config.example.json` to `~/.config/trumpify/config.json` and add your key:
     ```json
     {
         "apiKey": "your-api-key-here"
     }
     ```
   - **.env file**: Create `.env` in the project root:
     ```
     HAIPROXY_API_KEY=your-api-key-here
     ```
   - **Environment variable**: Set `HAIPROXY_API_KEY` globally.

3. **Configure Hammerspoon** — add this to `~/.hammerspoon/init.lua` (create the file if it doesn't exist):

   ```lua
   -- Enable CLI access (optional)
   require("hs.ipc")

   -- Load Trumpify
   package.path = package.path
       .. ";/Users/YOUR_USER/Documents/GitHub/Trumpify/?.lua"
       .. ";/Users/YOUR_USER/Documents/GitHub/Trumpify/?/init.lua"

   require("trumpify")
   ```

   Replace `YOUR_USER` with your macOS username.

4. **Grant Accessibility permissions** to Hammerspoon:
   System Settings → Privacy & Security → Accessibility → enable Hammerspoon

5. **Start HAI Proxy:**

   ```bash
   hai proxy start
   ```

6. **Reload Hammerspoon** — click the Hammerspoon menu bar icon → Reload Config, or press `⌃⌥R`.

   You should see a **"Trumpify loaded!"** notification.

## Shortcuts

All shortcuts use **Ctrl + Option** (`⌃⌥`) as the base modifier.

| Shortcut | Mode | What it does |
|----------|------|-------------|
| `⌃⌥T` | Trumpify | Rewrites in Trump's voice with rambling tangents |
| `⌃⌥E` | Email | Turns into a professional email |
| `⌃⌥S` | Summary | Summarizes text (shown in a dialog — click OK to dismiss) |
| `⌃⌥F` | Formal | Rewrites in formal/academic tone |
| `⌃⌥C` | Casual | Rewrites in friendly casual tone |
| `⌃⌥B` | Bullets | Converts to bullet points |
| `⌃⌥D` | Condense | Shortest possible version |
| `⌃⌥L` | LinkedIn | Rewrites as a viral LinkedIn post |
| `⌃⌥G` | Fix Grammar | Fixes spelling and grammar, keeps the tone |
| `⌃⌥A` | Reply | Auto-generates a reply matching the message style |
| `⌃⌥Q` | Reply (guided) | Writes a reply using your own talking points |
| `⌃⌥M` | Read Aloud | Reads the selected text aloud (Edge neural voice) |
| `⌃⌥Y` | Summarize & Speak | Summarizes and reads the summary aloud |
| `⌃⌥.` | Stop TTS | Stops current speech playback |
| `⌃⌥Space` | Chooser | Searchable menu of all modes + Settings |
| `⌃⌥R` | Reload | Reloads Hammerspoon config |

### Copy-only mode

Hold **Shift** with any shortcut to copy the result to your clipboard **without pasting** it. For example:

- `⌃⌥⇧T` — Trumpify and copy to clipboard
- `⌃⌥⇧E` — Email and copy to clipboard

## Text-to-Speech

Read Aloud and Summarize & Speak use [edge-tts](https://github.com/rany2/edge-tts) (Microsoft Edge neural voices) for natural speech:

- **Automatic language detection** — German texts are read with a German voice, English with an English one
- **Long text support** — texts are split into chunks at sentence boundaries and played back in a pipeline (playback starts while later chunks are still generating)
- **Stop anytime** — press `⌃⌥.` while speaking
- **Fallback** — if edge-tts is unavailable or fails, Trumpify falls back to the built-in macOS voice (configurable)

Voice, rate, volume and pitch can be changed in the Settings panel.

## Settings Panel

Open via the chooser (`⌃⌥Space` → **Settings**):

- **Text-to-Speech**: voice selection (with test button), rate/volume/pitch sliders, macOS fallback toggle
- **Shortcuts**: per-mode hotkey editing with live collision validation
- **Modes**: enable/disable individual modes
- **Advanced**: API endpoint, model, max tokens
- **Reset to Defaults**: restores all settings (applied after clicking Save)

Changes take effect immediately — no Hammerspoon reload required.

## Usage

1. **Highlight text** in any app
2. **Press a shortcut** (e.g., `⌃⌥T`)
3. A **"Processing..."** indicator appears
4. The transformed text either **replaces your selection** or is **shown in a dialog** (Summary mode)

## Configuration

Trumpify supports a JSON config file. It looks in these locations (in order):

1. `~/.config/trumpify/config.json`
2. `<project-root>/config.json`

See `config.example.json` for all options:

```json
{
    "endpoint": "http://localhost:6655/anthropic/v1/messages",
    "model": "anthropic--claude-4.6-opus",
    "maxTokens": 4096,
    "apiKey": "your-api-key",
    "keymap": {
        "trumpify": "t",
        "email": "e"
    },
    "tts": {
        "voice": null,
        "rate": "+0%",
        "volume": "+0%",
        "pitch": "+0Hz",
        "fallback": true
    },
    "disabledModes": []
}
```

- `keymap` — customize keyboard shortcuts for any mode (lowercase letters)
- `tts` — text-to-speech settings; `voice: null` enables automatic language detection
- `disabledModes` — mode IDs listed here are hidden from hotkeys and the chooser

All of these can also be edited in the Settings panel, which writes back to the project `config.json` (your `apiKey` is never touched by the panel).

## Adding a new mode

### Method 1: External prompt file (recommended)

Create a new `.lua` file in the `prompts/` directory:

```lua
-- prompts/mymode.lua
return {
    name = "My Mode",
    description = "Short description for the chooser menu",
    key = "m",                -- the letter after ⌃⌥
    paste_back = true,        -- false = show in dialog instead
    needs_input = false,      -- true = prompt for additional input first
    input_prompt = nil,       -- shown if needs_input is true
    system = [[Your system prompt here. Only output the result, nothing else.]],
}
```

Reload with `⌃⌥R` and the new mode is ready — including automatic Shift-copy support and chooser menu entry.

### Method 2: Embedded prompts.lua

Edit `trumpify/prompts.lua` (used as fallback if no `prompts/` directory exists):

### Method 3: Chooser-only mode (no hotkey)

Set `key = nil` to register the mode only in the chooser menu, without a dedicated hotkey.

## Project Structure

```
Trumpify/
├── trumpify/
│   ├── init.lua            Entry point — loads and initializes all modules
│   ├── constants.lua       Centralized values, paths, and timing
│   ├── config.lua          JSON config loader/saver with .env fallback
│   ├── api.lua             HAI Proxy HTTP client with retry & sanitization
│   ├── ui.lua              UI helpers: alerts, dialogs, scrollable webview
│   ├── selection.lua       Text capture with clipboard fallback + restore
│   ├── transformer.lua     Orchestrates capture → API → paste/copy/dialog
│   ├── hotkeys.lua         Hotkey registration and chooser management
│   ├── history.lua         Ring buffer of recent transformations
│   ├── prompt_loader.lua   Dynamic prompt loader with validation + fallback
│   ├── tts.lua             Text-to-speech via edge-tts with chunked playback
│   ├── settings_panel.lua  Webview-based settings UI (voice/keys/modes/API)
│   └── prompts.lua         Embedded prompt definitions (fallback)
├── prompts/                External prompt files (one .lua per mode)
│   ├── trumpify.lua
│   ├── email.lua
│   └── ...
├── docs/adr/               Architecture Decision Records
├── config.example.json     Example configuration
├── .luacheckrc             Lua static analysis config
└── test/                   Unit tests (busted)
```

## Development

```bash
# Install dev dependencies
brew install luarocks
luarocks install busted

# Run tests
cd test && busted .

# Lint
luacheck trumpify/ prompts/
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| "API key not configured" | No API key found | Add key to config.json, .env, or env var |
| "HAI Proxy not running" | HAI Proxy is down | Run `hai proxy start` |
| "Connection failed" | Network or proxy issue | Check `http://localhost:6655` is reachable |
| "Invalid API key" | Wrong key | Verify key in config.json or .env |
| No text captured | No accessibility permission | Enable Hammerspoon in System Settings → Privacy → Accessibility |
