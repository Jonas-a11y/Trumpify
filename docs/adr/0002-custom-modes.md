# ADR 0002: User-defined custom modes stored as JSON

Date: 2026-08-24
Status: Accepted

## Context

Trumpify ships with a fixed set of transformation modes defined in `prompts/*.lua`.
Users who want their own transformations currently have to write Lua files by hand.
We want to let users create modes through the settings panel (name, description,
hotkey, system prompt) without touching code.

Two storage options were considered:

1. **Lua files** in `~/.config/trumpify/prompts/` — consistent with the existing
   `prompts/` mechanism (`prompt_loader` scans directories of `.lua` mode tables),
   but generating valid Lua from a webview form requires escaping arbitrary user
   input into string literals, which is error-prone.
2. **JSON** in `~/.config/trumpify/custom_modes.json` — trivially safe to write
   from the panel (a JSON encoder handles escaping), and the data shape of a mode
   (flat table with string fields) maps directly onto JSON objects.

## Decision

Custom modes are stored as a JSON array in
`~/.config/trumpify/custom_modes.json` (path via
`constants.CUSTOM_MODES_FILE_NAME`). A new module `trumpify/custom_modes.lua`
owns validation, id assignment, JSON encoding/decoding (hs.json, dkjson fallback)
and persistence. `prompt_loader.init()` merges the loaded list on top of the
built-ins using IDs prefixed with `custom_`, reusing the same conflict rules as
built-in modes (unique name, optional single-character key). Conflicting or
invalid entries are skipped and reported as load issues; they never break loading
of other modes.

The settings panel sends the authoritative full custom list on every save; the
file is rewritten atomically per save. Hotkey overrides for custom modes work
through the existing `keymap` mechanism (keyed by `custom_<id>`), identical to
built-in modes.

## Consequences

- Users can add/remove/edit modes live; saving re-runs `prompt_loader.init()`
  and re-registers hotkeys without a Hammerspoon reload.
- Renaming a custom mode changes its slug ID and therefore drops any hotkey
  override or disabled-state entry keyed under the old ID. Acceptable for now;
  stable UUIDs would add complexity for little gain.
- Writing Lua prompt files remains available for power users (comments, dynamic
  prompts); both mechanisms coexist.
- Testability required pure logic (validate/merge/ids) separate from IO, so the
  module keeps hs dependencies out of those functions.
