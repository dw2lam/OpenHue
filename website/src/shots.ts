/**
 * Processed screenshot assets (public/shots/*.webp), built from shots-raw2/ — ⌘⇧4-Space style captures
 * WITH the native macOS shadow and transparent margins (bulbs at warm white 2695 K · 95 %).
 *
 * Full windows: 2584×1784 source canvas (2360×1560 window at (112,76)) → 2000×1381, alpha kept, full shadow.
 * Detail crops: native @2x, cut with a rounded mask (or a circle) + a synthetic soft shadow.
 *
 * `canvas` + `box` describe the rect this image covers in its source canvas (px), so live overlays can be
 * positioned by geometry: a control measured at (x, y, w, h) in the source lands at
 * left = (x − box[0]) / (box[2] − box[0]) etc. — see src/components/live.tsx `place()`.
 */
export type Canvas = 'win' | 'menubar' | 'settings-general' | 'settings-schedules' | 'settings-wake-mac' | 'settings-data';
export type Shot = {
  readonly src: string;
  readonly width: number;
  readonly height: number;
  readonly alt: string;
  readonly canvas: Canvas;
  /** [x0, y0, x1, y1] in source-canvas px (includes the shadow margin) */
  readonly box: readonly [number, number, number, number];
};

const WIN: readonly [number, number, number, number] = [0, 0, 2584, 1784];

export const shots = {
  // ── Full windows (2000×1381, shadow included) ──
  allLightsWhite: { src: '/shots/all-lights-white.webp', width: 2000, height: 1381, canvas: 'win', box: WIN, alt: 'OpenHue All Lights view: White tab with the colour-temperature slider at 2695 K, scene chips and per-light rows' },
  allLightsColor: { src: '/shots/all-lights-color.webp', width: 2000, height: 1381, canvas: 'win', box: WIN, alt: 'OpenHue All Lights view with the colour wheel selected' },
  allLightsEffects: { src: '/shots/all-lights-effects.webp', width: 2000, height: 1381, canvas: 'win', box: WIN, alt: 'OpenHue All Lights view on the Effects tab: Candle, Fireplace, Prism … and Police, driven from this Mac' },
  lightRight: { src: '/shots/light-right.webp', width: 2000, height: 1381, canvas: 'win', box: WIN, alt: 'OpenHue single-light view for the bulb named Right, a go-to-sleep fade running' },
  lightRightColor: { src: '/shots/light-right-color.webp', width: 2000, height: 1381, canvas: 'win', box: WIN, alt: 'OpenHue single-light view for Right on the Color tab' },
  lightRightEffects: { src: '/shots/light-right-effects.webp', width: 2000, height: 1381, canvas: 'win', box: WIN, alt: 'OpenHue single-light view for Right on the Effects tab' },
  scenes: { src: '/shots/scenes.webp', width: 2000, height: 1381, canvas: 'win', box: WIN, alt: 'OpenHue Scenes view: eleven Hue scene cards from Bright to Spring Blossom, plus My scenes' },
  timer: { src: '/shots/timer.webp', width: 2000, height: 1381, canvas: 'win', box: WIN, alt: 'OpenHue Timer view: the All Lights dial counting down in Sleep mode, and a 20-minute preset on Right and Left' },
  schedules: { src: '/shots/schedules.webp', width: 2000, height: 1381, canvas: 'win', box: WIN, alt: 'OpenHue Schedules view: on-the-bulb wake-up schedules for Right and Left' },
  diagnostics: { src: '/shots/diagnostics.webp', width: 2000, height: 1381, canvas: 'win', box: WIN, alt: 'OpenHue Diagnostics view with RSSI, firmware, decoded state and raw characteristic dumps' },
  addLight: { src: '/shots/add-light.webp', width: 2000, height: 1381, canvas: 'win', box: WIN, alt: 'OpenHue Add Light sheet scanning for bulbs over the All Lights window' },
  // ── Settings (native 1144 wide) and the menu-bar popover (772×674) ──
  settingsGeneral: { src: '/shots/settings-general.webp', width: 1144, height: 1000, canvas: 'settings-general', box: [0, 0, 1144, 1000], alt: 'OpenHue Settings, General: Launch at login, Keep lights connected' },
  settingsSchedules: { src: '/shots/settings-schedules.webp', width: 1144, height: 1460, canvas: 'settings-schedules', box: [0, 0, 1144, 1460], alt: 'OpenHue Settings, Schedules: keep-awake, timer fade-out and missed-schedule windows' },
  settingsWakeMac: { src: '/shots/settings-wake-mac.webp', width: 1144, height: 1440, canvas: 'settings-wake-mac', box: [0, 0, 1144, 1440], alt: 'OpenHue Settings, Wake Mac: pmset scheduled wake' },
  settingsData: { src: '/shots/settings-data.webp', width: 1144, height: 1160, canvas: 'settings-data', box: [0, 0, 1144, 1160], alt: 'OpenHue Settings, Data: storage folder, Disconnect all lights' },
  menubar: { src: '/shots/menubar.webp', width: 772, height: 674, canvas: 'menubar', box: [0, 0, 772, 674], alt: 'OpenHue menu-bar popover: All Lights, a running timer, per-bulb toggles, scene chips and Disconnect All' },
  // ── Detail crops (native @2x, rounded + shadow) ──
  ctCard: { src: '/shots/ct-card.webp', width: 1584, height: 386, canvas: 'win', box: [738, 538, 2322, 924], alt: 'Colour-temperature card: a 2000 – 6500 K slider set to 2695 K' },
  colorCard: { src: '/shots/color-card.webp', width: 1584, height: 832, canvas: 'win', box: [738, 538, 2322, 1370], alt: 'Color card with the colour wheel' },
  wheel: { src: '/shots/wheel.webp', width: 664, height: 684, canvas: 'win', box: [1198, 638, 1862, 1322], alt: 'The OpenHue colour wheel' },
  timerCard: { src: '/shots/timer-card.webp', width: 1584, height: 827, canvas: 'win', box: [738, 326, 2322, 1153], alt: 'All Lights timer card: the dial counting down in Sleep mode, presets from 5 min to 8 h, +5 min and Cancel' },
  dial: { src: '/shots/dial.webp', width: 648, height: 668, canvas: 'win', box: [782, 441, 1430, 1109], alt: 'The rotary timer dial, counting down' },
  effectsCard: { src: '/shots/effects-card.webp', width: 1584, height: 750, canvas: 'win', box: [738, 538, 2322, 1288], alt: 'Effects card: Candle, Fireplace, Prism, Sparkle, Opal, Glisten, Underwater, Cosmos, Sunbeam, Enchant — and Police, from this Mac' },
  scenesGrid: { src: '/shots/scenes-grid.webp', width: 1984, height: 904, canvas: 'win', box: [538, 202, 2522, 1106], alt: 'Hue scene cards: Bright, Dimmed, Nightlight, Relax, Read, Concentrate, Energize, Savanna Sunset, Tropical Twilight, Arctic Aurora, Spring Blossom' },
  sceneChips: { src: '/shots/scene-chips.webp', width: 1584, height: 236, canvas: 'win', box: [738, 1026, 2322, 1262], alt: 'Scene chips: Bright, Dimmed, Nightlight, Relax, Read, Concentrate' },
  lightRows: { src: '/shots/light-rows.webp', width: 1584, height: 333, canvas: 'win', box: [738, 1161, 2322, 1494], alt: 'Per-light rows for Right and Left with brightness sliders and toggles' },
  sidebar: { src: '/shots/sidebar.webp', width: 620, height: 794, canvas: 'win', box: [40, 100, 660, 894], alt: 'OpenHue sidebar: All Lights, Right, Left; Scenes, Timer, Schedules; Diagnostics' },
  lightHeader: { src: '/shots/light-header.webp', width: 1604, height: 308, canvas: 'win', box: [728, 146, 2332, 454], alt: 'Light header: Right, LCA003 · 1.163.1, Connected · −47 dBm, Identify' },
  fadeCard: { src: '/shots/fade-card.webp', width: 1584, height: 292, canvas: 'win', box: [738, 316, 2322, 608], alt: 'Go-to-sleep fade running, with a progress bar and Stop' },
  diagPanel: { src: '/shots/diag-panel.webp', width: 1948, height: 1072, canvas: 'win', box: [556, 461, 2504, 1533], alt: 'Diagnostics panel for Right: model, firmware, RSSI, decoded state, raw characteristics 0001 / 0007 / 1005, bulb clock and power-on behaviour' },
  addLightSheet: { src: '/shots/add-light-sheet.webp', width: 1272, height: 1196, canvas: 'win', box: [700, 298, 1972, 1494], alt: 'Add Light sheet: scanning, Left found at −57 dBm, pairing help' },
  wakeMac: { src: '/shots/wake-mac.webp', width: 984, height: 505, canvas: 'settings-wake-mac', box: [80, 284, 1064, 789], alt: 'Wake this Mac for schedules: days, time, Suggest from schedules' },
  pmset: { src: '/shots/pmset.webp', width: 984, height: 346, canvas: 'settings-wake-mac', box: [80, 869, 1064, 1215], alt: 'The pmset repeat command OpenHue writes for a scheduled wake' },
} as const satisfies Record<string, Shot>;

export type ShotKey = keyof typeof shots;

/** Aspect ratio string for CSS (`aspect-ratio: ${aspect(shots.x)}`). */
export const aspect = (s: Shot) => `${s.width} / ${s.height}`;
