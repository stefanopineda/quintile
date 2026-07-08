.PHONY: build test app run clean

build:
	swift build

test:
	swift run quintile-tests

app:
	Scripts/build-app.sh

run: app
	open dist/Quintile.app

clean:
	rm -rf .build dist
