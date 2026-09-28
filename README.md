# SatanabeCleanUI.dylib

UI-only override dylib for the current Satanabe External interface.

It intentionally does **not** change Supabase, keys, patch files, container access, kernel code, offsets, entitlements, or patch application logic.

## What it changes

- suppresses the `LoopingPlayerView` / AVPlayer background video;
- keeps an opaque black layer in the same position so `PatchBackground` does not show through;
- changes the general window/background treatment to black;
- applies a dark glass/material look to compatible rounded panels;
- makes compatible UIKit controls monochrome/white;
- turns system orange into white for a cleaner theme;
- gives small floating UIKit controls a subtle white border;
- while a compatible floating control is pressed/highlighted, the border becomes 1 pt white;
- rescans the visible hierarchy so SwiftUI rebuilds do not bring the old video back.

The current Satanabe patch cards already use `.ultraThinMaterial` in SwiftUI. Removing the video and placing them over black makes those cards much closer to the requested Liquid Glass-style appearance; the dylib also reinforces compatible UIKit material views.

## Compile on GitHub

1. Create an empty GitHub repository.
2. Upload the **contents** of this project, keeping `.github/workflows/build.yml` in that exact path.
3. Open **Actions** > **Build SatanabeCleanUI dylib** > **Run workflow**.
4. When the job finishes, download the artifact **SatanabeCleanUI-dylib**.
5. Inside it you will find `SatanabeCleanUI.dylib` and a ZIP copy.

No Apple certificate is needed for the GitHub compile step. You sign the final IPA later in eSign.

## Quick customization

Edit `Sources/SCUIConfig.h` and rebuild. The most useful values are:

- `SCUI_GLASS_CORNER_RADIUS`
- `SCUI_GLASS_BORDER_WIDTH`
- `SCUI_GLASS_BORDER_ALPHA`
- `SCUI_GLASS_BLACK_ALPHA`
- `SCUI_FLOATING_ACTIVE_BORDER_WIDTH`
- `SCUI_RESCAN_INTERVAL`

## Notes

This project targets arm64 iPhones and uses only public UIKit / AVFoundation runtime APIs. It does not depend on Theos, Substitute, ElleKit, jailbreak, or private SwiftUI class names for loading.

Because the host app is SwiftUI, exact styling of every SwiftUI-rendered pixel cannot be guaranteed from an injected UIKit dylib. The video suppression is specifically tailored to the current `LoopingPlayerView`; the extra glass/card styling is deliberately conservative to avoid breaking taps and layout.
