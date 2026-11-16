<p align="center">
  <img src="Icon/logo.png" width="300" alt="Control logo: a teal isometric cube on a worn cream-edged tile">
</p>

<h1 align="center">Control</h1>

<p align="center">
  A small tiling window manager for macOS.<br>
  No config file, no macOS Spaces, no System Integrity Protection changes. About 1,600 lines of Swift you can read.
</p>

---

- Windows **tile on their own**: a new window splits the focused one, a closed one gives its space back.
- Every window lives on a **desk**. The main monitor shows one desk at a time. Each extra monitor **takes a desk for itself**: the first one desk 0, the next one 9, then 8, down to 2.
- Pick a window on another desk, with Command + Tab, the Dock or Command + `, and **its desk comes on screen**.
- Dialogs and fixed-size windows **float**.
- The **pointer follows**: switch to another window, with a key, Command + Tab or the Dock, and it jumps to the middle of it. A key that moves or resizes the window (full screen, swap, send) takes it along. Show an empty desk and it goes to the middle of that desk. A click leaves it where it is. It can be switched off in the settings.
- The **mouse** works too: drag an edge and the neighbors follow, drop a window on another to trade places, drop it on another monitor to move it there.
- An unplugged monitor leaves its desk behind: its key shows it on the main monitor. The monitor **gets it back**, in the same layout, when it returns.
- A window in macOS's own full screen mode (a video, the green button) is **left alone**, and so is everything behind it.
- Windows **go back to their desk** when Control restarts. After a reboot, each app's windows go to the desk of its oldest window.
- The menu bar shows the current desk and a small map of each monitor: one box per tiled window, filled for a full screen window. Click it to see every desk and its apps.
- Scripts can do what the keys do, and more, with the **`control` command**: show a desk, or bring up a window wherever it is.

## Keys

| Key                       | Action                         |
| ------------------------- | ------------------------------ |
| Option + desk key         | Show desk, or focus it if an extra monitor shows it |
| Option + Shift + desk key | Send window to desk            |
| Option + Tab              | Previous desk                  |
| Option + H/J/K/L          | Focus left/down/up/right       |
| Option + Shift + H/J/K/L  | Swap with neighbor, or move to the monitor that way |
| Option + Minus / Equal    | Shrink / grow                  |
| Option + Shift + F        | Toggle fullscreen              |
| Option + Shift + Space    | Toggle floating                |

Desk keys: 0–9 and every letter except F, H, J, K, L.

With a second monitor plugged in, desk 0 is on it: Option + 0 gives it the focus, and Option + Shift + 0
sends the focused window there. A third monitor takes desk 9, and so on: nine extra monitors at most.
Desk 1 is always for the main monitor.

## Command line

The keys and the `control` command give the same commands to the running app.

```sh
control ls                           # the desks in use and their windows
control show 3                       # Option + 3
control focus app Ghostty            # a window of an app: its desk comes on screen, then the window gets focus
control focus title "~/code/my-app"   # the first window whose title contains this
control focus window 4211            # a window by number, from `control ls`
```

`make install` links it into `~/.local/bin`. A notification that brings you back to the terminal that sent it,
with [terminal-notifier](https://github.com/julienXX/terminal-notifier):

```sh
terminal-notifier -message "Build done" -execute "$HOME/.local/bin/control focus title '${PWD##*/}'"
```

Every command, the output formats, exit statuses and the socket other programs can talk to directly:
[COMMANDS.md](COMMANDS.md).

## Install

Needs macOS 14+ and Xcode or the Command Line Tools.

```sh
make install
```

This builds Control.app, quits the running copy, copies the new one to `/Applications`, links the
`control` command into `~/.local/bin` and opens the app.

Allow the **Accessibility** permission when asked, then open Control again. It starts at login from then on.

Each rebuild needs the permission again, unless you make a signing certificate once
(Keychain Access → Certificate Assistant → Create a Certificate…, name it `Control Signing`, type **Code Signing**).
The build uses it when it finds it. To use a certificate with another name:

```sh
SIGN_IDENTITY="Your Certificate Name" make install
```

To quit: menu bar → the power button. Hidden windows come back on screen first.

## Settings

Menu bar → the gear opens the settings window. What it shows is kept in `~/.config/control/config.json`:

```json
{
  "centerPointer" : true,
  "log" : false,
  "logFolder" : "~/Library/Logs/Control"
}
```

- `centerPointer`: the pointer follows the focus (see above). Off, Control never moves the pointer.
- `log`, `logFolder`: the debug log, below.

The file is the source of truth. Control reads it when it starts. After changing it by hand, click
**Sync settings** in the window (or restart Control) to use what it says. A file that cannot be read
changes nothing, and is never overwritten: the window says what is wrong with it.

The layout and the keys are set in code. Edit `Sources/Control/Settings.swift` and rebuild:

```swift
let gap: CGFloat = 8
let resizeStep: CGFloat = 0.05
let deskKeys = "1234567890ABCDEGIMNOPQRSTUVWXYZ".map(String.init)
let monitorDeskKeys = "098765432".map(String.init)
```

## Debug log

When windows end up in the wrong place, the debug log says how they got there. It is off until you
switch it on in the settings window. Then Control writes one line for each thing that happens:

- what macOS reports: sleep and wake, lock and unlock, monitors, apps and windows opening and closing,
- what Control does about it: which desk a window joins and why, which windows it keeps or lets go,
- where each window is: the frame Control asked for and the one the window took.

**Written:** times, window numbers, process numbers, bundle identifiers (like `com.apple.Safari`), window
positions and sizes, monitors, desk keys, the names of Control's own commands.

**Never written:** window titles, app names, the text given to `control focus title` or `control focus app`,
any key you type, file paths.

The log stays on your Mac: `control.log` in the log folder, readable by you only, 4 megabytes at most
(older lines go away). Control sends nothing anywhere.

To report a bug, switch the log on, wait for the bug to happen again, then click **Export log…** in the
settings window, or run:

```sh
control export            # a zip on the Desktop
control export ~/Downloads
```

The zip holds the log, a picture of where every window is right now, your `config.json`, and the versions
of Control and macOS. They are plain text files: open the zip and read them before you send it.
Each line of the log is one JSON object, so `grep` and `jq` work on it:

```sh
grep '"e":"adopt"' ~/Library/Logs/Control/control.log
```

## Tests

```sh
make test
```

The tests run Control against a pretend Mac (`Tests/ControlTests/FakeMac.swift`): monitors and windows are
plain values, so no real window moves and no permission is needed. They cover the layout, desks, keys,
mouse drags, monitors coming and going, full screen videos, the lock screen, restarts and the command line, and they play
long random sessions to look for a state that breaks the rules.

What only a real Mac can show is in [TESTING.md](TESTING.md): a short list to go through by hand.

## Known limits

- Option + letter no longer types special characters (like Option + E for é).
- Apps with a minimum size (Finder) can stick out of a small tile.
- Hidden windows are parked just past a bottom corner of a monitor, with one point left on screen. Control picks a corner with no other monitor behind it, but that one point can show.
- Option + the key of an empty desk on an extra monitor only moves the pointer there: there is no window to give the focus to.
- A window that changes its own size (the green button with Option, a double click on the title bar) keeps that size until the next change.
