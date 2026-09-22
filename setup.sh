#!/bin/bash

set -euo pipefail
umask 077

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
CONFIG_DIR="$HOME/.config/trumpify"
CONFIG_PATH="$CONFIG_DIR/config.json"
HAMMERSPOON_DIR="$HOME/.hammerspoon"
HAMMERSPOON_INIT="$HAMMERSPOON_DIR/init.lua"
BEGIN_MARKER="-- >>> Trumpify setup >>>"
END_MARKER="-- <<< Trumpify setup <<<"

INTERACTIVE=1
PROVIDER=""
ENDPOINT=""
MODEL=""
MAX_TOKENS=4096
API_KEY_ENV="TRUMPIFY_API_KEY"
SKIP_API_TEST=0
SKIP_HAMMERSPOON_CHECK=0
NO_RELOAD=0

if [[ -t 1 ]]; then
    BOLD=$'\033[1m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    RESET=$'\033[0m'
else
    BOLD=""
    GREEN=""
    YELLOW=""
    RESET=""
fi

info() { printf '%s\n' "$*"; }
success() { printf '%s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s!%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Trumpify setup wizard

Usage:
  ./setup.sh
  TRUMPIFY_API_KEY=... ./setup.sh --non-interactive [options]

Options:
  --non-interactive            Do not prompt; read the key from an environment variable
  --provider NAME              openrouter (default) or custom
  --endpoint URL               API base URL or full /chat/completions URL
  --model ID                   Provider model ID
  --max-tokens NUMBER          Maximum output tokens (default: 4096)
  --api-key-env NAME           Environment variable containing the key
                               (default: TRUMPIFY_API_KEY)
  --skip-api-test              Write configuration without testing the endpoint
  --no-reload                  Do not reload or launch Hammerspoon
  --skip-hammerspoon-check     Skip dependency check (mainly for automation)
  -h, --help                   Show this help

The API key is never accepted as a command-line argument, so it does not appear
in shell history or process listings.
EOF
}

need_value() {
    [[ $# -ge 2 && -n $2 ]] || die "$1 requires a value"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --non-interactive) INTERACTIVE=0; shift ;;
        --provider) need_value "$1" "${2-}"; PROVIDER=$2; shift 2 ;;
        --endpoint) need_value "$1" "${2-}"; ENDPOINT=$2; shift 2 ;;
        --model) need_value "$1" "${2-}"; MODEL=$2; shift 2 ;;
        --max-tokens) need_value "$1" "${2-}"; MAX_TOKENS=$2; shift 2 ;;
        --api-key-env) need_value "$1" "${2-}"; API_KEY_ENV=$2; shift 2 ;;
        --skip-api-test) SKIP_API_TEST=1; shift ;;
        --no-reload) NO_RELOAD=1; shift ;;
        --skip-hammerspoon-check) SKIP_HAMMERSPOON_CHECK=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
done

[[ $MAX_TOKENS =~ ^[0-9]+$ ]] || die "--max-tokens must be a positive integer"
(( MAX_TOKENS > 0 )) || die "--max-tokens must be greater than zero"

if [[ $(uname -s) != "Darwin" && ${TRUMPIFY_SETUP_ALLOW_NON_MACOS:-0} != "1" ]]; then
    die "Trumpify and this wizard require macOS"
fi

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v osascript >/dev/null 2>&1 || die "osascript is required"

read_config_value() {
    local key=$1
    [[ -f $CONFIG_PATH ]] || return 0
    WIZARD_CONFIG_PATH=$CONFIG_PATH WIZARD_CONFIG_KEY=$key /usr/bin/osascript -l JavaScript <<'JXA' 2>/dev/null || true
ObjC.import('Foundation')
function env(name) {
  const value = $.NSProcessInfo.processInfo.environment.objectForKey($(name))
  return value ? ObjC.unwrap(value) : ''
}
function run() {
  const path = env('WIZARD_CONFIG_PATH')
  const key = env('WIZARD_CONFIG_KEY')
  const contents = $.NSString.stringWithContentsOfFileEncodingError(
    $(path), $.NSUTF8StringEncoding, null
  )
  if (!contents) return ''
  try {
    const config = JSON.parse(ObjC.unwrap(contents))
    const value = config[key]
    return value === undefined || value === null ? '' : String(value)
  } catch (_) {
    return ''
  }
}
JXA
}

prompt_value() {
    local label=$1
    local default_value=$2
    local value
    read -r -p "$label [$default_value]: " value
    printf '%s' "${value:-$default_value}"
}

confirm() {
    local prompt=$1
    local answer
    read -r -p "$prompt [Y/n]: " answer
    [[ -z $answer || $answer == [Yy] || $answer == [Yy][Ee][Ss] ]]
}

ensure_hammerspoon() {
    (( SKIP_HAMMERSPOON_CHECK == 1 )) && return 0
    if command -v hs >/dev/null 2>&1 || [[ -d /Applications/Hammerspoon.app ]]; then
        success "Hammerspoon found"
        return 0
    fi

    if (( INTERACTIVE == 1 )) && command -v brew >/dev/null 2>&1; then
        if confirm "Hammerspoon is missing. Install it with Homebrew?"; then
            brew install --cask hammerspoon
            success "Hammerspoon installed"
            return 0
        fi
    fi

    if (( INTERACTIVE == 1 )); then
        open https://www.hammerspoon.org/ >/dev/null 2>&1 || true
    fi
    die "Hammerspoon is required. Install it and run the wizard again."
}

normalize_endpoint() {
    local value=${1%/}
    [[ $value == http://* || $value == https://* ]] || die "Endpoint must start with http:// or https://"
    case $value in
        */chat/completions) printf '%s' "$value" ;;
        *) printf '%s/chat/completions' "$value" ;;
    esac
}

choose_provider() {
    local existing_endpoint
    local existing_model
    existing_endpoint=$(read_config_value endpoint)
    existing_model=$(read_config_value model)

    if [[ -z $PROVIDER ]]; then
        if (( INTERACTIVE == 1 )); then
            info ""
            info "Choose an API provider:"
            info "  1) OpenRouter (recommended)"
            info "  2) Custom OpenAI-compatible endpoint"
            local choice
            read -r -p "Selection [1]: " choice
            case ${choice:-1} in
                1) PROVIDER=openrouter ;;
                2) PROVIDER=custom ;;
                *) die "Invalid provider selection" ;;
            esac
        else
            PROVIDER=openrouter
        fi
    fi

    case $PROVIDER in
        openrouter)
            local default_endpoint="https://openrouter.ai/api/v1/chat/completions"
            local default_model="openai/gpt-4.1-mini"
            [[ $existing_endpoint == *openrouter.ai* ]] && default_endpoint=$existing_endpoint
            [[ $existing_endpoint == *openrouter.ai* && -n $existing_model ]] && default_model=$existing_model
            if (( INTERACTIVE == 1 )); then
                ENDPOINT=${ENDPOINT:-$(prompt_value "Endpoint" "$default_endpoint")}
                MODEL=${MODEL:-$(prompt_value "Model" "$default_model")}
            else
                ENDPOINT=${ENDPOINT:-$default_endpoint}
                MODEL=${MODEL:-$default_model}
            fi
            ;;
        custom)
            local default_endpoint=${existing_endpoint:-"http://localhost:1234/v1"}
            local default_model=${existing_model:-"gpt-4.1-mini"}
            if (( INTERACTIVE == 1 )); then
                ENDPOINT=${ENDPOINT:-$(prompt_value "Endpoint or base URL" "$default_endpoint")}
                MODEL=${MODEL:-$(prompt_value "Model" "$default_model")}
            else
                [[ -n $ENDPOINT ]] || die "--endpoint is required for a custom provider"
                [[ -n $MODEL ]] || die "--model is required for a custom provider"
            fi
            ;;
        *) die "Provider must be 'openrouter' or 'custom'" ;;
    esac

    ENDPOINT=$(normalize_endpoint "$ENDPOINT")
    [[ -n $MODEL ]] || die "Model must not be empty"
}

read_api_key() {
    local existing_key
    existing_key=$(read_config_value apiKey)

    if (( INTERACTIVE == 1 )); then
        local hint=""
        if [[ -n $existing_key ]]; then
            hint=" (Enter keeps the existing key ending in ${existing_key: -4})"
        fi
        local entered_key
        read -r -s -p "API key$hint: " entered_key
        printf '\n'
        API_KEY=${entered_key:-$existing_key}
    else
        API_KEY=${!API_KEY_ENV:-$existing_key}
    fi

    [[ -n ${API_KEY:-} ]] || die "No API key supplied. Set $API_KEY_ENV or run interactively."
}

make_api_payload() {
    local path=$1
    WIZARD_PAYLOAD_PATH=$path WIZARD_MODEL=$MODEL WIZARD_MAX_TOKENS=$MAX_TOKENS \
        /usr/bin/osascript -l JavaScript <<'JXA' >/dev/null
ObjC.import('Foundation')
function env(name) {
  const value = $.NSProcessInfo.processInfo.environment.objectForKey($(name))
  return value ? ObjC.unwrap(value) : ''
}
const model = env('WIZARD_MODEL')
const payload = {
  model: model,
  messages: [{ role: 'user', content: 'Reply with exactly OK' }]
}
if (model.toLowerCase().includes('gpt-5')) {
  payload.max_completion_tokens = Number(env('WIZARD_MAX_TOKENS'))
} else {
  payload.max_tokens = Number(env('WIZARD_MAX_TOKENS'))
}
const text = $(JSON.stringify(payload))
const ok = text.writeToFileAtomicallyEncodingError(
  $(env('WIZARD_PAYLOAD_PATH')), true, $.NSUTF8StringEncoding, null
)
if (!ok) throw new Error('Could not write API test payload')
JXA
}

parse_api_response() {
    local path=$1
    WIZARD_RESPONSE_PATH=$path /usr/bin/osascript -l JavaScript <<'JXA' 2>/dev/null || true
ObjC.import('Foundation')
function env(name) {
  const value = $.NSProcessInfo.processInfo.environment.objectForKey($(name))
  return value ? ObjC.unwrap(value) : ''
}
function run() {
  const contents = $.NSString.stringWithContentsOfFileEncodingError(
    $(env('WIZARD_RESPONSE_PATH')), $.NSUTF8StringEncoding, null
  )
  if (!contents) return 'Could not read API response'
  try {
    const response = JSON.parse(ObjC.unwrap(contents))
    if (response.choices && response.choices[0] && response.choices[0].message) return 'OK'
    if (response.error && response.error.message) return String(response.error.message)
    return 'Response did not contain choices[0].message'
  } catch (_) {
    return 'API returned invalid JSON'
  }
}
JXA
}

test_api_connection() {
    (( SKIP_API_TEST == 1 )) && { warn "API test skipped"; return 0; }

    local work_dir
    work_dir=$(mktemp -d "${TMPDIR:-/tmp}/trumpify-setup.XXXXXX")
    local payload_file="$work_dir/payload.json"
    local response_file="$work_dir/response.json"
    local header_file="$work_dir/headers.txt"
    chmod 700 "$work_dir"
    printf 'Authorization: Bearer %s\nContent-Type: application/json\n' "$API_KEY" > "$header_file"
    chmod 600 "$header_file"
    make_api_payload "$payload_file"

    info "Testing API connection..."
    local http_code
    if ! http_code=$(curl --silent --show-error --max-time 30 \
        --output "$response_file" --write-out '%{http_code}' \
        --request POST --header "@$header_file" --data-binary "@$payload_file" \
        "$ENDPOINT"); then
        rm -rf "$work_dir"
        die "Could not connect to the configured endpoint"
    fi

    local response_status
    response_status=$(parse_api_response "$response_file")
    rm -rf "$work_dir"

    if [[ $http_code != 2* || $response_status != "OK" ]]; then
        die "API test failed (HTTP $http_code): $response_status"
    fi
    success "API connection works with model $MODEL"
}

write_config() {
    mkdir -p "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR"
    WIZARD_CONFIG_PATH=$CONFIG_PATH WIZARD_ENDPOINT=$ENDPOINT WIZARD_MODEL=$MODEL \
        WIZARD_MAX_TOKENS=$MAX_TOKENS WIZARD_API_KEY=$API_KEY \
        /usr/bin/osascript -l JavaScript <<'JXA' >/dev/null
ObjC.import('Foundation')
function env(name) {
  const value = $.NSProcessInfo.processInfo.environment.objectForKey($(name))
  return value ? ObjC.unwrap(value) : ''
}
const path = env('WIZARD_CONFIG_PATH')
let config = {}
const existing = $.NSString.stringWithContentsOfFileEncodingError(
  $(path), $.NSUTF8StringEncoding, null
)
if (existing) {
  try { config = JSON.parse(ObjC.unwrap(existing)) } catch (_) { config = {} }
}
config.endpoint = env('WIZARD_ENDPOINT')
config.model = env('WIZARD_MODEL')
config.maxTokens = Number(env('WIZARD_MAX_TOKENS'))
config.apiKey = env('WIZARD_API_KEY')
const text = $(JSON.stringify(config, null, 2) + '\n')
const ok = text.writeToFileAtomicallyEncodingError(
  $(path), true, $.NSUTF8StringEncoding, null
)
if (!ok) throw new Error('Could not write Trumpify configuration')
JXA
    chmod 600 "$CONFIG_PATH"
    success "Configuration saved to $CONFIG_PATH"
}

lua_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

configure_hammerspoon() {
    mkdir -p "$HAMMERSPOON_DIR"
    touch "$HAMMERSPOON_INIT"

    if ! grep -Fq -- "$BEGIN_MARKER" "$HAMMERSPOON_INIT" \
        && grep -Eq 'require[[:space:]]*\([[:space:]]*["'"'"]trumpify["'"'"]' "$HAMMERSPOON_INIT"; then
        warn "An existing Trumpify integration was found in $HAMMERSPOON_INIT; leaving it unchanged."
        return 0
    fi

    local escaped_dir
    escaped_dir=$(lua_escape "$SCRIPT_DIR")
    local block_file
    local cleaned_file
    block_file=$(mktemp "$HAMMERSPOON_DIR/trumpify-block.XXXXXX")
    cleaned_file=$(mktemp "$HAMMERSPOON_DIR/init-clean.XXXXXX")

    cat > "$block_file" <<EOF
$BEGIN_MARKER
pcall(require, "hs.ipc")
local trumpify_home = "$escaped_dir"
package.path = package.path
    .. ";" .. trumpify_home .. "/?.lua"
    .. ";" .. trumpify_home .. "/?/init.lua"
local trumpify_ok, trumpify_error = pcall(require, "trumpify")
if not trumpify_ok then
    hs.alert.show("Trumpify failed to load: " .. tostring(trumpify_error))
end
$END_MARKER
EOF

    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
        $0 == begin { skipping = 1; next }
        $0 == end { skipping = 0; next }
        !skipping { print }
    ' "$HAMMERSPOON_INIT" > "$cleaned_file"

    if [[ -s $cleaned_file ]]; then
        printf '\n' >> "$cleaned_file"
    fi
    cat "$block_file" >> "$cleaned_file"
    mv "$cleaned_file" "$HAMMERSPOON_INIT"
    rm -f "$block_file"
    chmod 600 "$HAMMERSPOON_INIT"
    success "Hammerspoon configured in $HAMMERSPOON_INIT"
}

reload_hammerspoon() {
    (( NO_RELOAD == 1 )) && return 0
    if command -v hs >/dev/null 2>&1; then
        if hs -c 'hs.reload()' >/dev/null 2>&1; then
            success "Hammerspoon reloaded"
            return 0
        fi
    fi
    if [[ -d /Applications/Hammerspoon.app ]]; then
        open -a Hammerspoon
        success "Hammerspoon launched"
        return 0
    fi
    warn "Configuration is ready, but Hammerspoon could not be reloaded automatically."
}

info "${BOLD}Trumpify setup${RESET}"
info "This wizard configures the API and connects Trumpify to Hammerspoon."
ensure_hammerspoon
choose_provider
read_api_key
test_api_connection
write_config
configure_hammerspoon
reload_hammerspoon

info ""
success "Trumpify setup is complete"
info "Endpoint: $ENDPOINT"
info "Model:    $MODEL"
info "Select text in any app and press ⌃⌥Space to open Trumpify."
