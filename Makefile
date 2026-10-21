SDK := $(shell xcrun --sdk iphoneos --show-sdk-path)
CLANG := xcrun --sdk iphoneos clang
CFLAGS := -arch arm64 -isysroot "$(SDK)" -miphoneos-version-min=14.0 -fobjc-arc -fblocks -O2 -dynamiclib
FRAMEWORKS := -framework Foundation -framework UIKit -framework QuartzCore -framework Metal -framework MetalKit
LDFLAGS := -Wl,-install_name,@rpath/ResolutionTrace.dylib

.PHONY: all clean inspect
all: build/SatanabeCleanUI.dylib

build/SatanabeCleanUI.dylib: Sources/ResolutionTrace.m
	mkdir -p build
	$(CLANG) $(CFLAGS) $(FRAMEWORKS) $(LDFLAGS) $< -o $@

inspect: build/SatanabeCleanUI.dylib
	file build/SatanabeCleanUI.dylib
	otool -hv build/SatanabeCleanUI.dylib | head -8

clean:
	rm -rf build dist *.zip
