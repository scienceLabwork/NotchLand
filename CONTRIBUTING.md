# Contributing to NotchLand

Thanks for your interest in NotchLand! This is a small, focused macOS app and
contributions of all sizes are welcome — bug reports, fixes, features, and docs.

## Getting set up

```bash
git clone https://github.com/scienceLabwork/NotchLand.git
cd NotchLand
open NotchLand.xcodeproj
```

NotchLand is a plain Xcode project (no `Package.swift`). Dependencies — **Sparkle** and
**Lottie** — are resolved by Xcode through Swift Package Manager automatically on first
open.

### Signing (read this first)

The project ships with the maintainer's Apple Developer Team (`H7RVWCMKF5`) baked into the
build settings, so a fresh clone **will not sign on your machine**. Before building:

1. Open the project in Xcode.
2. Select the **NotchLand** target → **Signing & Capabilities**.
3. Set **Team** to your own (or uncheck *Automatically manage signing* / set signing to
   *None* for a local unsigned build).

Note: App Sandbox is **off** and Hardened Runtime is **on** by default. Full Sparkle
update *installation* only works on Developer ID–signed builds, but that doesn't affect
local development.

## Building & testing

```bash
# Build (Debug)
xcodebuild -project NotchLand.xcodeproj -scheme NotchLand -configuration Debug build

# Run tests (Swift Testing, hosted in the app target)
xcodebuild -project NotchLand.xcodeproj -scheme NotchLand -configuration Debug test \
  -destination 'platform=macOS'

# Clean
xcodebuild -project NotchLand.xcodeproj -scheme NotchLand clean
```

SwiftUI Previews need Xcode (not the command line). For UI/animation work, iterate in
Xcode.

## Project conventions

- **Match the surrounding code.** There is no linter and no enforced style — read the
  neighboring files and follow their naming, comment density, and structure.
- **Concurrency:** the project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so types
  default to `@MainActor`. Move non-UI work to `nonisolated` functions, actors, or
  explicit `Task`s.
- **Adding a notch overlay?** Follow the existing pipeline: a `Controller` publishes a
  `Presentation` whose `branchKey` is handled in `FloatingNotchView`. A new branch needs
  four touch points — the check in `branchKey`, a size case in `currentVisibleSize(for:)`,
  a content case in `branchView(for:)`, and a mirror size case in
  `WindowManager.currentVisibleSize()` for the hover hit-test.
- New `.swift` files dropped into `NotchLand/` are picked up automatically (the project
  uses Xcode's synchronized file groups) — no `project.pbxproj` edit needed.

## Pull requests

- Open an **issue** to discuss anything larger than a small fix before sending a big PR.
- Keep PRs focused; describe what changed and how you tested it.
- Make sure the project builds and the tests pass before requesting review.

## License

By contributing, you agree that your contributions are licensed under the
[Apache License 2.0](LICENSE), the same license as the project.
