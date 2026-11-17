# The `control` command

Everything the keys do, and a few things they can't, from a terminal, a script or another app.
This page is the reference for tools that talk to Control. `control help` prints a short version.

- [Setup](#setup)
- [Commands](#commands)
- [Output](#output)
- [Exit status](#exit-status)
- [The socket](#the-socket)
- [Examples](#examples)

## Setup

`make install` links the command into `~/.local/bin/control` (`BIN_DIR=/somewhere make install` for another
folder). It is the app's own program, `/Applications/Control.app/Contents/MacOS/Control`. Run with words, it
asks the running app and prints the answer. Run without any, it starts the app.

Control must be running. The command needs no permission of its own: only the app moves windows.

Tools that run commands outside your shell (notifications, launchd jobs, some launchers) often have a short
`PATH` that leaves out `~/.local/bin`. Give them the full path.

## Commands

Each command is a few words. Quote a word that has spaces in it: `control focus app "Google Chrome"`.

| Command                         | What it does                                                                 |
| ------------------------------- | ---------------------------------------------------------------------------- |
| `show <desk>`                   | Show a desk on the main monitor. If an extra monitor shows it, focus it. Option + desk key. |
| `show previous`                 | Show the desk that was on the main monitor before. Option + Tab.             |
| `send <desk>`                   | Send the focused window to a desk, and show that desk. To the desk of an extra monitor, the window moves to that monitor. Option + Shift + desk key. |
| `focus left\|down\|up\|right`    | Focus the neighbor that way, on any monitor. Option + H/J/K/L.             |
| `focus window <number>`         | Focus a window by its number (see `windows`).                               |
| `focus app <name>`              | Focus a window of an app, by name (`Safari`) or bundle identifier (`com.apple.Safari`). Any case. |
| `focus title <text>`            | Focus a window whose title contains the text. Any case.                     |
| `swap left\|down\|up\|right`     | Trade places with the neighbor that way, or move to the monitor that way. Option + Shift + H/J/K/L. |
| `grow`, `shrink`                | Move the split next to the focused window. Option + Equal / Minus.          |
| `fullscreen`                    | The focused window covers its desk, or stops covering it. Option + Shift + F. |
| `float`                         | Float the focused window, or tile it again. Option + Shift + Space.         |
| `menu`                          | Open the menu bar panel, with every desk and its apps, or close it. Option + Slash. |
| `ls`                            | The desks in use and their windows, for people.                             |
| `windows`                       | Every window, one per line, for scripts.                                    |
| `export [folder]`               | Zip the debug log, to send with a bug report: on the Desktop, or in a folder. Prints the path of the zip. Works with the screen locked. See the README, "Debug log". |
| `help`                          | The list of commands. Works without the app.                                |

**Desks.** A desk key: `0` to `9`, or a letter except `F`, `H`, `J`, `K`, `L`, in any case. Each extra
monitor takes a desk for itself: the first one `0`, the next one `9`, then `8`, down to `2`. That desk is always
on screen, so `show` only gives it the focus. When the monitor is unplugged, the desk is one like the others
again, until the monitor returns.

**The `focus` commands that name a window** work wherever the window is. If its desk is not on screen,
that desk comes on screen first (and `show previous` goes back). If another window covers the desk
(`fullscreen`), it stops covering it, so the window shows. When several windows match, the first one wins, in
this order:

1. the focused window,
2. windows on screen, then windows on hidden desks; on each desk, the window that last had focus first,
3. windows Control leaves alone, like one in macOS's own full screen mode.

So `focus app Ghostty` stays on the Ghostty window you are using, or picks one you can see before one on
another desk.

**Commands that do not apply do nothing**, like their key: `focus left` with nothing on the left, `grow` on
a desk with one window. They still succeed. Only these fail:

- a `focus` that names a window when no window matches,
- any command while the screen is locked (apps report no windows then, so moving them would lose the layout).

## Output

Commands that change something print nothing. Errors go to standard error, as `control: <message>`.

### `ls`, for people

```
1  shown
   4211  Ghostty  ~/code/my-app — zsh
   4212  Safari   Pull requests
3
   4300  Notes    Groceries
0  shown
   4400  Mail     Inbox
```

Each desk that is on screen or has windows, with `shown` if it is on screen, then its windows: number, app,
title. Tiled windows first, from left/top to right/bottom, then floating ones. The layout of this text
may change: read `windows` from scripts.

### `windows`, for scripts

One line per window, columns separated by tabs, in the same order as `ls`:

| Column | Example      | Meaning                                                       |
| ------ | ------------ | ------------------------------------------------------------- |
| 1      | `4211`       | Window number, for `focus window`. It lasts as long as the window. |
| 2      | `1`          | Desk key.                                                     |
| 3      | `shown`      | `shown` if the desk is on screen, else `hidden`.              |
| 4      | `Ghostty`    | App name. May be empty.                                      |
| 5      | `~/code` | Window title. May be empty.                                  |

Tabs and line breaks in names and titles become spaces, so a line is always one window. No windows: no
output. New columns, if any, will be added at the end.

```sh
control windows | awk -F'\t' '$3 == "shown" { print $1 }'                  # numbers of the windows on screen
control windows | awk -F'\t' '$4 == "Ghostty" { print $1 " on desk " $2 }'
```

The list holds the windows Control manages. `focus window` also accepts the number of a window it leaves
alone (one in macOS's own full screen mode, say).

## Exit status

| Status | Meaning                                                                         |
| ------ | ------------------------------------------------------------------------------- |
| 0      | Done (or nothing to do, see above).                                            |
| 1      | Control said no (no window matches, the screen is locked), is not running, or did not answer within 5 seconds. |
| 2      | Not a command. The usage follows the error. Checked before asking the app.     |

## The socket

The command is a thin client. A tool can skip it and talk to the app directly.

- **Where:** a Unix socket at `control.sock` in your own temporary folder, the one
  `getconf DARWIN_USER_TEMP_DIR` prints (it ends with `/`). Only you can open it.
- **Request:** one JavaScript Object Notation (JSON) array of strings, the words of a command, then a line break:
  `["focus", "app", "Safari"]`
- **Answer:** one JSON object, then a line break, then the app closes the connection:
  `{"output": "..."}` when done (`""` for commands that print nothing), or `{"error": "no window matches"}`.
- One request per connection. Requests run on the app's main thread, one after the other, like key presses.
- A request without a line break within 64 KB is dropped without an answer.

```sh
echo '["show", "3"]' | nc -U "$(getconf DARWIN_USER_TEMP_DIR)control.sock"
```

```python
import json, socket, subprocess

path = subprocess.check_output(["getconf", "DARWIN_USER_TEMP_DIR"], text=True).strip() + "control.sock"

def control(*words):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(path)
        s.sendall(json.dumps(words).encode() + b"\n")
        answer = json.loads(s.makefile().readline())
    if "error" in answer:
        raise RuntimeError(answer["error"])
    return answer["output"]

control("focus", "app", "Safari")
```

## Examples

A notification that brings you back to the terminal that sent it, with
[terminal-notifier](https://github.com/julienXX/terminal-notifier). Most terminals put the folder in the
window title:

```sh
terminal-notifier -message "Build done" -execute "$HOME/.local/bin/control focus title '${PWD##*/}'"
```

A key of another tool (skhd, Hammerspoon, Raycast, Karabiner) that opens your chat app wherever it is:

```sh
control focus app Slack || open -a Slack
```
