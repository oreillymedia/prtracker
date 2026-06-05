# Avatar Image Caching via Nuke — Design

**Date:** 2026-06-05

## Goal

Cache GitHub avatar images so they don't re-download on every app launch and
across the many views that render them. Today every avatar uses SwiftUI's
`AsyncImage`, which has no persistent cache and re-fetches per instance.

## Background

All avatar rendering funnels through a single view, `AvatarView`
(`PRTracker/DesignSystem/AvatarView.swift`), used at 10 call sites (mail rows,
detail header, thread messages, timeline events, review comments, settings,
account footer, quick reply). Each currently triggers its own `AsyncImage`
load. Avatars are small (size 15–32) and repeat heavily across rows and
threads, so the same URL is fetched many times.

Target platform: macOS 26.4, Swift 5. Existing SPM dependency: Sparkle.

## Decisions

- **Integration style:** NukeUI's `LazyImage` as a drop-in replacement for
  `AsyncImage` inside `AvatarView`.
- **Cache configuration:** Nuke's **default shared `ImagePipeline`** — no
  custom pipeline. In-memory `ImageCache` + HTTP disk caching via `URLCache`.

## Dependency

Add the Swift Package `https://github.com/kean/Nuke`, pinned "up to next major"
from a recent 12.x release. Link only the **NukeUI** product to the PRTracker
target (it transitively brings in Nuke core).

Changes land in:
- `PRTracker.xcodeproj/project.pbxproj` — add an `XCRemoteSwiftPackageReference`
  and a package product dependency for NukeUI, alongside the existing Sparkle
  entry.
- `PRTracker.xcodeproj/.../swiftpm/Package.resolved` — updated by Xcode/SPM
  resolution.

## The code change

`PRTracker/DesignSystem/AvatarView.swift` — replace the `AsyncImage` (line 10)
with `LazyImage`, preserving all existing behavior:

```swift
import NukeUI
// ...
if let url = user.avatarURL {
    LazyImage(url: url) { state in
        if let image = state.image {
            image.resizable().scaledToFill()
        } else {
            Color.clear          // colored Circle behind shows through while loading / on error
        }
    }
    .clipShape(Circle())
} else {
    // unchanged letter fallback
}
```

The surrounding `ZStack` (colored `Circle` behind), `.frame(width:height:)`, and
the no-URL letter fallback are unchanged.

## What this buys us

- `LazyImage` uses Nuke's shared `ImagePipeline` automatically: an in-memory
  `ImageCache` plus HTTP disk caching via `URLCache`.
- **Request coalescing** — the same avatar appears many times across views;
  Nuke dedupes concurrent loads of the same URL and serves repeats from the
  memory cache instantly, instead of `AsyncImage` re-fetching per instance.
- GitHub avatar URLs ship sensible cache headers, so the `URLCache` layer gives
  cross-launch persistence without configuring a custom pipeline.

## Error / placeholder behavior

Unchanged from today: the `Tokens.commented` `Circle` sits behind the image, so
both the loading state and a load failure show that colored circle. The
`Color.clear` in the non-image state lets it show through.

## Testing

No new unit tests — this is a pure view swap and image loading is not
meaningfully unit-testable here. Verification:

- `xcodebuild -scheme PRTracker -destination 'platform=macOS' build` succeeds.
- `xcodebuild -scheme PRTracker -destination 'platform=macOS' test` — existing
  suite stays green.
- Manual: avatars render, and they load from cache (no re-download) after an
  app relaunch.

## Out of scope (YAGNI)

- No custom `ImagePipeline`.
- No aggressive `DataCache`.
- No image prefetching.
- No changes to any of the 10 `AvatarView` call sites.
