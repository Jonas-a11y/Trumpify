#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/trumpify-setup-test.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT

HOME_DIR="$TEST_DIR/home"
FAKE_BIN="$TEST_DIR/bin"
mkdir -p "$HOME_DIR" "$FAKE_BIN"

cat > "$FAKE_BIN/curl" <<'EOF'
#!/bin/bash
set -euo pipefail
output=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --output) output=$2; shift 2 ;;
        --write-out) shift 2 ;;
        *) shift ;;
    esac
done
if [[ ${FAKE_CURL_FAILURE:-0} == 1 ]]; then
    printf '{"error":{"message":"rate limited"}}' > "$output"
    printf '429'
else
    printf '{"choices":[{"message":{"content":"OK"}}]}' > "$output"
    printf '200'
fi
EOF
chmod +x "$FAKE_BIN/curl"

cat > "$FAKE_BIN/hs" <<'EOF'
#!/bin/bash
touch "$HOME/hs-reloaded"
EOF
chmod +x "$FAKE_BIN/hs"

run_wizard() {
    HOME=$HOME_DIR PATH="$FAKE_BIN:$PATH" TRUMPIFY_API_KEY="test-secret-value" \
        "$ROOT/setup.sh" --non-interactive --provider custom \
        --endpoint "http://localhost:6655/openai/v1" --model "gpt-5.6-luna"
}

run_wizard > "$TEST_DIR/first-run.log"

CONFIG="$HOME_DIR/.config/trumpify/config.json"
INIT="$HOME_DIR/.hammerspoon/init.lua"
[[ -f $CONFIG ]] || { echo "config file missing" >&2; exit 1; }
[[ -f $INIT ]] || { echo "Hammerspoon init missing" >&2; exit 1; }
[[ -f $HOME_DIR/hs-reloaded ]] || { echo "Hammerspoon was not reloaded" >&2; exit 1; }
grep -Fq '"endpoint": "http://localhost:6655/openai/v1/chat/completions"' "$CONFIG"
grep -Fq '"model": "gpt-5.6-luna"' "$CONFIG"
grep -Fq '"apiKey": "test-secret-value"' "$CONFIG"
[[ $(stat -f '%Lp' "$CONFIG") == 600 ]] || { echo "config permissions are not 600" >&2; exit 1; }
grep -Fq -- '-- >>> Trumpify setup >>>' "$INIT"
grep -Fq "$ROOT" "$INIT"

WIZARD_TEST_CONFIG=$CONFIG /usr/bin/osascript -l JavaScript <<'JXA' >/dev/null
ObjC.import('Foundation')
const env = $.NSProcessInfo.processInfo.environment
const path = ObjC.unwrap(env.objectForKey($('WIZARD_TEST_CONFIG')))
const contents = $.NSString.stringWithContentsOfFileEncodingError(
  $(path), $.NSUTF8StringEncoding, null
)
const config = JSON.parse(ObjC.unwrap(contents))
config.disabledModes = ['linkedin']
const text = $(JSON.stringify(config, null, 2) + '\n')
text.writeToFileAtomicallyEncodingError($(path), true, $.NSUTF8StringEncoding, null)
JXA

run_wizard > "$TEST_DIR/second-run.log"
[[ $(grep -Fc -- '-- >>> Trumpify setup >>>' "$INIT") == 1 ]] \
    || { echo "wizard added duplicate Hammerspoon blocks" >&2; exit 1; }
grep -Fq '"disabledModes": [' "$CONFIG" \
    || { echo "wizard discarded existing configuration" >&2; exit 1; }

if HOME=$HOME_DIR PATH="$FAKE_BIN:$PATH" TRUMPIFY_API_KEY="test-secret-value" \
    FAKE_CURL_FAILURE=1 "$ROOT/setup.sh" --non-interactive --provider custom \
    --endpoint "http://localhost:6655/openai/v1" --model "gpt-5.6-luna" \
    > "$TEST_DIR/failure.log" 2>&1; then
    echo "wizard accepted a failed API test" >&2
    exit 1
fi
grep -Fq 'API test failed (HTTP 429): rate limited' "$TEST_DIR/failure.log"
if grep -Fq 'test-secret-value' "$TEST_DIR/failure.log"; then
    echo "wizard leaked the API key into output" >&2
    exit 1
fi

echo "Setup wizard tests passed"
