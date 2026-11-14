.PHONY: app run install clean

app:
	./bundle.sh

run: app
	open Control.app

# Quit the running copy first (SIGTERM, so hidden windows come back), then start the new one.
install: app
	pkill -x Control || true
	rm -rf /Applications/Control.app
	cp -R Control.app /Applications/
	open /Applications/Control.app

clean:
	rm -rf .build Control.app
