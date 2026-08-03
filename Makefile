.PHONY: all project build debug test strings run dmg pkg icon clean

CONFIG ?= Release
APP = build/Build/Products/$(CONFIG)/QLite.app

all: build

## Regenerate QLite.xcodeproj from project.yml
project:
	xcodegen generate

## Build the app (CONFIG=Debug|Release)
build:
	Scripts/build.sh $(CONFIG)

debug:
	Scripts/build.sh Debug

## Run the unit tests
test: project
	xcodebuild -project QLite.xcodeproj -scheme QLite -configuration Debug \
		-derivedDataPath build test

## Check that all translations define the same keys
strings:
	Scripts/check-localization.sh

## Build and launch the app
run: build
	open $(APP)

## Build the drag-and-drop DMG installer into dist/
dmg:
	Scripts/make-dmg.sh

## Build the .pkg installer into dist/
pkg:
	Scripts/make-pkg.sh

## Regenerate the app icon assets
icon:
	swift Scripts/generate-icon.swift

clean:
	rm -rf build dist QLite.xcodeproj
