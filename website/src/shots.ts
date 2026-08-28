/**
 * Processed screenshot assets (public/shots/*.webp). Generated from shots-raw/ — see the Showcase agent's
 * build script. Full windows are 2000px wide (from 2360×1560 @2x captures, alpha corners kept); the rest are
 * tight detail crops at native @2x resolution. Reference by key; never hard-code paths.
 */
export type Shot = { readonly src: string; readonly width: number; readonly height: number; readonly alt: string };

export const shots = {
  // ── Full windows ──
  allLightsColor: { src: '/shots/all-lights-color.webp', width: 2000, height: 1322, alt: 'OpenHue All Lights view with the colour wheel selected' },
  allLightsWhite: { src: '/shots/all-lights-white.webp', width: 2000, height: 1322, alt: 'OpenHue All Lights view showing the colour-temperature slider, scene chips and per-light rows' },
  allLightsEffects: { src: '/shots/all-lights-effects.webp', width: 2000, height: 1322, alt: 'OpenHue All Lights view on the Effects tab: Candle, Fireplace, Prism and the Police effect driven from this Mac' },
  allLightsColorScrolled: { src: '/shots/all-lights-color-scrolled.webp', width: 2000, height: 1322, alt: 'OpenHue All Lights view scrolled to show the colour wheel, scene chips and per-light rows' },
  lightRight: { src: '/shots/light-right.webp', width: 2000, height: 1322, alt: 'OpenHue single-light view for the bulb named Right, colour wheel selected' },
  lightRightWhite: { src: '/shots/light-right-white.webp', width: 2000, height: 1322, alt: 'OpenHue single-light view for Right on the White tab with the colour-temperature slider' },
  lightRightEffects: { src: '/shots/light-right-effects.webp', width: 2000, height: 1322, alt: 'OpenHue single-light view for Right on the Effects tab' },
  scenes: { src: '/shots/scenes.webp', width: 2000, height: 1322, alt: 'OpenHue Scenes view with Hue stock scenes: Bright, Relax, Energize, Savanna Sunset, Tropical Twilight, Arctic Aurora' },
  timer: { src: '/shots/timer.webp', width: 2000, height: 1322, alt: 'OpenHue Timer view with rotary dials for All Lights and each bulb' },
  schedules: { src: '/shots/schedules.webp', width: 2000, height: 1322, alt: 'OpenHue Schedules view' },
  diagnostics: { src: '/shots/diagnostics.webp', width: 2000, height: 1322, alt: 'OpenHue Diagnostics view with raw characteristic dumps for each bulb' },
  addLight: { src: '/shots/add-light.webp', width: 2000, height: 1322, alt: 'OpenHue Add Light sheet scanning for bulbs' },
  // ── Settings (920px wide) ──
  settingsGeneral: { src: '/shots/settings-general.webp', width: 920, height: 776, alt: 'OpenHue Settings, General tab: Launch at login, Keep lights connected' },
  settingsSchedules: { src: '/shots/settings-schedules.webp', width: 920, height: 1236, alt: 'OpenHue Settings, Schedules tab: keep-awake, timer fade-out and missed-schedule windows' },
  settingsWakeMac: { src: '/shots/settings-wake-mac.webp', width: 920, height: 1216, alt: 'OpenHue Settings, Wake Mac tab: pmset scheduled wake' },
  settingsData: { src: '/shots/settings-data.webp', width: 920, height: 936, alt: 'OpenHue Settings, Data tab: storage folder, Disconnect all lights' },
  // ── Menu bar ──
  menubar: { src: '/shots/menubar.webp', width: 680, height: 574, alt: 'OpenHue menu-bar popover with All Lights, per-bulb toggles, scene chips and Disconnect All' },
  menubarContext: { src: '/shots/menubar-context.webp', width: 1200, height: 660, alt: 'OpenHue menu-bar popover open under the macOS menu bar' },
  // ── Detail crops ──
  wheel: { src: '/shots/wheel.webp', width: 620, height: 620, alt: 'The OpenHue colour wheel' },
  colorCard: { src: '/shots/color-card.webp', width: 1468, height: 696, alt: 'The Color card with the colour wheel' },
  ctCard: { src: '/shots/ct-card.webp', width: 1468, height: 250, alt: 'Colour-temperature slider from 2000 K to 6500 K' },
  dial: { src: '/shots/dial.webp', width: 580, height: 580, alt: 'The rotary timer dial set to 20 minutes' },
  timerCard: { src: '/shots/timer-card.webp', width: 1468, height: 684, alt: 'All Lights timer card: dial, Timer/Sleep mode, 5 min to 8 h presets and Start' },
  effectsGrid: { src: '/shots/effects-grid.webp', width: 1468, height: 614, alt: 'Effects grid: Candle, Fireplace, Prism, Sparkle, Opal, Glisten, Underwater, Cosmos, Sunbeam, Enchant, and Police from this Mac' },
  scenesGrid: { src: '/shots/scenes-grid.webp', width: 1836, height: 552, alt: 'Hue scene cards: Bright, Dimmed, Nightlight, Relax, Read, Concentrate, Energize, Savanna Sunset, Tropical Twilight, Arctic Aurora' },
  lightRows: { src: '/shots/light-rows.webp', width: 1468, height: 222, alt: 'Per-light rows for Right and Left with brightness sliders and toggles' },
  sceneChips: { src: '/shots/scene-chips.webp', width: 1468, height: 136, alt: 'Scene chips row: Bright, Dimmed, Nightlight, Relax, Read, Concentrate' },
  sidebar: { src: '/shots/sidebar.webp', width: 500, height: 740, alt: 'OpenHue sidebar: Lights, Library (Scenes, Timer, Schedules) and Tools (Diagnostics)' },
  lightHeader: { src: '/shots/light-header.webp', width: 1468, height: 160, alt: 'Light header: Right, LCA003 firmware 1.163.1, connected at -43 dBm, Identify' },
  diagRaw: { src: '/shots/diag-raw.webp', width: 1836, height: 175, alt: 'Raw characteristic dump: Capabilities 0001, Combined state 0007, Power-on default 1005' },
  diagPanel: { src: '/shots/diag-panel.webp', width: 1836, height: 855, alt: 'Diagnostics panel for one bulb: model, firmware, RSSI, decoded state, raw characteristics and power-on behaviour' },
  addLightSheet: { src: '/shots/add-light-sheet.webp', width: 1120, height: 1040, alt: 'Add Light sheet: scanning for bulbs, with pairing help' },
  wakeMac: { src: '/shots/wake-mac.webp', width: 860, height: 515, alt: 'Scheduled wake settings: days, time, Suggest from schedules' },
  pmsetCommand: { src: '/shots/pmset-command.webp', width: 860, height: 250, alt: 'The pmset repeat command OpenHue writes for a scheduled wake' },
  keepAwake: { src: '/shots/keep-awake.webp', width: 860, height: 382, alt: 'Sleep settings: keep this Mac awake while OpenHue runs or a timer counts down, timer fade-out' },
} as const satisfies Record<string, Shot>;

export type ShotKey = keyof typeof shots;

/** Aspect ratio string for CSS (`aspect-ratio: ${aspect(shots.x)}`). */
export const aspect = (s: Shot) => `${s.width} / ${s.height}`;
