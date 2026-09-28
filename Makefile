DYLIB := SatanabeCleanUI.dylib
BUILD := build
MIN_IOS ?= 15.0

ifneq ("$(wildcard Source/SatanabeCleanUI.mm)","")
SRC_DIR := Source
else ifneq ("$(wildcard Sources/SatanabeCleanUI.mm)","")
SRC_DIR := Sources
else
$(error SatanabeCleanUI.mm nao encontrado em Source/ nem Sources/)
endif

SRC := $(SRC_DIR)/SatanabeCleanUI.mm
CONFIG := $(SRC_DIR)/SCUIConfig.h
OBJ := $(BUILD)/SatanabeCleanUI.o
OUT := $(BUILD)/$(DYLIB)

SDK := $(shell xcrun --sdk iphoneos --show-sdk-path)

.PHONY: all clean inspect diagnose

all: $(OUT)

$(BUILD):
	mkdir -p $(BUILD)

$(OBJ): $(SRC) $(CONFIG) | $(BUILD)
	@echo "===== COMPILANDO OBJECT ====="
	xcrun --sdk iphoneos clang++ \
		-v \
		-arch arm64 \
		-c \
		-fobjc-arc \
		-fmodules \
		-std=c++17 \
		-isysroot "$(SDK)" \
		-miphoneos-version-min=$(MIN_IOS) \
		$(SRC) \
		-o $(OBJ)

diagnose: $(OBJ)
	@echo ""
	@echo "===== SIMBOLOS EXTERNOS/UNDEFINED ====="
	xcrun nm -u $(OBJ) | sort || true
	@echo ""
	@echo "===== COREGRAPHICS ====="
	xcrun nm -u $(OBJ) | grep -E "CGColor|CGRect|CGPoint|CGSize|CGPath|CGContext" || true
	@echo ""

$(OUT): $(OBJ)
	@echo "===== LINKANDO DYLIB ====="
	xcrun --sdk iphoneos clang++ \
		-v \
		-arch arm64 \
		-dynamiclib \
		-isysroot "$(SDK)" \
		-miphoneos-version-min=$(MIN_IOS) \
		-framework Foundation \
		-framework UIKit \
		-framework CoreGraphics \
		-framework QuartzCore \
		-framework AVFoundation \
		-Wl,-install_name,@rpath/$(DYLIB) \
		-Wl,-dead_strip \
		$(OBJ) \
		-o $(OUT)

inspect: diagnose $(OUT)
	@echo ""
	@echo "===== RESULTADO ====="
	file $(OUT)
	xcrun otool -L $(OUT)

clean:
	rm -rf $(BUILD)
