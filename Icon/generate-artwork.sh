#!/usr/bin/env bash
# generate-artwork.sh — regenerate the raw full-bleed icon artwork with Codex image generation.
#
# Requires the codex-design-handoff dispatcher (Claude Code skill) and the Codex CLI:
#   ~/.claude/skills/codex-design-handoff/codex-skill.sh   (prepends the `brandkit` taste skill)
#
# Usage:  Icon/generate-artwork.sh [A|B|C]      (default: A, the shipped variant)
#
# Codex writes the PNG to the current directory (and to ~/.codex/generated_images/...).
# Move the result to Icon/source/artwork.png and run Icon/build.sh to composite it.
set -euo pipefail
VARIANT="${1:-A}"
DISPATCH="$HOME/.claude/skills/codex-design-handoff/codex-skill.sh"
[[ -x "$DISPATCH" ]] || { echo "missing $DISPATCH" >&2; exit 1; }

SPINE='OVERRIDE THE SKILL DEFAULTS FOR THIS TASK: produce exactly ONE image, square 1:1 aspect ratio, 1024x1024. This is NOT a brand board, NOT a grid, NOT a mockup, NO text, NO labels, NO page numbers, NO typography, NO device frames, NO outer canvas or margins. The image is a single full-bleed, edge-to-edge piece of macOS app-icon ARTWORK with square corners (it will be masked into the Apple rounded-square icon shape by us later, so do not draw any rounded corners, borders, or icon frames).

SUBJECT: the app icon for "openHue", a native macOS app that controls Philips Hue Bluetooth smart bulbs. Show a single classic A19 light bulb silhouette, perfectly centred, upright, occupying roughly 60 percent of the image height, with a short screw base at the bottom. Keep the bulb shape simple, bold, and iconic so it still reads clearly when scaled down to 16x16 pixels: smooth frosted glass, clean outline, no filament detail, no fine lines, no sparkles, no particles, no lens flares, no reflections of rooms or objects.

BACKGROUND: a deep, rich indigo (#1a1740 area) fading to near-black (#07061a) toward the edges and bottom, smooth vertical/radial gradient, with a faint soft lighter glow just behind the bulb. No noise, no grain, no halftone, no scanlines.

COLOUR: the Philips Hue "spectrum" idea. A colourful hue gradient of warm amber (#ffb347) to hot magenta (#ff3d8a) to violet (#8b5cf6) to cyan (#22d3ee) used as the bulb glow. The glow should be soft, luminous, and blurred like real light in a dark room, not a hard rainbow, not a rainbow stripe, not a pride flag.

STYLE: modern macOS Tahoe / Liquid Glass app icon: soft translucent glass, gentle depth, subtle top highlight on the bulb glass, no hard bevels, no cartoon outlines, no flat clip-art, no 3D render of a real bulb photograph, no text. Premium, restrained, Apple-quality. Colours must be saturated and bright enough that the icon is recognisable at a glance in the Dock.'

case "$VARIANT" in
  A) DETAIL='The bulb GLASS ITSELF is filled with the spectrum gradient: warm amber near the neck, through magenta and violet in the middle, to cyan at the top of the dome, like a frosted glass bulb lit from inside with coloured light. Around the bulb a soft white-to-coloured halo bleeds into the dark background. The screw base is smooth dark graphite with a subtle brushed-metal highlight.' ;;
  B) DETAIL='The bulb is milky white frosted glass with a soft warm-white inner glow. BEHIND the bulb sits a large soft ring of light, like a blurred hue colour wheel: the ring cycles amber, magenta, violet, cyan around the bulb, heavily blurred so it reads as an atmospheric halo, not a sharp ring. The screw base is matte dark graphite.' ;;
  C) DETAIL='The bulb glass is a soft gradient from warm amber (bottom of the glass) to violet to cyan (top of the dome), glowing outward with a soft coloured halo. To the right of the bulb, two faint, thin, concentric arc waves (like a subtle wireless/Bluetooth signal) radiate outward in soft cyan, very subtle and elegant, not clip-art, no Bluetooth logo, no text. The screw base is smooth dark graphite.' ;;
  *) echo "unknown variant $VARIANT (A|B|C)" >&2; exit 2 ;;
esac

"$DISPATCH" brandkit "$SPINE

VARIANT $VARIANT: $DETAIL"
