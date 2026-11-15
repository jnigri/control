.PHONY: app run install test clean

# The Command Line Tools ship the Swift Testing library, but the compiler does not find its
# macros there on its own. Xcode needs no help.
ifeq ($(shell xcode-select -p),/Library/Developer/CommandLineTools)
TEST_FLAGS = -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
endif

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

# The tests run against a pretend Mac: no window moves, no permission needed.
test:
	swift test $(TEST_FLAGS)

clean:
	rm -rf .build Control.app
