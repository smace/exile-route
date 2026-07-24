# Contributing

Exile Route uses a pull-request-only workflow after `v1.0.0`.

## Workflow

1. Create a branch named `feat/*`, `fix/*`, or `chore/*` from `main`.
2. Keep commits focused and use Conventional Commits.
3. Open a pull request with a Conventional Commit title.
4. Complete the pull request checklist and resolve all review conversations.
5. Wait for every required CI check.
6. Squash merge and delete the source branch.

Direct pushes, force-pushes, and deletion of `main` are blocked by repository rules.

## Versioning and releases

Published versions follow [Semantic Versioning](https://semver.org/):

- increment `MAJOR` for incompatible application, route, or persisted-data behavior;
- increment `MINOR` for backward-compatible features and meaningful interface or workflow changes;
- increment `PATCH` for backward-compatible fixes only.

Each release pull request updates `MARKETING_VERSION` and increments `CURRENT_PROJECT_VERSION` in `project.yml`, regenerates the Xcode project, moves the changelog entries out of `Unreleased`, and adds release notes. The merged release commit is tagged `vMAJOR.MINOR.PATCH`; `scripts/build-release.sh` derives the archive name from that marketing version.

Beta tags use `vMAJOR.MINOR.PATCH-beta.N` and must be marked as pre-releases on GitHub. Every Stable or Beta archive is added to `updates/appcast.xml` with `scripts/prepare-appcast.sh`; that appcast change follows the same pull-request and CI rules as application code.

## Visual changes

Every pull request that changes the interface must include before-and-after captures. Use account-neutral content and do not commit Path of Exile or Grinding Gear Games proprietary logos, fonts, textures, maps, or icons.

All decorative assets in the application must remain original SwiftUI shapes or original project artwork. Cinzel is included under the SIL Open Font License.

## Validation

Run before opening a pull request:

```sh
./scripts/generate-project.sh
./scripts/validate-snapshot.sh
./scripts/validate-appcast.sh
xcodebuild test -project ExileRoute.xcodeproj -scheme ExileRoute -destination 'platform=macOS,arch=arm64'
```

Changes to capture, focus, overlay, or progression behavior also require a manual check in the real GeForce NOW client.
