# Look-direction blink rows for Mikkel

## The job

Produce **16 new cells: two complete 8-cell rows**, which are the existing look
direction rows with the eyes closed and nothing else changed.

- Source row 9 -> a new blink row (look directions 0-7).
- Source row 10 -> a new blink row (look directions 8-15).

## Why whole rows, not cells

`hatch-pet` already says this, and it is the whole risk of the job: never
package a newly generated one-off cell beside cells from another generation, and
if a look cell fails, correct the complete containing 8-frame row. A blink cell
is the same drawing with the eyes changed, and image models drift on fur
shading, ear angle, head tilt and body proportion. Drift shows up as a pop at
exactly the moment the blink fires, which looks worse than never blinking.

Generate each row in one pass, with the source row as the reference.

## The source

- `_row9-directions-0-7.png` and `_row10-directions-8-15.png` — the two source
  rows, 1536x208 each, transparent.
- `look-00-...` through `look-15-...` — the same 16 cells individually, 192x208,
  named with their atlas position and their angle. `look-00` is straight up /
  12 o'clock and the sequence runs clockwise.

The body is identical across a look row. Only the head angle, the eyes and the
muzzle change from cell to cell. That is what makes this tractable: the blink
variant of a cell is that cell with the eyelids closed, at the same head angle.

## Hard constraints

- 192x208 per cell, 8 cells per row, 1536x208 per row strip, transparent
  background, no padding changes.
- Same head angle, ear position, body, tail, fur shading, lighting, palette and
  contact shadow as the source cell. Same size and position in the frame.
- Eyes closed as a natural blink for this character, following the existing eye
  shape and keeping the orange eyebrow markings where they are.
- Do not restyle, recentre, rescale, crop, or add a background.

## Where it lands

The app's atlas is currently 12 rows (1536x2496): rows 0-8 states, 9-10 look
directions, 11 sleep. The two blink rows become **rows 12 and 13**, taking it to
14 rows, 1536x2912. Cell `n` of the blink rows must correspond to look direction
`n` of rows 9-10, in the same order.

Do not change rows 0-11. And leave `~/.codex/pets/mikkel` alone: it must stay at
11 rows, because Codex itself rejects a taller atlas. This extended sheet is for
the app only, the same way the sleep row already is.

## Acceptance

Each new cell gets flipped against its source at speed. If the fur, the outline,
the ears or the tail move, the row fails and gets regenerated as a row. Only the
eyelids may differ.

## What happens after

The pet holds a single still look cell for as long as the pointer is still,
which is where it spends nearly all of its idle time and why it currently almost
never blinks. With these rows, a blink during pointer watching becomes a ~110ms
swap to the same index in the blink row and back. I will wire that up.
