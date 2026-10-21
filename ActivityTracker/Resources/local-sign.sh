#!/bin/bash
# Signs ActivityTracker.app with a stable, self-signed identity that is created on and never leaves this Mac.
#
#   local-sign.sh <app>           sign (creates the identity on first use)
#   local-sign.sh --check <app>   exit 0 if <app> is already signed with this Mac's identity, 1 otherwise
#
# Why: macOS remembers privacy permissions (Accessibility, Automation) by the app's code signature. An ad-hoc
# signature changes with every build, so every update would silently lose them; a stable identity keeps them.
set -euo pipefail

DIR="$HOME/Library/Application Support/ActivityTracker/Signing"
KEYCHAIN="$DIR/signing.keychain-db"
CERT="$DIR/certificate.pem"
# Only protects this throwaway local signing key.
PASSWORD="activitytracker-local-signing"
NAME="ActivityTracker Local Signing"
# LibreSSL from macOS: its PKCS#12 files can be imported by `security`, Homebrew OpenSSL 3's by default cannot.
SSL=/usr/bin/openssl

fingerprint() {
    "$SSL" x509 -in "$CERT" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g' | tr 'A-F' 'a-f'
}

create_identity() {
    security delete-keychain "$KEYCHAIN" 2>/dev/null || true
    rm -rf "$DIR"
    mkdir -p "$DIR"
    chmod 700 "$DIR"
    local tmp
    tmp="$(mktemp -d)"

    cat > "$tmp/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
    "$SSL" req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$tmp/cert.cnf" \
        -keyout "$tmp/key.pem" -out "$CERT" 2>/dev/null
    "$SSL" pkcs12 -export -inkey "$tmp/key.pem" -in "$CERT" -name "$NAME" \
        -out "$tmp/identity.p12" -passout "pass:$PASSWORD"

    # create-keychain adds the new keychain to the user's search list; the list is put back right away so other
    # apps never see (or ask to unlock) this keychain.
    save_search_list
    trap restore_search_list EXIT   # even if creation fails half-way
    security create-keychain -p "$PASSWORD" "$KEYCHAIN"
    restore_search_list
    trap - EXIT
    security set-keychain-settings "$KEYCHAIN"   # no auto-lock
    security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
    security import "$tmp/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null
    rm -rf "$tmp"
}

# The user's keychain search list, saved so it can be restored exactly.
SEARCH=()
save_search_list() {
    SEARCH=()
    local line
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%\"}"
        line="${line#\"}"
        # Never keep our own keychain on the list (e.g. left there by an interrupted run).
        [[ -z "$line" || "$line" == "$KEYCHAIN" ]] && continue
        SEARCH+=("$line")
    done < <(security list-keychains -d user)
}
restore_search_list() {
    if [[ ${#SEARCH[@]} -gt 0 ]]; then
        security list-keychains -d user -s "${SEARCH[@]}"
    fi
}

sign() {
    security unlock-keychain -p "$PASSWORD" "$KEYCHAIN" || return 1
    # codesign looks identities up through the search list, so the keychain is on it only while signing.
    save_search_list
    trap restore_search_list EXIT
    security list-keychains -d user -s ${SEARCH[@]+"${SEARCH[@]}"} "$KEYCHAIN"
    local status=0
    codesign --force --timestamp=none --keychain "$KEYCHAIN" --sign "$(fingerprint)" "$1" || status=$?
    restore_search_list
    trap - EXIT
    [[ $status -eq 0 ]] || return $status
    codesign --verify --strict "$1"
}

if [[ "${1:-}" == "--check" ]]; then
    APP="${2:?usage: local-sign.sh --check <app>}"
    [[ -f "$CERT" ]] || exit 1
    requirement="$(codesign -d -r- "$APP" 2>&1 || true)"
    requirement="$(echo "$requirement" | tr 'A-F' 'a-f')"
    if [[ "$requirement" == *"$(fingerprint)"* ]]; then exit 0; else exit 1; fi
fi

APP="${1:?usage: local-sign.sh <app>}"
if [[ ! -f "$KEYCHAIN" || ! -f "$CERT" ]]; then
    create_identity
fi
if ! sign "$APP"; then
    # A broken identity (e.g. keychain deleted by hand): start over once.
    echo "local-sign: signing failed, recreating the identity" >&2
    create_identity
    sign "$APP"
fi
echo "local-sign: signed $APP with $(fingerprint)"
