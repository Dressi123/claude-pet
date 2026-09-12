# Blink twins for the held poses

Same job as the look directions, which worked. Three strips, one per state.

| File | State | What he is doing |
|---|---|---|
| `waiting-row6.png` | asking | waiting on you for a decision |
| `running-row7.png` | working | running a tool |
| `review-row8.png` | inspecting | reading or searching |

Each strip is **1152 x 208**: six 192 x 208 cells side by side, transparent
background. These rows use six of the sheet's eight columns, so the strips are
narrower than the look rows were. Return the same 1152 x 208 canvas.

## The prompt

> Edit the attached PNG in place. Do not generate a new image.
>
> The attached file is 1152 x 208 pixels with a transparent background: six
> 192 x 208 sprite cells of the same 3D-rendered cartoon fox, side by side, each
> in a different pose.
>
> Change one thing only: close the eyes in all six cells, as in a blink. The
> eyelids should close naturally for this character, following the existing eye
> shape, keeping the orange eyebrow markings exactly where they are.
>
> Every other pixel must be unchanged. Same fox, same pose in each cell, same
> muzzle, same ears, same paws, same chest fur, same tail, same body
> proportions, same shading, same lighting, same palette, same contact shadow,
> same position and size within each cell, same transparent background.
>
> Do not redraw the character. Do not restyle, resize, recentre, crop, or add a
> background. Do not improve anything.
>
> Return the edited file at exactly 1152 x 208 pixels with transparency.

## Two cells already have closed eyes

`running-row7.png` cell 4 and `review-row8.png` cell 4 are drawn with the eyes
closed already. Leave them exactly as they are; their twin is themselves.

## Checking it

    python3 art/check-blink-row.py <returned.png> <6|7|8>

It passes at 0.0%. If the returned file is not 1152 x 208 it was redrawn rather
than edited, and it will not pass, so there is no point going further with it.

## Save it under a new name

The returned file goes in `art/blink/`, named for the row it is a twin of. Do
not save it over the source strip in this folder, however tempting the Save
dialog makes it. That has happened three times: the source is overwritten by its
own twin, the Finder leaves the original beside it as a "copy", and the file
named after the source row is now the closed-eye art. Nothing warns you, because
a twin passes every check a source would.

The sheet is the real source in the end, so this is recoverable by re-cropping
the row. It is still an afternoon of confusion nobody needs.
