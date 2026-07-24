# Exile Route 1.4.0

Exile Route 1.4.0 adds authenticated automatic updates and separate Stable, Beta, and Dev channels.

Highlights:

- check a signed update feed automatically once per day or manually from Settings and the menu bar;
- keep Stable as the default while allowing an explicit opt-in to Beta releases;
- let a later Stable release supersede an installed beta automatically;
- run isolated Dev builds alongside Stable with a separate bundle identifier and Application Support directory;
- authenticate every update archive with an Ed25519 signature whose private key remains in the maintainer's Keychain;
- expose the active update channel and automatic-check controls in Settings;
- preserve the existing application identity, campaign progress, shortcuts, overlay position, and Screen Recording permission during the one-time manual upgrade from v1.3.0.

The application targets Apple Silicon and requires macOS 15 or newer. The public archive is ad hoc signed and is not notarized, so its first launch must be approved with Finder's **Open** command.

The application includes no proprietary Path of Exile visual assets. Route content is attributed to HeartofPhos and bundled under its MIT license.
