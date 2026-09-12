# The den he runs into when he is sent away

## What went wrong the first time, so it is not repeated

Two failures, both worth naming because both are the model doing what it was
asked rather than misunderstanding.

**It painted a checkerboard.** Asked for a transparent background, an image
model draws the grey-and-white checker it has seen behind ten thousand cut-out
stock images. That is pixels, not alpha, and it cannot be undone cleanly: the
checker sits behind every soft edge, so keying it out eats the anti-aliased rim
that makes the object look rendered rather than cut out.

The fix is to stop asking for transparency at all. Ask for a **flat magenta
background**, `#FF00FF`. Nothing in this palette is anywhere near magenta, so it
keys out exactly, edges and all. Transparency is a file format problem, and this
repo can solve file format problems.

**It was asked for exact pixel dimensions.** Image models cannot hit 192 x 208
and will distort the drawing trying. So do not ask. Let it render at whatever
size it likes, with room around the object, and cut the cells here.

The rule that follows from both: **ask the model only for the picture.** Size,
alignment, grid and alpha are all done locally afterwards.

## The job

One image, two dens side by side on flat magenta, generous margin around and
between them.

| Left | Right |
|---|---|
| The den, empty. Nobody home. | The same den, with him just inside: eyes and the tip of his nose in the shadow of the opening, nothing else. |

The empty one is what he runs into and back out of. The occupied one is what
stands there while he is gone, and the swap between them happens at the exact
moment his window goes, so he reads as arriving rather than vanishing.

That swap is the whole reason the two have to be the same den in the same
position at the same size, with nothing changed but what is looking out.
Generate both in one pass so they cannot drift apart, the same way the blink
rows are generated a whole row at a time. A difference of a few pixels between
them is a jump at exactly the moment you are looking at it.

## The shape

**Seen from the side, with the opening facing sideways**, so he can run
straight into it. Not a three-quarter view, and not the entrance facing the
camera: those are what the first attempts produced and neither lets him run in.

A small rounded den, the kind of soft kennel a toy fox would own, in profile,
with its arched mouth at one end and the body of it extending away behind. The
mouth faces **right**, so he runs in leftwards. It gets mirrored for the other
screen edge, so nothing may depend on which way it faces: no hinges, no latch,
no lettering, nothing that reads backwards.

## Slim is still the point

The pet is 144 points wide and his bubble is 256. Getting that off the screen is
the reason any of this exists, so a den that replaces him with a building has
moved the problem rather than solved it.

It is parked flush against the screen edge with its back half off the screen,
so what shows is the mouth and a little of the body. Keep it low and wide
rather than tall: it should sit no higher than his shoulder.

## What it has to look like

The pet is a 3D-rendered cartoon fox with a soft plush, almost felted surface,
matte rather than glossy, lit softly from the upper left. The den has to look
rendered by the same hand and in the same material. `_reference-fox.png` in this
folder is him at twice size, front on and side on. Attach it.

- **Palette**: his navy, roughly `#1a2c4e` through `#204060`, with the amber of
  his tail and eyebrows, `#e0a030`, and the cream of his muzzle for relief. No
  other hue, magenta background aside.
- **No baked shadow.** The pet cells have none and the window draws none, so a
  shadow here would float above a floor that is not there.
- **No text and no lettering.**
- It ends up about 100 points across, so fine stitching, small hinges and thin
  outlines all disappear. Bold shapes, few details.

## The prompt

> The attached image is a character. Match its style exactly: the same soft
> plush felted material, the same matte finish, the same soft light from the
> upper left, the same palette.
>
> Draw two small pet dens side by side on a **flat solid magenta background,
> hex #FF00FF**, filling the whole background. Do not draw a transparent
> background and do not draw a checkerboard. Solid magenta everywhere the dens
> are not.
>
> Both dens are the same object, drawn at the same size and in the same pose,
> **seen from the side, in profile, with the arched entrance facing right** so
> that an animal could run straight in from the right. The body of the den
> extends away to the left behind the entrance. It is low and wide, like a soft
> rounded kennel, not tall and not a house.
>
> In the left one the entrance is empty and dark. In the right one a small navy
> fox is just inside, so that only his eyes and the tip of his nose catch the
> light in the opening. Everything else about the two is identical.
>
> Render them as 3D cartoon objects with a soft plush, felted, matte surface,
> the way a stitched toy looks. Deep navy blues around #1a2c4e to #204060, amber
> #e0a030 accents, cream trim. No other colours. No shadow on the ground, no
> text, no lettering, no paw prints.
>
> Leave a clear margin of magenta around and between them.

## When it comes back

Send it over whatever size it is. Keying the magenta, cutting the two cells,
matching their alignment and exporting the strip all happen here.
