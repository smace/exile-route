# Durable local code signing

Exile Route can use a self-signed identity stored in the macOS login Keychain. This gives local builds a stable designated requirement, so macOS can recognize updates as the same application instead of treating every ad hoc build as new code.

This workflow is intended for development and installation on a trusted Mac. It does not replace Developer ID signing or Apple notarization for public distribution.

## Create the identity

Install OpenSSL if necessary, then create the ten-year local identity:

```sh
brew install openssl
./scripts/create-local-signing-identity.sh
```

The script:

- creates `Exile Route Local Signing`;
- imports its private key into the login Keychain;
- trusts the certificate for code signing in the user trust domain;
- grants key access only to `/usr/bin/codesign` and `/usr/bin/security`;
- deletes every temporary certificate, PKCS#12 file, password, and source private key.

No certificate or private key material belongs in Git. Losing the private key requires creating a new identity and granting Screen Recording permission again. A self-signed certificate cannot be revoked through Apple, so it must remain local and protected by the Keychain.

## Build a signed local Release

```sh
./scripts/build-local-release.sh
```

The application is written to:

```text
DerivedData/LocalSigned/Build/Products/Release/ExileRoute.app
```

The script fails if the identity is missing, the signature is invalid, or the designated requirement still depends on a changing `cdhash`.

Inspect the resulting identity at any time:

```sh
codesign --verify --deep --strict --verbose=2 ExileRoute.app
codesign -d -r- ExileRoute.app
security find-identity -v -p codesigning
```

The first migration from an ad hoc signature to this identity requires Screen Recording permission once. Later builds signed with the same private key and bundle identifier should retain the same code identity.

## Overrides

The scripts accept these optional environment variables:

- `EXILE_ROUTE_SIGNING_IDENTITY`
- `EXILE_ROUTE_KEYCHAIN`
- `EXILE_ROUTE_DERIVED_DATA`

CI and public release artifacts continue to build without this machine-local identity.
