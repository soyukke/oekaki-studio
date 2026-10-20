# Oekaki Studio build.
#
#   make run    build and launch the app
#   make test   run the unit tests
#   make app    build build/OekakiStudio.app
#   make pv     make the promotional film, out/pv.mp4
#   make logo   draw the logo and app icon into brand/
#
# The core is written in Kizu. Point KIZU at a compiler that supports
# `export "c"` and `--emit obj` (and set KIZU_LIB_DIR if it needs one),
# either on the command line or in a local.mk next to this file.

-include local.mk

KIZU ?= kizu
KIZU_FLAGS ?= --opt
CORE_OBJ := build/core.o
APP := build/OekakiStudio.app
BIN = $(shell swift build -c release --show-bin-path)/OekakiApp

.PHONY: all core build test run app pv logo clean

all: build

core: $(CORE_OBJ)

$(CORE_OBJ): core/core.kizu
	@mkdir -p build
	$(KIZU) build --target native --emit obj $(KIZU_FLAGS) -o $@ $<

build: core
	swift build -c release

test: core
	swift test

run: core
	swift run OekakiApp

app: build
	@rm -rf $(APP)
	@mkdir -p $(APP)/Contents/MacOS
	cp $(BIN) $(APP)/Contents/MacOS/OekakiStudio
	cp packaging/Info.plist $(APP)/Contents/Info.plist
	@mkdir -p $(APP)/Contents/Resources
	cp brand/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	codesign --force --sign - $(APP)
	@echo "Built $(APP)"

pv: core
	swift build -c release --product OekakiPV
	$(shell swift build -c release --show-bin-path)/OekakiPV still out/picture.png
	$(shell swift build -c release --show-bin-path)/OekakiPV film out/pv.mp4

logo: core
	swift build -c release --product OekakiPV
	$(shell swift build -c release --show-bin-path)/OekakiPV logo brand
	@rm -rf brand/AppIcon.iconset

clean:
	rm -rf .build build/core.o build/core.o.kizu-build.json $(APP)
