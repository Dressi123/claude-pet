# The den, as a row he walks into

## What changed and why

The first den was a still tab at the screen edge in a window of its own, and
the pet's window passed behind it. Two problems, both structural.

It was 48 points wide against his 144, so it could never look like he went
inside it: he is three times its size. And with the den in one window and him
in another, whether he is in front of it or behind it is decided by window
ordering, which is a single choice for the whole sprite. He cannot be in front
of the door frame and behind the far wall at the same time, which is what
walking through a doorway actually looks like.

Both go away if the den and the fox are drawn together. Then he is in front of
whatever the artist puts him in front of, and the den is as big as it needs to
be for him to fit through it.

## The job

**Five cells side by side, each 192 x 208**, the same cell as every pose in the
spritesheet. The den is in all five, in exactly the same position and at exactly
the same size. Only the fox changes.

| Cell | What it shows |
|---|---|
| 0 | The den alone, mouth open and dark. Nobody in sight. |
| 1 | The fox beside it on the left, side on, facing right, about to go in. |
| 2 | Head and shoulders inside the mouth, back half still out. |
| 3 | Only his hindquarters and the tail still out. |
| 4 | The den alone again, but with his eyes and the tip of his nose catching the light inside the mouth. |

Played 0 to 4 he goes in. Played 4 to 0 he comes out. That is the whole
animation, and it is why the den may not move by a single pixel between cells:
it is on screen continuously while the fox changes underneath it.

**He passes in front of the near side of the mouth and behind the far side**,
which is the thing a separate window could never do.

## The den faces left

He runs rightwards to leave by the right-hand edge, so the mouth faces left and
he walks in from the left. It is mirrored for the other edge, so nothing may
depend on which way it faces.

## Size

Bigger than the first attempt, which was too small to be a door. The den should
fill roughly two thirds of the cell's width and most of its height, leaving room
on the left for him to stand beside it in cell 1. On screen at the default Size
that puts it near 100 points wide against his 144.

## The hard constraint, which is the same one the blink rows have

Generate all five in one pass. Image models drift on shading, proportion and
placement between separate generations, and here the drift lands on the den,
which is the part that must not move. A den that shifts two pixels between cells
reads as the whole world lurching every time he steps.

If five cells will not hold together, **three is worth more than five that
wobble**: den alone, him half in, and the eyes. Say so rather than sending five
that drift.

## What it has to look like

The pet is a 3D-rendered cartoon fox with a soft plush, almost felted surface,
matte rather than glossy, lit softly from the upper left. The fox in these cells
has to be that fox, not a new one, so attach **both** references in this folder.
They do different jobs.

- `_reference-fox.png` is him at twice size, front on and three-quarter. This is
  the material, the palette, the lighting and the face.
- `_reference-running.png` is three cells of the running row at twice size: the
  same fox in side profile, moving right, tail trailing behind him. This is the
  profile, the proportions and the tail, and it is the angle every cell of this
  animation is drawn from. Without it the model has only a front view to work
  from and invents a side.

Note what neither reference can give it. Nothing in the atlas shows him from
behind, because the look directions turn his head rather than his body. Cell 3,
where only his hindquarters and tail are still outside, is therefore the one
view he has never been drawn in, and the cell most likely to come back wrong.
If it does, drop it: den alone, him beside it, him half in, and the eyes still
reads as going inside.

- **Wood**, as in the version that worked: navy planks, cream arch, amber
  fittings. Palette `#1a2c4e` to `#204060` navy, `#e0a030` amber, cream trim.
- **No baked shadow**, no text, no lettering.
- **Flat magenta background**, `#FF00FF`. Not transparency, not a checkerboard.
  Magenta is nowhere near this palette, so it keys out exactly, and getting a
  real alpha channel out of it is this repo's problem rather than the model's.
- Do not ask the model for exact pixel dimensions. It cannot hit them and will
  distort the drawing trying. Any size, generous margin, cut here.

## The prompt

> Two images are attached, both of the same character. Match him exactly: the
> same fox, the same soft plush felted material, the same matte finish, the same
> soft light from the upper left, the same palette.
>
> The first is him front on and three-quarter, which is the material, the
> colours and the face. The second is him in side profile running to the right,
> tail trailing behind him. The second is the angle to draw him from in every
> panel below: match that profile, that tail and those proportions.
>
> Draw five panels in a row, left to right, on a flat solid magenta background,
> hex #FF00FF. Solid magenta everywhere the drawing is not. Do not draw a
> transparent background and do not draw a checkerboard.
>
> Every panel contains the same wooden den, drawn at exactly the same size and
> in exactly the same position in its panel, seen from the side with its arched
> mouth facing left and open onto darkness. The den must not move or change at
> all between panels. It is made of navy planks with a cream arch around the
> mouth and small amber fittings.
>
> What changes is the fox:
>
> 1. The den alone. No fox anywhere.
> 2. The fox standing to the left of the mouth, side on, facing right towards
>    it, about to walk in.
> 3. The fox halfway in: head and shoulders swallowed by the dark mouth, back
>    half and tail still outside. He passes in front of the near edge of the
>    arch.
> 4. Almost gone: only his hindquarters and tail still outside the mouth.
> 5. The den alone again, except that his two eyes and the tip of his nose catch
>    the light just inside the dark mouth.
>
> Render everything as 3D cartoon objects with a soft plush, felted, matte
> surface, the way a stitched toy looks. Deep navy blues around #1a2c4e to
> #204060, amber #e0a030 accents, cream trim. No other colours. No shadow on the
> ground, no text, no lettering.
>
> Leave a clear margin of magenta around and between the panels.

## When it comes back

Send it at whatever size it is. Keying the magenta, cutting the five cells,
checking the den has not moved between them and exporting the strip all happen
here. The den not moving is measured, not eyeballed.
