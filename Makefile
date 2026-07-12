.PHONY: build test app run clean verify-brew

build:
	swift build

test:
	swift run quintile-tests

app:
	Scripts/build-app.sh

run: app
	open dist/Quintile.app

# Full Homebrew install/uninstall/reinstall lifecycle (needs network + brew).
# Run before every public cask release — this is what humans should not re-do by hand.
verify-brew:
	bash Scripts/verify-brew-lifecycle.sh

clean:
	rm -rf .build dist
