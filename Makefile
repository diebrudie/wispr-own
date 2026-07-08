.PHONY: setup build run app reload clean

setup:
	Scripts/fetch-whisper.sh

build: setup
	swift build

run: setup
	swift run

app: setup
	Scripts/make-app.sh

# Rebuild the .app, replace the running instance, relaunch.
reload: app
	-pkill -f 'WisprOwn.app/Contents/MacOS/WisprOwn'
	sleep 1
	open dist/WisprOwn.app
	@echo "Relaunched. If the hotkey stops working, the build was ad-hoc signed —"
	@echo "run ./Scripts/make-signing-cert.sh once, then 'make reload' again."

clean:
	rm -rf .build dist
