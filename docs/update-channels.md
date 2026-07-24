# Application update channels

Exile Route uses Sparkle 2 with one HTTPS appcast committed at `updates/appcast.xml`. Release archives are authenticated with an Ed25519 signature before Sparkle offers them to an installed app.

## Channel behavior

| Build | Bundle identifier | Data directory | Update behavior |
| --- | --- | --- | --- |
| Stable | `com.swannmace.ExileRoute` | `Application Support/Exile Route` | Stable by default; user may opt into Beta |
| Beta | `com.swannmace.ExileRoute` | `Application Support/Exile Route` | Always follows Beta and also accepts a later Stable |
| Dev | `com.swannmace.ExileRoute.Dev` | `Application Support/Exile Route Dev` | Sparkle disabled |

Sparkle always includes the unchannelled Stable feed. Selecting Beta additionally permits items marked `sparkle:channel="beta"`, so a final Stable build with a higher build number naturally replaces its beta.

All published builds must increment `CFBundleVersion`, including successive betas. `CFBundleShortVersionString` follows Semantic Versioning for user-visible releases.

## Trust model

The public Ed25519 key is embedded in the application through `SUPublicEDKey`. Its private key is stored only in the maintainer's login Keychain under account `com.swannmace.ExileRoute`; it is not committed and is not uploaded as a GitHub Actions secret.

Ed25519 authenticates the update archive. It does not replace Apple Developer ID signing or notarization. Until those are available, public builds remain ad hoc signed and users must approve the application on first installation. The durable self-signed certificate documented in `local-signing.md` remains local to the maintainer's Mac.

Back up the update private key securely. Losing it means already installed updater-enabled builds cannot trust a replacement key without a manually installed migration release.

## Prepare a Stable update

1. Merge and tag the release using the normal pull-request release process.
2. Build `ExileRoute-MAJOR.MINOR.PATCH.zip` with `./scripts/build-release.sh`.
3. Publish the archive and checksum in GitHub Release `vMAJOR.MINOR.PATCH`.
4. Generate the signed appcast entry:

   ```sh
   ./scripts/prepare-appcast.sh \
     stable \
     v1.4.0 \
     ExileRoute-1.4.0.zip \
     docs/release-notes-v1.4.0.md
   ```

5. Validate and submit the `updates/appcast.xml` change through a pull request:

   ```sh
   ./scripts/validate-appcast.sh
   ```

The feed uses the raw `main` URL, so an update is visible only after its archive exists in the matching GitHub Release and the appcast pull request is merged.

## Prepare a Beta update

Use a monotonically increasing build number, tag the GitHub Release as a pre-release, and generate its feed item with the Beta channel:

```sh
./scripts/prepare-appcast.sh \
  beta \
  v1.4.0-beta.1 \
  ExileRoute-1.4.0-beta.1.zip \
  docs/release-notes-v1.4.0-beta.1.md
```

The release archive must contain the Beta configuration so Settings visibly identifies the pre-release and automatically follows Beta.

## Local Dev loop

Run:

```sh
./scripts/build-local-dev.sh
open DerivedData/LocalDev/Build/Products/Debug/ExileRoute.app
```

Dev is deliberately absent from the appcast. Its separate bundle identifier and Application Support directory allow experimentation without replacing Stable or changing real campaign progress.

The first updater-enabled Stable version is v1.4.0. Existing v1.3.0 installations need that single version installed manually; every later compatible release can be delivered by Sparkle.
