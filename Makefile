DYLIB := SatanabeCleanUI.dylib
BUILD := build
SRC := Source/SatanabeCleanUI.mm
OBJ := $(BUILD)/SatanabeCleanUI.o
OUT := $(BUILD)/$(DYLIB)
MIN_IOS ?= 15.0
SDK := $(shell xcrun --sdk iphoneos --show-sdk-path)

.PHONY: all clean inspect diagnose

all: $(OUT)

$(BUILD):
	mkdir -p $(BUILD)

$(OBJ): $(SRC) | $(BUILD)
	xcrun --sdk iphoneos clang++ \
		-arch arm64 -c -fobjc-arc -fblocks -fmodules -std=c++17 -O2 \
		-isysroot "$(SDK)" -miphoneos-version-min=$(MIN_IOS) \
		$(SRC) -o $(OBJ)

diagnose: $(OBJ)
	@echo "===== UNDEFINED SYMBOLS BEFORE LINK ====="
	xcrun nm -u $(OBJ) | sort || true

$(OUT): $(OBJ)
	xcrun --sdk iphoneos clang++ \
		-arch arm64 -dynamiclib -fobjc-arc -fblocks \
		-isysroot "$(SDK)" -miphoneos-version-min=$(MIN_IOS) \
		-framework Foundation \
		-framework UIKit \
		-framework AVFoundation \
		-framework QuartzCore \
		-framework CoreGraphics \
		-framework UniformTypeIdentifiers \
		-Wl,-install_name,@rpath/$(DYLIB) \
		-Wl,-dead_strip \
		$(OBJ) -o $(OUT)

inspect: diagnose $(OUT)
	file $(OUT)
	xcrun lipo $(OUT) -verify_arch arm64
	xcrun otool -L $(OUT)

clean:
	rm -rf $(BUILD)
