# MacTabs — autoscrolling tab viewer as a native Mac app.
# make            build build/MacTabs.app
# make run        build and launch
# make test       build + drive the app through the FIFO harness (tests/ui.sh; no focus steal)
# make test-full  the same plus the real-keystroke leg (steals focus — leave the Mac alone)
# make install    copy the bundle to ~/Applications
APP    := MacTabs
BUILD  := build
BUNDLE := $(BUILD)/$(APP).app
REL    := .build/release

all: $(BUNDLE)

$(BUNDLE): $(wildcard Sources/MacTabs/*.swift) Package.swift res/Info.plist
	swift build -c release
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp $(REL)/$(APP) $(BUNDLE)/Contents/MacOS/
	cp -R $(REL)/*.bundle $(BUNDLE)/Contents/Resources/
	cp res/Info.plist $(BUNDLE)/Contents/
	@[ -f res/$(APP).icns ] && cp res/$(APP).icns $(BUNDLE)/Contents/Resources/ || true
	printf 'APPL????' > $(BUNDLE)/Contents/PkgInfo
	codesign --force --sign - $(BUNDLE)
	@echo "→ $(BUNDLE)"

run: all
	open $(BUNDLE)

test: all
	tests/ui.sh

test-full: all
	FULL=1 tests/ui.sh

install: all
	mkdir -p ~/Applications
	rm -rf ~/Applications/$(APP).app
	cp -R $(BUNDLE) ~/Applications/

clean:
	rm -rf $(BUILD) .build

.PHONY: all run test test-full install clean
