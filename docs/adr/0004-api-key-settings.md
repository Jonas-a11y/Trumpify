# ADR 0004: API key management via the settings panel

Date: 2026-08-24
Status: Accepted

## Context

Previously the API key had to be configured by hand in `config.json`, `.env` or
an environment variable, and the settings panel deliberately never touched it
(`apiKey` was excluded from the managed keys). This made onboarding cumbersome.

Security constraints:

- The key must never end up in the git repository.
- The panel displays whatever is in its state; showing a raw key would leak it
  into process memory of the webview and screen recordings.

## Decision

1. The settings panel gains a password-type **API Key** field under Advanced.
   The current key is only shown masked (`••••<last 4>`); typing a new value
   replaces the stored one, leaving the field unchanged keeps it.
2. `apiKey` becomes a managed config key and the panel now saves all settings
   to the **user config file** (`~/.config/trumpify/config.json`) instead of
   the project-level `config.json`. The project file remains a template/
   fallback location and stays outside the panel's write path.
3. The existing load chain is unchanged: user config → project config → `.env`
   → environment variable (first hit wins for the key).
4. On startup without a key, Trumpify shows an onboarding hint pointing at the
   settings panel instead of only listing checked locations.
5. Additionally verified that neither `config.json` nor `.env` were ever
   committed (both are gitignored since the initial commit).

## Consequences

- New users can complete setup entirely inside the app.
- The key lives outside the repository directory by default; even a careless
  commit cannot expose it.
- Saving settings writes the resolved key (including one loaded from `.env`)
  into the user config file. This consolidates configuration but means the key
  may exist in two places afterwards; the load order makes this deterministic.
- The masked display leaks at most the last 4 characters, consistent with
  common practice.
