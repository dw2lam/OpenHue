#!/usr/bin/env bash
# generate-artwork.sh — regenerate the raw full-bleed OpenHue icon artwork with Codex image generation.
#
# Requires the codex-design-handoff dispatcher (Claude Code skill) and the Codex CLI:
#   ~/.claude/skills/codex-design-handoff/codex-skill.sh   (prepends the `brandkit` taste skill)
#
# Usage:  Icon/generate-artwork.sh [A|B|C]      (default: A)
#
# The v2 "RGB and flashy" direction. Codex saves the PNG into the current working directory
# (and a copy under ~/.codex/generated_images/...). Move the result to Icon/source/artwork.png
# and run Icon/build.sh to composite it onto the macOS icon grid.
set -euo pipefail
VARIANT="${1:-A}"
DISPATCH="$HOME/.claude/skills/codex-design-handoff/codex-skill.sh"
[[ -x "$DISPATCH" ]] || { echo "missing $DISPATCH" >&2; exit 1; }

SPINE='OVERRIDE THE SKILL DEFAULTS FOR THIS TASK: produce exactly ONE image, square 1:1 aspect ratio, 1024x1024. This is NOT a brand board, NOT a grid, NOT a mockup, NO text, NO labels, NO page numbers, NO typography, NO device frames, NO outer canvas or margins. The image is a single full-bleed, edge-to-edge piece of macOS app-icon ARTWORK with square corners (it will be masked into the Apple rounded-square icon shape by us later, so do not draw any rounded corners, borders, or icon frames). Save the final PNG into the current working directory.

SUBJECT: the app icon artwork for "OpenHue", a macOS app that controls Philips Hue Bluetooth smart bulbs. Show a single classic A19 light bulb, perfectly centred, upright, occupying roughly 60 percent of the image height, with a short dark screw base at the bottom. The bulb silhouette must stay clean and bold so it still reads as a light bulb at 32x32 pixels: smooth glass, no filament, no busy texture or pattern inside the glass, no text, no logos.

LOOK: RGB GAMING PERIPHERAL MARKETING, not muted product photography. Loud, flashy, high-contrast, hyper-saturated, energetic. The bulb glass is lit with a vivid FULL-SPECTRUM RGB gradient like an RGB LED light strip: electric red, hot magenta, violet, electric blue, cyan, neon green, yellow, flowing smoothly through the glass. A blazing neon halo and bright glow bloom radiate from the bulb into the darkness, with crisp streaks or rays of coloured light, plus small star sparkles and lens-flare highlights around the glass. Background is deep black-indigo (#05040f to #12103a) so the colours pop, with the glow fading to near-black at the corners. Still premium, Apple-quality craftsmanship: smooth gradients, a glossy highlight on the top of the glass, no cartoon outlines, no pixel art, no rainbow flag stripes, no grain, no noise.'

case "$VARIANT" in
  A) DETAIL='RGB STRIP + CHROMATIC RING. The spectrum runs vertically through the glass (yellow and green at the top of the dome, cyan and blue in the middle, violet, magenta and red toward the neck), like an RGB strip wrapped inside the bulb. Behind the bulb sits a saturated chromatic ring of light that cycles through the full RGB spectrum around the bulb, with thin bright radial light rays shooting outward from the ring, and a few small four-point star sparkles on the glass highlights. Save as openhue-v2-A.png.' ;;
  B) DETAIL='PRISM BURST. The glass holds a swirling, luminous full-spectrum gradient. From behind the bulb, big radiant beams of coloured light (red, magenta, blue, cyan, green, yellow) burst outward toward the edges of the image like a prism explosion or god-rays, brightest near the bulb and fading before the corners. A crisp horizontal anamorphic lens-flare streak crosses the bulb, and a handful of tiny sparkles float around it. Save as openhue-v2-B.png.' ;;
  C) DETAIL='WHITE-HOT CORE, RGB EDGES. The centre of the bulb glass is blazing white-hot, and the colour lives at the edges of the glass: the rim of the bulb glows in hyper-saturated RGB (cyan and blue on one side, magenta and red on the other, green and yellow at the top), bleeding outward into an intense multi-colour neon halo with soft light rays and a few star sparkles and a lens-flare glint at the top highlight. Maximum contrast between the white core and the electric coloured glow. Save as openhue-v2-C.png.' ;;
  *) echo "unknown variant $VARIANT (A|B|C)" >&2; exit 2 ;;
esac

"$DISPATCH" brandkit "$SPINE

VARIANT $VARIANT: $DETAIL"
