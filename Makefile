DYLIB := SatanabeCleanUI.dylib
BUILD := build
MIN_IOS ?= 15.0

# Accept either "Sources/" or "Source/" so GitHub uploads from iPhone
# don't fail just because the folder name differs.
ifneq ("$(wildcard Sources/SatanabeCleanUI.mm)","")
SRC_DIR := Sources
else ifneq ("$(wildcard Source/SatanabeCleanUI.mm)","")
SRC_DIR := Source
else
$(error Could not find SatanabeCleanUI.mm in Sources/ or Source/)
endif

SRC := $(SRC_DIR)/SatanabeCleanUI.mm
CONFIG := $(SRC_DIR)/SCUIConfig.h

.PHONY: all clean inspect

all: $(BUILD)/$(DYLIB)

$(BUILD)/$(DYLIB): $(SRC) $(CONFIG)
	@mkdir -p $(BUILD)
	@SDK="$$(xcrun --sdk iphoneos --show-sdk-path)"; \
	xcrun --sdk iphoneos clang++ \
	  -arch arm64 \
	  -dynamiclib \
	  -fobjc-arc \
	  -fmodules \
	  -std=c++17 \
	  -isysroot "$$SDK" \
	  -miphoneos-version-min=$(MIN_IOS) \
	  -framework Foundation \
	  -framework UIKit \
	  -framework AVFoundation \
	  -framework QuartzCore \
	  -Wl,-install_name,@rpath/$(DYLIB) \
	  -Wl,-dead_strip \
	  $(SRC) \
	  -o $(BUILD)/$(DYLIB)

inspect: all
	file $(BUILD)/$(DYLIB)
	xcrun otool -L $(BUILD)/$(DYLIB)

clean:
	rm -rf $(BUILD)
