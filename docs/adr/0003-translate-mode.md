# ADR 0003: Translate mode with configurable target language

Date: 2026-08-24
Status: Accepted

## Context

Translation was requested as a new transformation mode. Options ranged from a
fixed German↔English mode to per-invocation language selection.

The primary use case is translating between German and English. Requiring the
user to pick a target language on every invocation adds friction; hard-coding
German↔English removes flexibility for other languages.

## Decision

A single `Translate` mode (`prompts/translate.lua`, hotkey `⌃⌥V`) whose system
prompt contains a `{target_language}` placeholder. `transformer.build_system()`
resolves it at call time:

- If `config.translate.target` is set to a non-empty value, that language is
  used verbatim (e.g. "French").
- Otherwise the placeholder resolves to an auto rule: *German if the text is
  German, otherwise English* — the model performs source-language detection,
  so no separate detection step or API call is needed.

The mode can be disabled like any other via the settings panel
(`disabledModes`). The target language is editable in the panel's Advanced
section; leaving it empty restores auto behavior.

## Consequences

- One mode covers the common case and arbitrary configured targets without
  extra UI complexity.
- Language detection quality depends on the model, but this matches how all
  other modes already rely on the model's judgment.
- The placeholder mechanism (`build_system`) is generic; future modes can use
  config-driven prompt interpolation without new plumbing.
- The default hotkey `v` was chosen because `t` is taken by Trumpify.
