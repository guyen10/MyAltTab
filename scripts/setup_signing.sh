#!/bin/bash
# Creates a self-signed code signing certificate in a dedicated keychain (once), then unlocks it.
# Signing every build with the same certificate keeps the app's identity stable,
# so macOS keeps its Accessibility and Screen Recording permissions across rebuilds.
#
# The signing keychain's password is random and stored in the login keychain, never in this repo.
# No app is pre-approved to read it, so macOS asks before every build; that keeps other
# processes from silently unlocking the key and re-signing a binary as MyAltTab.
set -euo pipefail

KEYCHAIN="$HOME/Library/Keychains/myalttab-signing.keychain-db"
PASSWORD_SERVICE="MyAltTab signing keychain"
IDENTITY="MyAltTab Self-Signed"

stored_password() {
    security find-generic-password -a "$USER" -s "$PASSWORD_SERVICE" -w 2>/dev/null
}

# codesign only finds identities in keychains on the user's search list.
add_to_search_list() {
    if ! security list-keychains -d user | grep -q "$KEYCHAIN"; then
        local current=()
        while IFS= read -r line; do
            line="${line#"${line%%[![:space:]]*}"}"   # trim leading spaces
            current+=("${line//\"/}")                # strip quotes
        done < <(security list-keychains -d user)
        security list-keychains -d user -s "${current[@]}" "$KEYCHAIN"
    fi
}

create_keychain() {
    local password tmp
    password="$(/usr/bin/openssl rand -base64 32)"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN

    cat > "$tmp/cert.conf" <<CONF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CONF

    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -config "$tmp/cert.conf" -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
    P12_PASSWORD="$password" /usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
        -name "$IDENTITY" -out "$tmp/identity.p12" -passout env:P12_PASSWORD

    security create-keychain -p "$password" "$KEYCHAIN"
    security set-keychain-settings -l -t 300 "$KEYCHAIN" # lock on sleep and after 5 minutes
    security unlock-keychain -p "$password" "$KEYCHAIN"
    security import "$tmp/identity.p12" -k "$KEYCHAIN" -P "$password" -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$KEYCHAIN" >/dev/null
    security add-generic-password -U -a "$USER" -s "$PASSWORD_SERVICE" -w "$password" \
        -T "" "$HOME/Library/Keychains/login.keychain-db"
    echo "Created signing identity \"$IDENTITY\" in $KEYCHAIN"
}

if [ ! -f "$KEYCHAIN" ]; then
    create_keychain
fi

if ! password="$(stored_password)"; then
    echo "error: no stored password for $KEYCHAIN." >&2
    echo "Delete that keychain and run this script again to recreate it." >&2
    exit 1
fi
add_to_search_list
security set-keychain-settings -l -t 300 "$KEYCHAIN" # also tightens keychains created by older versions
security unlock-keychain -p "$password" "$KEYCHAIN"
