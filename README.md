<p align="center">
  <img src="Icon/logo.png" width="300" alt="Control logo: a teal isometric cube on a worn cream-edged tile">
</p>

<h1 align="center">Control</h1>

<p align="center">
  A small tiling window manager for macOS.<br>
  No config file, no macOS Spaces, no System Integrity Protection changes. About 1,200 lines of Swift you can read.
</p>

---

- Windows **tile on their own**: a new window splits the focused one, a closed one gives its space back.
- Every window lives on a **desk**. The main monitor shows one desk at a time; each extra monitor is one more desk.
- Dialogs and fixed-size windows **float**.
- The **mouse** works too: drag an edge and the neighbors follow, drop a window on another to trade places, drop it on another monitor to move it there.
- An unplugged monitor lends its windows to the main one, and **gets them back**, in the same layout, when it returns.
- A window in macOS's own full screen mode (a video, the green button) is **left alone**, and so is everything behind it.
- Windows **go back to their desk** when Control restarts. After a reboot, each app's windows go to the desk of its oldest window.
- The menu bar shows the current desk and a small map of each monitor: one box per tiled window, filled for a full screen window. Click it to see every desk and its apps.

## Keys

| Key                       | Action                         |
| ------------------------- | ------------------------------ |
| Option + desk key         | Show desk                      |
| Option + Shift + desk key | Send window to desk            |
| Option + Tab              | Previous desk                  |
| Option + H/J/K/L          | Focus left/down/up/right       |
| Option + Shift + H/J/K/L  | Swap with neighbor, or move to the monitor that way |
| Option + Minus / Equal    | Shrink / grow                  |
| Option + Shift + F        | Toggle fullscreen              |
| Option + Shift + Space    | Toggle floating                |

Desk keys: 1–9 and every letter except F, H, J, K, L.

## Install

Needs macOS 14+ and Xcode or the Command Line Tools.

```sh
make install
```

This builds Control.app, quits the running copy, copies the new one to `/Applications` and opens it.

Allow the **Accessibility** permission when asked, then open Control again. It starts at login from then on.

Each rebuild needs the permission again, unless you make a signing certificate once
(Keychain Access → Certificate Assistant → Create a Certificate…, name it `Control Signing`, type **Code Signing**).
The build uses it when it finds it. To use a certificate with another name:

```sh
SIGN_IDENTITY="Your Certificate Name" make install
```

To quit: menu bar → Quit Control. Hidden windows come back on screen first.

## Settings

Edit `Sources/Control/Settings.swift` and rebuild:

```swift
let gap: CGFloat = 8
let resizeStep: CGFloat = 0.05
let deskKeys = "123456789ABCDEGIMNOPQRSTUVWXYZ".map(String.init)
```

## Tests

```sh
make test
```

The tests run Control against a pretend Mac (`Tests/ControlTests/FakeMac.swift`): monitors and windows are
plain values, so no real window moves and no permission is needed. They cover the layout, desks, keys,
mouse drags, monitors coming and going, full screen videos, the lock screen and restarts, and they play
long random sessions to look for a state that breaks the rules.

What only a real Mac can show is in [TESTING.md](TESTING.md): a short list to go through by hand.

## Known limits

- Option + letter no longer types special characters (like Option + E for é).
- Apps with a minimum size (Finder) can stick out of a small tile.
- Hidden windows are parked just past a bottom corner of a monitor, with one point left on screen. Control picks a corner with no other monitor behind it, but that one point can show.
- The keys trade places with a window on another monitor, or move a window to a monitor with nothing that way. To add a window to a monitor that already has some, drag it there.
- A window that changes its own size (the green button with Option, a double click on the title bar) keeps that size until the next change.
