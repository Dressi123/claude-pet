# Mikkel

A desktop pet for macOS that reacts to what Claude Code is doing. Mikkel is the
navy-and-gold arctic fox hatched with the Codex `hatch-pet` skill, reusing that
spritesheet unchanged and driving it from Claude Code's hook system instead.

## What he does

He sits on the desktop above other windows and changes animation as Claude Code
works:

| Claude Code is doing            | Mikkel        |
| ------------------------------- | ------------- |
| starting a session              | waves         |
| thinking, or running most tools | works         |
| reading, searching, fetching    | inspects      |
| waiting for you to approve      | asks          |
| a tool failed                   | looks sad     |
| a subagent finished             | jumps         |
| nothing                         | idles         |

## Two playback modes

The states he sits in while Claude works, idle, working, inspecting and asking,
do not run as flipbooks. Flipping six poses a second reads as frantic when it
lasts for minutes. Instead he holds one pose for a few seconds, then cuts to
another at random, never repeating the pose he is already in.

The hold length is not uniform. About a third of the time he shifts quickly, the
way an animal glances up mid-rest; otherwise he settles. Measured over 30
seconds at the default Pace: twelve changes, from 1.0 to 4.5 seconds, averaging
2.7. A single fixed interval read as metronomic.

Locomotion and the one-shots, waving, jumping and the sad reaction, still run as
real animations. Those are brief and deliberate, and there the motion is the
whole point.

Two things keep him calm. He holds each pose for at least 0.6 seconds, because a
busy turn can publish a dozen state changes a second and without that floor he
strobes instead of reading as activity. And every frame duration is stretched by
the Pace setting, which defaults to 1.7x the atlas's own timings. Pace scales
both the animated frames and the held poses, and offers Lively, Steady, Relaxed
and Calm in the menu. At the default, a held pose lasts between 2.7 and 4.8
seconds.

A finished tool no longer resets the pose either. Claude is still busy after a
tool returns, so the pose set when the tool started stands until the next tool
or the end of the turn. Without that, a run of reads restarted the animation
twice per file.

When idle he follows the mouse pointer through the atlas's 16 look directions,
and falls back to the idle loop when the pointer is close by. Drag him and he
runs in the direction he is carried. Click him for his description.

Several Claude Code sessions can run at once, so each is tracked separately and
the pet shows whichever most deserves attention. "Waiting for you" outranks
"busy", which outranks "idle". The menu bar lists every live session and shows a
count when there is more than one.

A live session always outranks one that has gone quiet, whatever their states.
Without that rule a session killed while asking for approval kept the top
priority forever and froze the pet on "needs you" while ignoring the window
actually in use.

To watch one window only, right-click the pet or use the menu bar and pick a
session under Follow. Pick "All sessions" to go back. A pinned session releases
the pin when it ends, so the pet never goes permanently blank.

The menu is on the pet as well as the menu bar, because a status icon can be
pushed off a crowded menu bar or hidden behind the notch. Right-click or
control-click him.

Headless `claude -p` sessions are ignored by default. Hooks that start their own
Claude session, which is what a session-summary Stop hook does, would otherwise
keep the pet permanently busy with work nobody is watching. Interactive sessions
report entrypoint `cli` and headless ones report `sdk-cli`, and the hook helper
forwards that. Turn on "Follow background sessions" in the menu to see them.

## Install

```bash
./bundle.sh                                              # builds ~/Applications/Mikkel.app
open ~/Applications/Mikkel.app
"$HOME/Applications/Mikkel.app/Contents/MacOS/MikkelPet" --install-hooks
```

The hooks can also be toggled from the menu bar. To start him at login, add
Mikkel.app under System Settings, General, Login Items.

Remove the hooks with `--uninstall-hooks`, or from the same menu.

The installed hook records the absolute path of the helper inside the bundle, so
rerun `--install-hooks` after moving Mikkel.app somewhere else.

## How it hooks into Claude Code

`--install-hooks` appends a `mikkel-hook` command to eight events in
`~/.claude/settings.json`: `SessionStart`, `UserPromptSubmit`, `PreToolUse`,
`PostToolUse`, `Notification`, `SubagentStop`, `Stop` and `SessionEnd`.

Entries are appended to the arrays already there, so other hooks keep working,
and the file is backed up before every write.

`mikkel-hook` reads the payload on stdin, sends a small summary to the app over
a Unix datagram socket at `~/.mikkel-pet/pet.sock`, and exits. Datagrams mean it
never waits for a reader, so Claude Code is not slowed down when the pet is
closed. The helper exits 0 on every path, including bad JSON and a missing
socket, because a non-zero `PreToolUse` hook would block the tool call.

Only small identifying strings travel over the socket: the tool name, the tool's
own `description`, a command, a bare filename. File contents and command output
never leave the hook.

## One copy at a time

Launching Mikkel twice used to break him silently: the second copy took over the
socket, the first went deaf, and closing the duplicate left nothing listening at
all. A second copy now probes the socket, finds the first one answering, and
quits instead of taking over. A socket file left behind by a crash still refuses
the probe and is cleaned up as before.

## Detecting failures

Claude Code emits no `PostToolUse` when a tool fails. Confirmed by capturing
real payloads: three `PreToolUse` events against one failing command produced
only two `PostToolUse` events, and the failing call's `tool_use_id` was the one
missing.

So outstanding `tool_use_id`s are tracked per session and reconciled at turn
boundaries, `Stop` and the next `UserPromptSubmit`. Anything still unmatched
failed. Checking only at boundaries is what keeps parallel tool calls from
looking like failures. A tool that instead reports `is_error` in its response
is caught immediately.

Every event above was captured from a live session and checked against the
running pet, except `Notification`, whose text field could not be triggered on
demand. That path falls back to a generic label if the field is ever absent.

## Spritesheet corrections

Two rows differ from what `hatch-pet` last produced, both verified cell by cell
against the source atlases:

- **failed** is kept from the earlier generation. The newer take read as much
  flatter.
- **running-left** is derived by mirroring **running-right** in place, frame
  order preserved. The generated row had ghost fragments at the left edge of
  three cells. The skill sanctions mirroring for a symmetrical design, and
  Mikkel was drawn symmetrical so left and right travel could be mirrored.

Everything else is byte-identical to the current generated atlas.

## The spritesheet

Unchanged from `hatch-pet`, and the app enforces the v2 contract at load:
1536x2288, 8 columns by 11 rows, 192x208 cells. Rows 0-8 are animation states
with the contract's uneven per-frame durations. Rows 9 and 10 are the 16
clockwise look directions, where `000` is up, not front. Front-facing neutral is
row 0, column 6, which is also the menu bar icon.

Swapping in another hatched pet is a matter of replacing the two files in
`Sources/MikkelPet/Resources`.

## Layout

```
Sources/PetCore       state machine and atlas geometry, no AppKit, covered by tests
Sources/MikkelPet     the app: window, drawing, socket, hook installer
Sources/mikkel-hook   the tiny binary Claude Code actually runs
```

`swift test` covers the failure rule, session priority, pruning and the atlas
geometry.

## Debugging

`MIKKEL_PET_DEBUG=1` traces hook events, state changes and look indices to
stderr. `MIKKEL_PET_SOCKET` overrides the socket path for both binaries.
