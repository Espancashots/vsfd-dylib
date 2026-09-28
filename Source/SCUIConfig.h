#pragma once

// SatanabeCleanUI — tweak only these constants for quick visual changes.
#define SCUI_VERSION_STRING @"1.0.0"

// General appearance
#define SCUI_BACKGROUND_BLACK 1
#define SCUI_REPLACE_SYSTEM_ORANGE_WITH_WHITE 1

// Glass/card look
#define SCUI_GLASS_CORNER_RADIUS 20.0
#define SCUI_GLASS_BORDER_WIDTH 0.65
#define SCUI_GLASS_BORDER_ALPHA 0.20
#define SCUI_GLASS_BLACK_ALPHA 0.26

// Floating control look
#define SCUI_FLOATING_IDLE_BORDER_WIDTH 0.45
#define SCUI_FLOATING_ACTIVE_BORDER_WIDTH 1.00
#define SCUI_FLOATING_IDLE_BORDER_ALPHA 0.22
#define SCUI_FLOATING_ACTIVE_BORDER_ALPHA 0.95

// Re-scan interval. This also keeps the old PatchShowcase video suppressed
// if the SwiftUI screen rebuilds itself.
#define SCUI_RESCAN_INTERVAL 1.0
