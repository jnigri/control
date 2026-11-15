# Checking by hand

`make test` covers Control's own logic against a pretend Mac. This list covers what only a real Mac
can show: that macOS and real apps behave the way the pretend Mac assumes. Go through it after a
change to `Events.swift` or `Accessibility.swift`, after a macOS update, or the first time you plug in a monitor.

Start with `make install`, and three windows side by side on a desk.

## Full screen videos

The tests assume two things: a full screen window says so (the Accessibility attribute `AXFullScreen`),
and during the animation in and out it already, or still, says so.

- [ ] Play a video in your browser and press the player's full screen button. The video fills the screen.
- [ ] Leave full screen. Every window is back in the tile it had.
- [ ] Same with the green button of a window.
- [ ] Same in each browser you use. They do it differently: some move the window to its own Space, some open a new window for the video, some just cover the screen.
- [ ] With a window in full screen, swipe to the desktop and back a few times (four fingers, or Control + arrows), then leave full screen. The layout is the same.
- [ ] During a full screen video, press Option + 2, then leave full screen. Desk 2 shows, and desk 1 still has its layout.

If the layout is lost, note which browser, and whether it was on the way in or the way out.

## Mouse

The tests assume apps report moves and resizes of their windows while the mouse button is down.

- [ ] Drag the edge between two tiles and let go. The neighbor takes the new size.
- [ ] While dragging, the window follows the pointer: nothing pulls it back before you let go.
- [ ] Drag a window by its title bar onto another tile. They trade places.
- [ ] Drag a window a little and drop it on its own tile. It snaps back.
- [ ] Select text with the mouse while another app opens a window. Nothing trades places.
- [ ] Try the first three with a terminal, which only takes sizes that fit whole lines of text.

## Lock and sleep

- [ ] Lock the screen (Control + Command + Q), wait ten seconds, unlock. Nothing moved, on any desk.
- [ ] Let the display sleep, wake it. Same.
- [ ] Sleep the Mac, wake it. Same.

## A second monitor

- [ ] Plug it in. The menu bar shows a second, empty map. No hidden window shows up on the new monitor (look along its edges: one point at most).
- [ ] Option + Shift + H or L moves the focused window to it, and back.
- [ ] Drag a window to it. Drop one on a tile there: it splits that tile.
- [ ] Drag a dialog to it, then change desk on the main monitor. The dialog stays.
- [ ] Option + H or L moves the focus across monitors.
- [ ] Unplug it. Its windows are tiled on the main monitor.
- [ ] Plug it back. They are back on it, in the same layout.
- [ ] With windows on both monitors, sleep the Mac and wake it. Both layouts are the same.
- [ ] Close the laptop lid with the monitor plugged in, then open it again. Nothing is lost.
- [ ] Play a full screen video on one monitor. With "Displays have separate Spaces" on (System Settings, Desktop & Dock), the other monitor keeps tiling. With it off, macOS blanks the other monitor; after the video both layouts are the same.
- [ ] Try the monitor on the left, on the right, and above or below (System Settings, Displays, Arrange). Each time, change desk and check that hidden windows stay hidden.

## Command line

- [ ] `control ls` lists the desks and their windows with titles, and `control windows` the same, tab-separated.
- [ ] `control focus app <an app on another desk>`. That desk shows, and the window has the focus: typing goes to it.
- [ ] `control focus window <number>` for a window on another monitor. The desk on the main monitor stays.
- [ ] Run `sleep 5; control show 2` in a terminal and lock the screen right away. After unlocking, the terminal says the screen is locked, and nothing moved.
- [ ] Quit Control, then run `control ls`. It says Control is not running.

## Restart

- [ ] With windows on several desks, run `make install`. Every window is back on its desk.
- [ ] With a dialog on a desk you are not looking at, run `pkill -9 Control`, then open Control again. Every window can be reached, and the dialog shows when you go to its desk.
- [ ] Restart the Mac with "Reopen windows when logging back in". Each app lands on the desk its oldest window had.
