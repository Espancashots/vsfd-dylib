# Injecting SatanabeCleanUI.dylib with eSign

Use this only with the Satanabe External IPA you control.

## Before starting

Keep a clean backup of the original IPA. If the edited app fails to launch, reinstall the clean copy and repeat the injection from that file.

## Steps

1. Download `SatanabeCleanUI.dylib` from the GitHub Actions artifact to the iPhone.
2. Import both the Satanabe External IPA and `SatanabeCleanUI.dylib` into eSign.
3. Open the signing/editing screen for the Satanabe External IPA.
4. Use eSign's **dylib injection** / **add dylib** option (the exact wording varies by eSign version).
5. Select `SatanabeCleanUI.dylib`.
6. Confirm that eSign is adding it to the app bundle and adding a load command for the dylib. Do not remove the app's existing frameworks or dylibs.
7. Sign the edited IPA with the same certificate/provisioning flow you normally use.
8. Install the newly signed IPA.

## Expected result

Open the patch screen:

- the old looping video should no longer be visible;
- the area behind the patches should be black;
- compatible cards/material views should look darker and glass-like;
- orange UIKit tint should become white;
- compatible small floating controls should have a subtle border, becoming a thin bright-white border while pressed.

## If the app crashes immediately

That normally means the dylib was not embedded/loaded correctly or the signing step changed something required by the app. Start again from the clean IPA. It is not necessary to modify Supabase or patch data for this UI dylib.

## If the video still appears

Make sure the injected file is actually loaded. A correctly loaded build continuously suppresses any `AVPlayerLayer` used by the current `LoopingPlayerView`, including when the SwiftUI screen rebuilds.
