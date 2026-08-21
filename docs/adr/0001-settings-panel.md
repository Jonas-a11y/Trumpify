# ADR 0001: Settings Panel

Date: 2026-08-21

## Status

Accepted

## Context

Trumpify has accumulated user-facing options that were previously only
configurable by manually editing files:

- TTS voice/rate/volume/pitch (stored in `hs.settings`, inconsistent with the
  rest of the app which uses `config.json`)
- Per-mode keyboard shortcuts (`keymap` in `config.json`)
- Mode enable/disable (no mechanism existed)

Editing JSON by hand is error-prone (invalid keys, collisions with reserved
hotkeys) and requires a Hammerspoon reload to take effect. The number of
options will keep growing, so a proper UI was needed.

Constraints:

- Hammerspoon offers no native settings UI; options are `hs.dialog` (too
  limited), `hs.canvas` (complex), and `hs.webview` (HTML-based).
- `config.lua` was read-only; a write path had to be added.
- The project config file contains unmanaged keys (`apiKey`, comments) that
  must not be lost when the panel writes settings.

## Decision

1. **UI**: Build the settings panel as an `hs.webview` window using
   `hs.webview.usercontent` as the JS-to-Lua bridge
   (`window.webkit.messageHandlers.trumpifySettings.postMessage`). HTML gives
   us dropdowns, sliders and checkboxes without extra dependencies, and the
   webview pattern already existed in `ui.lua`.

2. **Storage**: Settings are written to the project `config.json` via new
   `config.set()` / `config.save()` functions. `save()` uses a merge strategy:
   it reads the existing file and overwrites only the managed keys
   (`tts`, `keymap`, `disabledModes`, `endpoint`, `model`, `maxTokens`),
   preserving everything else (in particular `apiKey` and `_comment`
   documentation keys). A pure-Lua JSON encoder fallback keeps saving
   functional even if `hs.json` is unavailable.

3. **TTS settings migration**: Voice/rate/volume/pitch/fallback moved from
   `hs.settings` into the `tts` block of `config.json`. Old `hs.settings`
   values are ignored (no migration code needed).

4. **Live apply**: After saving, the panel invokes an injected `on_apply`
   callback (wired in `init.lua`) that re-initializes TTS, re-registers all
   hotkeys and refreshes the chooser choices - no Hammerspoon reload needed.

5. **Circular dependency avoidance**: `settings_panel` needs `hotkeys`
   (reserved-key validation, chooser refresh) while the chooser callback needs
   `settings_panel`. This is resolved by lazy `require` inside the chooser
   callback closure plus dependency injection for the apply callback.

6. **Disabled modes**: `prompt_loader.get_modes()` / `get_chooser_choices()`
   filter out IDs listed in `config.disabledModes`; `get_all_modes()` returns
   the unfiltered set for the panel itself.

## Consequences

- Users can configure voice, shortcuts and modes without touching files or
  reloading.
- Shortcut inputs are validated twice (client-side JS for instant feedback,
  Lua-side on save) against reserved keys and collisions.
- Writing to the project `config.json` means settings are tied to the project
  checkout; users who sync dotfiles separately will not pick up panel changes.
- The panel depends on `edge-tts --list-voices` for the full voice list;
  offline it falls back to a hardcoded list of common DE/EN voices.
- Busted tests cover keymap validation, config save round-trips and mode
  filtering; they run wherever busted is available.
