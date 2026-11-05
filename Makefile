PROJECT := FluxKit.xcodeproj
SCHEME := FluxKit
DESTINATION ?= platform=iOS Simulator,name=iPhone 18 Pro Max
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO

.PHONY: generate test test-unit test-ui build archive export clean

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

archive: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'generic/platform=iOS' -archivePath build/FluxKit.xcarchive \
		archive -allowProvisioningUpdates

export: archive
	xcodebuild -exportArchive -archivePath build/FluxKit.xcarchive \
		-exportPath build/export -exportOptionsPlist ExportOptions.plist \
		-allowProvisioningUpdates

clean:
	rm -rf build DerivedData
