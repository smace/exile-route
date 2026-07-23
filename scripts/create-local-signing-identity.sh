#!/bin/sh
set -eu

identity_name="${EXILE_ROUTE_SIGNING_IDENTITY:-Exile Route Local Signing}"
keychain_path="${EXILE_ROUTE_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

if security find-identity -v -p codesigning "$keychain_path" 2>/dev/null | grep -Fq "\"$identity_name\""; then
    printf 'Signing identity already available: %s\n' "$identity_name"
    exit 0
fi

openssl_bin="$(command -v openssl || true)"
if [ -z "$openssl_bin" ]; then
    printf 'OpenSSL is required. Install it with: brew install openssl\n' >&2
    exit 1
fi

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/exile-route-signing.XXXXXX")"
cleanup() {
    rm -rf "$temporary_directory"
}
trap cleanup EXIT HUP INT TERM

"$openssl_bin" req \
    -x509 \
    -newkey rsa:3072 \
    -sha256 \
    -days 3650 \
    -nodes \
    -keyout "$temporary_directory/private-key.pem" \
    -out "$temporary_directory/certificate.pem" \
    -subj "/CN=$identity_name/O=Exile Route Local/OU=Local Code Signing" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,digitalSignature,keyCertSign" \
    -addext "extendedKeyUsage=codeSigning" \
    -addext "subjectKeyIdentifier=hash" \
    -addext "authorityKeyIdentifier=keyid:always" \
    >/dev/null 2>&1

p12_password="$("$openssl_bin" rand -hex 32)"
legacy_flag=""
if "$openssl_bin" pkcs12 -help 2>&1 | grep -q -- "-legacy"; then
    legacy_flag="-legacy"
fi

# The temporary password only protects the in-memory transfer into Keychain.
# The PKCS#12 file and source private key are deleted by the trap above.
# shellcheck disable=SC2086
"$openssl_bin" pkcs12 \
    -export \
    $legacy_flag \
    -out "$temporary_directory/identity.p12" \
    -inkey "$temporary_directory/private-key.pem" \
    -in "$temporary_directory/certificate.pem" \
    -name "$identity_name" \
    -passout "pass:$p12_password" \
    >/dev/null 2>&1

security import "$temporary_directory/identity.p12" \
    -k "$keychain_path" \
    -P "$p12_password" \
    -T /usr/bin/codesign \
    -T /usr/bin/security

security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$keychain_path" \
    "$temporary_directory/certificate.pem"

if ! security find-identity -v -p codesigning "$keychain_path" | grep -Fq "\"$identity_name\""; then
    printf 'The identity was imported but is not valid for code signing.\n' >&2
    exit 1
fi

printf 'Created local signing identity: %s\n' "$identity_name"
