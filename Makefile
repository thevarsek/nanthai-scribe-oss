## Builds a signed .app from the SwiftPM package. Direct-distribution (Developer ID) build:
## the Mac App Store sandbox doesn't allow the global key tap or synthetic paste.

# Optional machine-specific signing settings. Never synced or committed.
-include Config.local.mk
export TEAM_ID NOTARY_PROFILE

APP      := NanthAi Scribe.app
EXEC     := ScribeMac
CONFIG   ?= release
BUNDLE   := build/$(APP)
CONTENTS := $(BUNDLE)/Contents
TIMESTAMP ?= --timestamp=none

## Accessibility grants are tied to the code signature. A stable Developer ID keeps the
## grant across rebuilds; ad-hoc ("-") would need re-granting after every build.
SIGN_ID ?= $(shell security find-identity -v -p codesigning 2>/dev/null \
             | grep "Developer ID Application" | grep -F -- "$(TEAM_ID)" | head -1 | sed -E 's/.*"(.*)".*/\1/')
ifeq ($(strip $(SIGN_ID)),)
SIGN_ID := -
endif

.PHONY: app install run test clean icon dmg dmg-background

app:
	swift build -j 4 -c $(CONFIG) --product $(EXEC)
	python3 Tools/build-metal.py "$$(swift build -j 4 -c $(CONFIG) --show-bin-path)"
	@rm -rf "$(BUNDLE)"
	@mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	@cp "$$(swift build -j 4 -c $(CONFIG) --show-bin-path)/$(EXEC)" "$(CONTENTS)/MacOS/$(EXEC)"
	@cp "$$(swift build -j 4 -c $(CONFIG) --show-bin-path)/mlx.metallib" "$(CONTENTS)/Resources/mlx.metallib"
	@for resource in "$$(swift build -j 4 -c $(CONFIG) --show-bin-path)"/*.bundle; do \
		cp -R "$$resource" "$(CONTENTS)/Resources/"; \
	done
	@cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	@cp Resources/PrivacyInfo.xcprivacy "$(CONTENTS)/Resources/PrivacyInfo.xcprivacy"
	@cp .build/artifacts/sparkle/Sparkle/LICENSE "$(CONTENTS)/Resources/Sparkle-LICENSE.txt"
	@mkdir -p "$(CONTENTS)/Frameworks"
	@ditto "$$(swift build -j 4 -c $(CONFIG) --show-bin-path)/Sparkle.framework" "$(CONTENTS)/Frameworks/Sparkle.framework"
	# Remove the linker signature before changing the rpath; the bundle is signed below.
	@codesign --remove-signature "$(CONTENTS)/MacOS/$(EXEC)"
	@install_name_tool -add_rpath @executable_path/../Frameworks "$(CONTENTS)/MacOS/$(EXEC)"
	@cp Resources/AppIcon.icns "$(CONTENTS)/Resources/AppIcon.icns"
	@chmod -R u+w "$(BUNDLE)"
	@xattr -cr "$(BUNDLE)"
	@Tools/release/sign-sparkle.sh "$(CONTENTS)/Frameworks/Sparkle.framework" "$(SIGN_ID)" "$(TIMESTAMP)"
	@codesign --force --options runtime $(TIMESTAMP) \
		--entitlements Resources/ScribeMac.entitlements \
		--sign "$(SIGN_ID)" "$(BUNDLE)"
	@echo "built $(BUNDLE) [signed: $(SIGN_ID)]"

install: app
	@pkill -x $(EXEC) 2>/dev/null || true
	@rm -rf "/Applications/$(APP)"
	@cp -R "$(BUNDLE)" "/Applications/$(APP)"
	@open "/Applications/$(APP)"
	@echo "installed /Applications/$(APP)"

run: app
	@pkill -x $(EXEC) 2>/dev/null || true
	@open "$(BUNDLE)"

## Regenerate the icon from Tools/MakeIcon.swift (not part of every build).
icon:
	swift Tools/MakeIcon.swift Resources/Icon
	@rm -rf build/AppIcon.iconset && mkdir -p build/AppIcon.iconset
	@for s in 16 32 128 256 512; do \
		sips -z $$s $$s Resources/Icon/icon-mac-1024.png --out build/AppIcon.iconset/icon_$${s}x$${s}.png >/dev/null; \
		d=$$((s*2)); sips -z $$d $$d Resources/Icon/icon-mac-1024.png --out build/AppIcon.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

test:
	swift test

clean:
	rm -rf .build build

## NOTARY_PROFILE is deliberately optional; an unset value produces a signed local artifact.
dmg:
	@test "$(SIGN_ID)" != "-" || (echo "make dmg requires a Developer ID Application identity."; exit 1)
	$(MAKE) app CONFIG=release TIMESTAMP=--timestamp
	$(MAKE) dmg-background
	Tools/release/make-dmg.sh "$(SIGN_ID)"

dmg-background:
	@mkdir -p build/dmg-background
	xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library Sources/ScribeUI/Brand.swift Sources/ScribeUI/TrioMark.swift Tools/MakeDMGBackground.swift -o build/dmg-background/render
	build/dmg-background/render build/dmg-background
