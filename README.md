# Trumpify

A macOS text transformation tool powered by Hammerspoon and Claude. Highlight text anywhere, press a shortcut, and get it rewritten instantly — as Trump, a professional email, bullet points, and more.

## Prerequisites

- **macOS**
- **[Hammerspoon](https://www.hammerspoon.org/)** — install via `brew install --cask hammerspoon` or from the website
- **HAI Proxy** — running locally (`hai proxy start`)

## Installation

1. **Clone this repo:**

   ```bash
   git clone https://github.com/YOUR_USER/Trumpify.git ~/Documents/GitHub/Trumpify
   ```

2. **Add your API key** to `.env` in the project root:

   ```
   HAIPROXY_API_KEY=your-api-key-here
   ```

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
| `⌃⌥Space` | Chooser | Searchable menu of all modes |
| `⌃⌥R` | Reload | Reloads Hammerspoon config |

### Copy-only mode

Hold **Shift** with any shortcut to copy the result to your clipboard **without pasting** it. For example:

- `⌃⌥⇧T` — Trumpify and copy to clipboard
- `⌃⌥⇧E` — Email and copy to clipboard

## Usage

1. **Highlight text** in any app
2. **Press a shortcut** (e.g., `⌃⌥T`)
3. A **"Processing..."** indicator appears
4. The transformed text either **replaces your selection** or is **shown in a dialog** (Summary mode)

## Configuration

The model and endpoint are configured in `trumpify/api.lua`:

```lua
M.config = {
    endpoint = "http://localhost:6655/anthropic/v1/messages",
    model = "anthropic--claude-4.6-opus",
    maxTokens = 4096,
}
```

## Adding a new mode

Edit `trumpify/prompts.lua` and add an entry to `M.modes`:

```lua
mymode = {
    name = "My Mode",
    description = "Short description for the chooser menu",
    key = "m",                -- the letter after ⌃⌥
    paste_back = true,        -- false = show in dialog instead
    system = [[Your system prompt here. Only output the result, nothing else.]],
},
```

Reload with `⌃⌥R` and the new mode is ready — including automatic Shift-copy support and chooser menu entry.

## Project Structure

```
trumpify/
  init.lua        Main module — hotkey bindings, chooser, UI feedback
  api.lua         HAI Proxy HTTP client (Anthropic Messages API)
  selection.lua   Text capture (accessibility API + Cmd+C fallback) and paste-back
  prompts.lua     All transformation modes and their system prompts
.env              HAI Proxy API key
```
