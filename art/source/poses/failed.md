# Blink twin for the failed row

## The job

Produce **one complete 8-cell row**: atlas row 5, the failure poses, with the
eyes closed and nothing else changed.

The source is `failed-row5.png`, **1536 x 208**: eight 192 x 208 cells side by
side, transparent background. This row uses all eight of the sheet's columns, so
the strip is a full row wide rather than the 1152 the held-pose strips were.

A failure is held rather than flipped through — its eight cells are eight ways
of looking glum and it stays up for seconds at a time — so without a twin he
simply stares while he is sad. That is the same reason asking, working and
inspecting got twins.

## Why the whole row in one pass

Never package a newly generated one-off cell beside cells from another
generation. A blink cell is the same drawing with the eyes changed, and image
models drift on fur shading, ear angle, head tilt and body proportion. Drift
shows up as a pop at exactly the moment the blink fires, which looks worse than
never blinking at all.

Generate the row in one pass, with `failed-row5.png` attached as the file being
edited. Do not ask for a cell at a time, and if a cell comes back wrong, correct
the complete containing 8-frame row.

## Edited in place, not redrawn

The file must come back at **exactly 1536 x 208 with transparency**. A returned
file at any other size was redrawn on a fresh canvas rather than edited, and a
redraw is useless here however good it looks on its own: cut against the
original at blink speed, the fur and the outline move and he changes shape every
time he blinks. Wrong dimensions means stop, not resize.

## Four of the eight cells are already closed

Counting from the left, zero-based:

| Cell | Pose | What to do |
|---|---|---|
| 0 | head bowed, lids already down | leave exactly as it is |
| 1 | sitting, looking up at you | close the eyes |
| 2 | sitting, head tilted | close the eyes |
| 3 | sighing, eyes already shut | leave exactly as it is |
| 4 | both paws over the face, no eyes visible at all | leave exactly as it is |
| 5 | lying flat, chin on the floor | close the eyes |
| 6 | sitting up, wide-eyed | close the eyes |
| 7 | slumped, eyes already shut | leave exactly as it is |

This matters more here than it did on the held-pose rows, where only two cells
of six were already closed. Half this row is already blinking. Asking for all
eight to change is asking for four cells to be redrawn for no reason, which is
precisely the drift this brief exists to prevent, so the carve-out is written
into the prompt itself rather than left as a footnote.

## The only change is the eyes

Eyelids closing as a natural blink for this character, following the existing
eye shape, with the orange eyebrow markings left exactly where they are. The
brows carry the sadness in this row; moved or reshaped, the twin stops matching
the pose it is a twin of. Everything else — fur shading, lighting, palette,
ears, muzzle, paws, chest fur, tail, body proportions, contact shadow, position
and size within the cell, and the transparent background — is untouched.

## The prompt

> Edit the attached PNG in place. Do not generate a new image.
>
> The attached file is 1536 x 208 pixels with a transparent background: eight
> 192 x 208 sprite cells of the same 3D-rendered cartoon fox, side by side, each
> in a different sad pose.
>
> Number the cells 0 to 7 from left to right.
>
> Change one thing only: close the eyes in cells 1, 2, 5 and 6. The eyelids
> should close naturally for this character, following the existing eye shape,
> keeping the orange eyebrow markings exactly where they are.
>
> Cells 0, 3, 4 and 7 already have the eyes closed or hidden. Leave those four
> cells completely untouched — do not redraw them, do not adjust them, do not
> improve them.
>
> Every other pixel must be unchanged. Same fox, same pose in each cell, same
> muzzle, same ears, same paws, same chest fur, same tail, same body
> proportions, same shading, same lighting, same palette, same contact shadow,
> same position and size within each cell, same transparent background.
>
> Do not redraw the character. Do not restyle, resize, recentre, crop, or add a
> background. Do not improve anything.
>
> Return the edited file at exactly 1536 x 208 pixels with transparency.

## Checking it

    python3 art/check-blink-row.py <returned.png> 5

Run it from the repo root. A real edit scores 0.0%; anything past about 1% will
visibly pop. If the returned file is not 1536 x 208 it was redrawn rather than
edited, and it will not pass, so there is no point going further with it.

## Where it lands

The sheet is 17 rows today (1536 x 3536): rows 0-8 states, 9-10 look directions,
11 sleep, 12-13 look blinks, 14-16 the working, inspecting and asking twins. A
failed twin becomes row 17. Nothing in the app reads it until `blinkRow` in
`AnimationCatalog.swift` says so, and that is a separate change from producing
the art.
