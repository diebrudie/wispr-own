.PHONY: setup build run app clean

setup:
	Scripts/fetch-whisper.sh

build: setup
	swift build

run: setup
	swift run

app: setup
	Scripts/make-app.sh

clean:
	rm -rf .build dist
