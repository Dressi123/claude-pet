# claude-pet

A desktop pet for macOS that reacts to what Claude Code is doing. He sits above
your other windows, changes pose as Claude works, and tells you in a speech
bubble what it is up to. He is a navy-and-gold fox, and he goes by no name.

<p align="center">
  <img src="docs/hero.png" alt="The pet working, with a speech bubble reading &quot;Let me run the test suite&quot; and a timer at 14 seconds" width="260">
  &nbsp;&nbsp;&nbsp;
  <img src="docs/asking.png" alt="The pet with a paw raised, saying Claude needs your permission to use Bash" width="330">
</p>

## Requirements

- macOS 13 or later
- A Swift 6 toolchain, which means Xcode or the Command Line Tools
- Claude Code

## Install

```bash
git clone <this repo>
cd claude-pet
./bundle.sh                                    # builds "~/Applications/Claude Pet.app"
open "$HOME/Applications/Claude Pet.app"
"$HOME/Applications/Claude Pet.app/Contents/MacOS/claude-pet" --install-hooks
```

`bundle.sh` signs the app with the first code-signing identity it finds, and
falls back to an ad-hoc signature. Ad-hoc works, but the app's identity is then
a hash of its own contents, so macOS treats every rebuild as a new app and asks
for permissions again. Pass `SIGN_ID` to choose an identity.

Hooks can also be installed and removed from the menu. The installed hook records
the absolute path of the helper inside the bundle, so rerun `--install-hooks`
after moving the app. `--uninstall-hooks` removes them.

To start him at login, add Claude Pet under System Settings, General, Login Items.

## What he does

| | | | | | | |
|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| <img src="docs/idle.png" width="84"> | <img src="docs/working.png" width="84"> | <img src="docs/inspecting.png" width="84"> | <img src="docs/waiting.png" width="84"> | <img src="docs/jumping.png" width="84"> | <img src="docs/failed.png" width="84"> | <img src="docs/asleep.png" width="84"> |
| idle | working | inspecting | asking | subagent done | something broke | asleep |

| Claude Code is doing            | The pet       |
| ------------------------------- | ------------- |
| starting a session              | waves         |
| thinking, or running most tools | works         |
| reading, searching, fetching    | inspects      |
| waiting for you to approve      | asks          |
| a tool failed                   | looks sad     |
| a subagent finished             | jumps         |
| nothing                         | idles         |

Several Claude Code sessions can run at once. Each is tracked separately and he
shows whichever most deserves attention: "waiting for you" outranks "busy",
which outranks "idle", and a live session always outranks one that has gone
quiet. The menu bar lists every live session and shows a count when there is
more than one.

After four minutes with nothing happening he curls up and sleeps. He also
settles at once when the last session closes. Any event wakes him, and so does
clicking him.

## What he says

The bubble never shows a tool name. `Bash: Stack the two bubble captures` is a
log line, not a pet, so he speaks in the first person instead.

| Claude is doing        | He says                         |
| ---------------------- | ------------------------------- |
| reading a file         | Let me look at Atlas.swift      |
| searching              | Hunting for socketPath          |
| editing                | Tidying up PetView.swift        |
| running a command      | Let me run the test suite       |
| asking permission      | Claude's own wording, verbatim  |
| a tool failed          | That didn't go through          |

An approval prompt keeps Claude's own message, because it says what is being
asked better than anything of ours would.

Each tool has a few phrasings, picked by a stable hash of the subject so the
wording cannot change while one tool call is still running.

He gets two balloons, and which one appears says what is happening before a word
of it is read. While working he **thinks**, in a scalloped cloud. When he is
addressing you he **speaks**, in a balloon with a hooked tail. The border picks
up the state: gold when he needs you, red when something broke, blue otherwise.

A header names the session the line came from, taken from its working directory,
so two Claude Code windows are told apart without opening the menu. Dots cycle
while he is busy and a clock appears once a job passes four seconds. A line that
stops changing fades after ten seconds, so a finished job does not leave "All
done" on screen all day.

## Using him

Right-click or control-click him for the menu, or use the menu bar icon. The
menu is on both because a status icon can be pushed off a crowded menu bar or
hidden behind the notch.

| Menu item | What it does |
| --- | --- |
| **Follow** | Pin him to one session, or "All sessions" to go back. A pinned session releases the pin when it ends. |
| **Watch the pointer** | When idle, he follows the mouse through 16 look directions. |
| **Hop when you hover** | He jumps when the pointer arrives over him. Fires on arrival, with a few seconds' cooldown. |
| **Follow background sessions** | Headless `claude -p` runs are ignored by default, since hooks that start their own session would keep him permanently busy with work nobody is watching. |
| **Send him away** | He walks off the nearer screen edge and his window hides. Wait for anything to change, or pick "Bring him back", and he walks back in the way he left. Not remembered across a restart. |
| **Size** | Small, Medium or Large. Half, three quarters or full size. |
| **Pace** | Lively, Steady, Relaxed or Calm. Stretches every frame duration; the default is 1.7x the atlas's own timings. |
| **Sleep when idle** | After 2, 4 or 10 minutes, or never. |
| **Install / Remove Claude Code hooks** | The same thing `--install-hooks` does. |

Drag him and he runs in the direction he is carried. Click him for his
description. Clicks land on his outline rather than the box he is drawn in, so
the empty corners around him pass through to whatever is underneath.

## Privacy

Only small identifying strings cross the socket: the tool name, the tool's own
`description`, a command, a bare filename. File contents and command output
never leave the hook.

## How it works

`--install-hooks` appends a `claude-pet-hook` command to eight events in
`~/.claude/settings.json`: `SessionStart`, `UserPromptSubmit`, `PreToolUse`,
`PostToolUse`, `Notification`, `SubagentStop`, `Stop` and `SessionEnd`. Entries
are appended to the arrays already there, so other hooks keep working, and the
file is backed up before every write.

`claude-pet-hook` reads the payload on stdin, sends a summary to the app over a Unix
datagram socket at `~/.claude-pet/pet.sock`, and exits. Datagrams mean it never
waits for a reader, so Claude Code is not slowed down when the pet is closed. The
helper exits 0 on every path, including bad JSON and a missing socket, because a
non-zero `PreToolUse` hook would block the tool call.

A second copy probes the socket, finds the first one answering, and quits rather
than taking over. A socket file left behind by a crash is cleaned up instead.

**Failures.** Claude Code emits no `PostToolUse` when a tool fails, so
outstanding `tool_use_id`s are tracked per session and reconciled at turn
boundaries. Anything still unmatched failed. Checking only at boundaries is what
keeps parallel tool calls from looking like failures. A tool that reports
`is_error` in its response is caught immediately.

**Animation.** Locomotion, waving and jumping run as flipbooks. Working,
inspecting, asking and the sad reaction instead hold one pose for a few seconds
and cut to another at random, because flipping six poses a second reads as
frantic when it lasts for minutes. He holds each pose for at least 0.6 seconds,
so a busy turn publishing a dozen changes a second does not make him strobe. At
the default Pace a held pose lasts between 2.7 and 4.8 seconds, and the sad
reaction ends after seven.

**Blinking.** Rows 12 to 17 are closed-eye twins of the look directions and the
held poses, swapped in for 130ms on a jittered schedule taken from the idle row.
Idle has no twin because its blink is drawn into the loop itself. A pose without
a twin simply does not blink rather than holding the feature back.

## Swapping in another pet

Replace `pet.json` and `spritesheet.png` in `Sources/ClaudePet/Resources`.
Those two files are the whole of it.

What governs the sheet is `PetState` in `Sources/PetCore/AnimationCatalog.swift`:

| Property | What it decides |
| --- | --- |
| `row` | which atlas row the state draws from |
| `durations` | milliseconds per frame, and its length sets how many of the eight columns the row uses |
| `playback` | flipbook, or hold a pose and cut |
| `blinkRow` | the row of closed-eye twins, if there is one |
| `AtlasGeometry` | cell size, column count, and where the look and sleep rows live |

The app counts rows rather than matching a fixed height. Eleven is the floor,
since that covers every state and look direction. Everything above it is optional
and degrades on its own, so a shorter sheet still loads: no sleep row means he
falls back to a still closed-eye pose, and no blink twins means he does not
blink. Adding a row is an edit to `AnimationCatalog` and nothing else.

## The spritesheet

1536x3744: 8 columns by 18 rows of 192x208 cells.

| Rows | Contents |
| --- | --- |
| 0-8 | animation states, with uneven per-frame durations |
| 9-10 | the 16 clockwise look directions, where `000` is up, not front |
| 11 | sleep |
| 12-13 | closed-eye twins of the look directions, split the same way |
| 14-17 | closed-eye twins of the working, inspecting, asking and sad poses |

Front-facing neutral is row 0, column 6, which is also the menu bar icon.

The artwork was originally hatched with the Codex `hatch-pet` skill, and two rows
differ from what it last produced. **failed** is kept from an earlier generation,
because the newer take read as flatter. **running-left** is mirrored from
**running-right** in place, because the generated row had ghost fragments at the
left edge of three cells. Everything else is byte-identical to the generated
atlas.

`art/` holds the source strips and the briefs used to generate the added rows,
plus `check-blink-row.py`, which measures a returned blink row against the row it
is a twin of. An image model asked to close the eyes will sometimes edit the file
and sometimes quietly redraw the character, and a redraw pops at exactly the
moment the blink fires.

## Development

```
Sources/PetCore       state machine and atlas geometry, no AppKit, covered by tests
Sources/ClaudePet     the app: window, drawing, socket, hook installer
Sources/claude-pet-hook   the tiny binary Claude Code actually runs
```

`swift test` covers the failure rule, session priority, pruning and the atlas
geometry.

`CLAUDE_PET_DEBUG=1` traces hook events, state changes and look indices to
stderr. `CLAUDE_PET_SOCKET` overrides the socket path for both binaries, and
`CLAUDE_PET_SETTINGS` points the hook installer at another file, which is the
only way to exercise it without editing the settings the machine is using.

`--snapshot <png>` renders one frame of the real view tree offscreen, and
`--film <dir>` renders a scripted sequence. Both exist because screen recording
is denied to the terminal, so there is otherwise no way to look at the pet while
working on it.

### Regenerating the README artwork

The sprite images under `docs/` are rendered straight from the atlas, so they
always match what the app draws:

```bash
swiftc -O docs/render-readme-art.swift -o /tmp/render-art
/tmp/render-art Sources/ClaudePet/Resources/spritesheet.png docs
```

The two balloon pictures come out of the app itself, so the artwork cannot drift
from the design:

```bash
export CLAUDE_PET_SNAPSHOT_BG=none CLAUDE_PET_SNAPSHOT_CROP=1
CLAUDE_PET_SNAPSHOT_SETTLE=6 .build/release/ClaudePet --snapshot docs/hero.png \
  "Let me run the test suite" "claude-pet" running
CLAUDE_PET_SNAPSHOT_SETTLE=3 .build/release/ClaudePet --snapshot docs/asking.png \
  "Claude needs your permission to use Bash" "second-brain" waiting
```

The settle time matters: a state waits out a dwell window before it commits, and
the elapsed clock only appears once a job passes four seconds.
