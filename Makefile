PROJECT := FluxKit.xcodeproj
SCHEME := FluxKit
DESTINATION ?= platform=iOS Simulator,name=iPhone 18 Pro Max
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO

ARCHIVE_DIR ?= build
ARCHIVE_PATH := $(ARCHIVE_DIR)/FluxKit.xcarchive
ARCHIVE_CMD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
	-destination 'generic/platform=iOS' archive -allowProvisioningUpdates
ORGANIZER_ARCHIVES := $(HOME)/Library/Developer/Xcode/Archives

.PHONY: generate test test-unit test-ui build archive archive-file open-archive export clean site

site:
	python3 scripts/build_site.py

generate:
	xcodegen generate

test: generate
	$(XCODEBUILD) test

test-unit: generate
	$(XCODEBUILD) test -only-testing:FluxKitTests

test-ui: generate
	$(XCODEBUILD) test -only-testing:FluxKitUITests

build: generate
	$(XCODEBUILD) build

# Archive into Xcode's own archive folder, so it shows up in
# Xcode → Window → Organizer and can be uploaded from there.
archive: generate
	$(ARCHIVE_CMD)
	@echo ""
	@echo "Open Xcode → Window → Organizer to distribute it, or run: make open-archive"

# Archive to a fixed path instead (CI, or when you want the file next to the repo).
archive-file: generate
	$(ARCHIVE_CMD) -archivePath $(ARCHIVE_PATH)

# Open the newest archive from Organizer's folder.
open-archive:
	@ARCHIVE=$$(ls -dt $(ORGANIZER_ARCHIVES)/*/*.xcarchive 2>/dev/null | head -1); \
	if [ -z "$$ARCHIVE" ]; then echo "no archive in $(ORGANIZER_ARCHIVES) — run: make archive"; exit 1; fi; \
	echo "opening $$ARCHIVE"; open "$$ARCHIVE"

export: archive-file
	xcodebuild -exportArchive -archivePath $(ARCHIVE_PATH) \
		-exportPath build/export -exportOptionsPlist ExportOptions.plist \
		-allowProvisioningUpdates

clean:
	rm -rf build DerivedData
