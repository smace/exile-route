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

## Visual changes

Every pull request that changes the interface must include before-and-after captures. Use account-neutral content and do not commit Path of Exile or Grinding Gear Games proprietary logos, fonts, textures, maps, or icons.

All decorative assets in the application must remain original SwiftUI shapes or original project artwork. Cinzel is included under the SIL Open Font License.

## Validation

Run before opening a pull request:

```sh
./scripts/generate-project.sh
./scripts/validate-snapshot.sh
xcodebuild test -project ExileRoute.xcodeproj -scheme ExileRoute -destination 'platform=macOS,arch=arm64'
```

Changes to capture, focus, overlay, or progression behavior also require a manual check in the real GeForce NOW client.
