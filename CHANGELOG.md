# Changelog

All notable changes to Trumpify will be documented in this file.

## [Unreleased]

### Added
- Custom Modes: create, edit and delete user-defined transformations directly in the settings panel (name, description, hotkey, system prompt); stored in `~/.config/trumpify/custom_modes.json`, live-reloaded without Hammerspoon restart
- Translate mode (`⌃⌥V`): auto language detection (German → English, everything else → German); target language configurable in the settings panel, mode can be disabled like any other
- API key can be entered in the settings panel (Advanced section, masked display showing only the last 4 characters)
- Onboarding hint when no API key is configured, pointing at the settings panel
- `.env.example` template for API key configuration

### Changed
- Replaced the SAP-specific local proxy with an OpenAI-compatible API client
- OpenRouter is now the default provider and uses Bearer authentication
- Added `OPENROUTER_API_KEY` and `OPENAI_API_KEY` environment-variable support
- Documented how selected text is sent to the configured provider
- Added bounded exponential backoff with jitter for connection errors, rate limits and temporary server failures
- Settings are now written to `~/.config/trumpify/config.json` instead of the project-level `config.json` (keeps secrets out of the repository directory)
- History ring buffer extended from 5 to 20 entries
- Hotkey collision validation now checks all effective keys (overrides and per-mode defaults), not just overrides
- README: replaced placeholder install paths with a dynamic snippet; documented new features and config options

### Added
- History browser (`⌃⌥H` or chooser entry): browse recent transformations and copy, paste or read them aloud
- Streaming TTS playback via `ffplay` + named pipe: audio starts while text is still being generated (falls back to file-based playback without ffmpeg)
- Settings panel (accessible via chooser entry "Settings"):
  - TTS voice/rate/volume/pitch configuration with voice test button
  - Per-mode keyboard shortcut editing with live collision validation
  - Mode enable/disable toggles
  - Advanced section: API endpoint, model, max tokens
  - Reset to defaults
- TTS module (`tts.lua`) using Microsoft Edge neural voices via `edge-tts`
- "Read Aloud" mode (`⌃⌥M`) - reads selected text aloud
- "Summarize & Speak" mode (`⌃⌥Y`) - summarizes text and reads the summary aloud
- "Stop TTS" hotkey (`⌃⌥.`) - stops current speech
- Chunked playback for long texts: split at sentence boundaries, pipelined generation/playback
- Lightweight DE/EN language detection (function-word scoring + umlaut bonus)
- Cleanup of orphaned `/tmp/trumpify_tts_*.mp3` files on startup
- Visible speaking status with stop hint; TTS errors shown when fallback is disabled
- Config write support: `config.set()` / `config.save()` (merge-based, preserves unmanaged keys)
- `disabledModes` config option to hide modes from hotkeys and chooser
- Voice list loaded dynamically from `edge-tts --list-voices` (with hardcoded fallback)

### Fixed
- Settings panel JS bridge: user content controller must be passed as third argument to `hs.webview.new` (passing it in the preferences table is silently ignored); explicit `nil` as preferences argument breaks webview creation
- Shortcut keys are normalized to lowercase when saved (panel displays uppercase, `hs.hotkey.bind` expects lowercase)
- Chooser menu now shows the effective key from `keymap` overrides instead of the mode default

### Changed
- TTS switched from macOS `hs.speech` to `edge-tts` for higher voice quality
- TTS settings migrated from `hs.settings` to `config.json` (`tts` block)
- TTS fallback to `hs.speech` is now configurable (`tts.fallback`); failures are shown as errors when disabled

## [2.0.0] - 2026-06-25

### Added
- Dynamic project path resolution - no more hardcoded paths
- JSON config file support (`~/.config/trumpify/config.json` or project root)
- Configurable keyboard shortcuts via `keymap` in config
- External prompt files in `prompts/` directory - add new modes without editing Lua
- Scrollable result dialog for long text (uses `hs.webview`)
- Result history buffer (last 5 transformations)
- Input sanitization (null bytes, control chars) before API call
- Retry logic with exponential backoff for network and rate-limit errors
- Better error diagnostics (401, 429, connection refused)
- Accessibility permission check on startup
- Robust clipboard fallback with retry loop and clipboard restoration
- Paste verification with automatic retry
- UI utilities module (`ui.lua`) with reusable alert/dialog functions
- Hotkey manager module (`hotkeys.lua`) for centralized key binding
- Transformer module (`transformer.lua`) for clean transformation pipeline
- Config module (`config.lua`) for loading settings from JSON + .env fallback
- Constants module (`constants.lua`) for all centralized values
- History module (`history.lua`) for tracking transformations
- Prompt loader module (`prompt_loader.lua`) with validation and fallback
- CI workflow (GitHub Actions) for linting and testing
- Luacheck configuration for static analysis
- Example config file (`config.example.json`)
- Unit test setup with busted
- CHANGELOG.md

### Changed
- Complete architecture refactor from single-file to modular structure
- `init.lua` is now a thin entry point (8 lines)
- Selection module: clipboard restoration after fallback, retry loops
- API module: dynamic endpoint/model from config, error type detection
- All old keys and shortcuts remain unchanged

### Backward Compatibility
- The old `trumpify/prompts.lua` is preserved as embedded fallback (only used if `prompts/` directory is missing)
- Old `.env` file still works
- All hotkeys (`⌃⌥T`, `⌃⌥E`, etc.) remain the same
