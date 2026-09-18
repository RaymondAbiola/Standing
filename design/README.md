# Standing brand assets

The mark is two brackets holding a pill: a charge held in escrow through its reversal window. Concept "Hold".

## Files

### SVG (`svg/`)

| File | Use |
|---|---|
| `mark.svg` | Mark on light backgrounds |
| `mark-dark.svg` | Mark on dark backgrounds |
| `mark-black.svg` | Single colour, all ink |
| `mark-white.svg` | Single colour, all white |
| `lockup.svg` | Mark plus wordmark, light backgrounds |
| `lockup-dark.svg` | Mark plus wordmark, dark backgrounds |
| `favicon.svg` | Thicker strokes and tighter margins, for 16 to 32 px |
| `avatar.svg` | Square, ink ground, for social profiles |

Both lockups carry Space Grotesk Bold embedded as base64, so they render correctly anywhere without the font installed. That is why they are around 18 KB rather than under 1 KB.

### PNG (`png/`)

All transparent except the avatars, which carry the ink ground.

- `mark-64/128/256/512/1024.png`
- `mark-dark-256/512/1024.png`
- `mark-black-512.png`, `mark-white-512.png`
- `favicon-16/32/48/64/180.png` (180 is the iOS touch icon)
- `avatar-512.png`, `avatar-1024.png`
- `lockup-252x64/504x128/1008x256/2016x512.png`
- `lockup-dark-504x128/1008x256.png`

## Colour

| Token | Hex | Use |
|---|---|---|
| Ink | `#14181C` | Mark and wordmark on light, dark grounds |
| Paper | `#F7F6F3` | Light ground |
| Bone | `#F2F1EE` | Mark and wordmark on dark |
| Accent | `#12B886` | The held charge, on light grounds |
| Accent bright | `#2FD8A8` | The held charge, on dark grounds |

The accent is deliberately not Arbitrum blue, so Standing reads as its own brand rather than an ecosystem sub-project.

## Type

Wordmark is Space Grotesk Bold at minus 0.03 em tracking. The Bold latin subset is in `fonts/` for reference, and it is licensed under the SIL Open Font License, so embedding and redistribution are permitted.

## Rules

- Keep clear space around the mark equal to the width of one bracket arm.
- Never recolour the pill to anything but an accent value. The pill is the held charge and it carries the meaning.
- Use `favicon.svg` below 32 px. The standard mark has strokes too fine to survive at that size.
- Do not add a gradient, a shadow, or an outline to the mark.

## Regenerating the PNGs

No SVG rasteriser is installed on this machine. The PNGs were produced with headless Chrome:

```
google-chrome --headless --disable-gpu --hide-scrollbars \
  --default-background-color=00000000 --window-size=512,512 \
  --screenshot=out.png file:///path/to/wrapper.html
```

where the wrapper is a zero-margin HTML page holding the SVG in an `img` at the target size.
