import { useEffect, useRef } from 'react';
import { gsap, ScrollTrigger, reducedMotion } from '../lib/gsap';
import { useReveal } from '../hooks/useReveal';
import { shots, type Shot } from '../shots';
import './story.css';

const FACTS = [
  {
    k: 'Direct BLE GATT',
    v: 'The same protocol the Hue Bluetooth phone app speaks — service FE0F, light characteristics read and written straight from CoreBluetooth. No Bridge, no account, no Zigbee.',
  },
  {
    k: 'Schedules on the bulb — or the Mac',
    v: 'Wake-up and turn-off schedules are written into the bulb’s own memory and fire on its clock with the Mac asleep. Weekly routines, fades and timers run from macOS, with keep-awake and an optional pmset wake.',
  },
  {
    k: 'Swift 6 · macOS 14+',
    v: 'Native SwiftUI + CoreBluetooth, a 4 MB download. Open source on GitHub, with 102 unit tests covering the protocol, the colour maths and the scheduler.',
  },
] as const;

function Img({ s, eager }: { s: Shot; eager?: boolean }) {
  return (
    <img
      src={s.src}
      width={s.width}
      height={s.height}
      alt={s.alt}
      loading={eager ? 'eager' : 'lazy'}
      decoding="async"
      draggable={false}
    />
  );
}

/** Cursor tilt: rotates `target` toward the pointer while it is over `area`. Returns a disposer. */
function attachTilt(area: HTMLElement, target: HTMLElement, max: number) {
  if (!window.matchMedia('(hover: hover) and (pointer: fine)').matches) return () => {};
  const rx = gsap.quickTo(target, 'rotationX', { duration: 1.1, ease: 'power3.out' });
  const ry = gsap.quickTo(target, 'rotationY', { duration: 1.1, ease: 'power3.out' });
  const move = (e: PointerEvent) => {
    const r = area.getBoundingClientRect();
    const nx = ((e.clientX - r.left) / r.width) * 2 - 1;
    const ny = ((e.clientY - r.top) / r.height) * 2 - 1;
    ry(nx * max);
    rx(-ny * max * 0.7);
  };
  const leave = () => { rx(0); ry(0); };
  area.addEventListener('pointermove', move);
  area.addEventListener('pointerleave', leave);
  return () => {
    area.removeEventListener('pointermove', move);
    area.removeEventListener('pointerleave', leave);
  };
}

export default function Story() {
  const root = useReveal<HTMLElement>(0.1);
  const sceneRef = useRef<HTMLDivElement>(null);
  const stackRef = useRef<HTMLDivElement>(null);
  const tiltRef = useRef<HTMLDivElement>(null);
  const ctRef = useRef<HTMLElement>(null);
  const winRef = useRef<HTMLElement>(null);
  const menuRef = useRef<HTMLElement>(null);
  const dialRef = useRef<HTMLElement>(null);

  useEffect(() => {
    const scene = sceneRef.current, stack = stackRef.current, tilt = tiltRef.current;
    const ct = ctRef.current, win = winRef.current, menu = menuRef.current, dial = dialRef.current;
    if (!scene || !stack || !tilt || !ct || !win || !menu || !dial) return;

    const rm = reducedMotion();
    const mobile = window.matchMedia('(max-width: 720px)').matches;
    const amp = mobile ? 0.35 : 1; // rotation / parallax amplitude
    const zAmp = mobile ? 0.5 : 1; // depth spread (a phone's short perspective magnifies z)

    const ctx = gsap.context(() => {
      // Depth layers — a real 3D stack (sorted by translateZ inside preserve-3d wrappers).
      gsap.set(ct, { z: -180 * zAmp });
      gsap.set(win, { z: 0 });
      gsap.set(menu, { z: 170 * zAmp });
      gsap.set(dial, { z: 250 * zAmp });
      if (rm) return;

      const tl = gsap.timeline({
        defaults: { ease: 'none' },
        scrollTrigger: { trigger: scene, start: 'top bottom', end: 'bottom top', scrub: 0.9 },
      });
      // Whole stack drifts through perspective as it crosses the viewport…
      tl.fromTo(stack, { rotationX: 17 * amp, rotationY: -13 * amp, y: 70 * amp }, { rotationX: -6 * amp, rotationY: 5 * amp, y: -70 * amp }, 0);
      // …while each layer parallaxes at its own speed (nearer = faster).
      tl.fromTo(ct, { y: 40 * amp }, { y: -50 * amp }, 0);
      tl.fromTo(menu, { y: 120 * amp }, { y: -140 * amp }, 0);
      tl.fromTo(dial, { y: 170 * amp }, { y: -190 * amp }, 0);
    }, scene);

    const offTilt = rm || mobile ? () => {} : attachTilt(scene, tilt, 7);
    return () => {
      offTilt();
      ctx.revert();
      ScrollTrigger.refresh();
    };
  }, []);

  return (
    <section id="story" className="section story" ref={root} aria-labelledby="story-title">
      <div className="section__inner">
        <header className="story-head">
          <p className="eyebrow reveal">[ 01 — Overview ]</p>
          <h2 id="story-title" className="display story-title reveal" data-delay="1">
            No Bridge.<br />No cloud.<br />No phone.
          </h2>
          <p className="body story-lede reveal" data-delay="2">
            Hue bulbs sold in the last few years carry a Bluetooth radio — the one Signify’s own phone app
            uses. OpenHue speaks the same GATT protocol from your Mac: it discovers bulbs, pairs with them,
            reads and writes their state, stores schedules in the bulb itself, and runs timers and fades on the Mac’s clock. Nothing leaves
            the room.
          </p>
        </header>

        <div className="story-scene reveal" data-delay="2" ref={sceneRef} role="group" aria-label="OpenHue windows floating in perspective">
          <div className="story-glow" aria-hidden="true" />
          <div className="story-stack" ref={stackRef}>
            <div className="story-tilt" ref={tiltRef}>
              <figure className="story-layer story-layer--ct" ref={ctRef}>
                <Img s={shots.ctCard} />
                <figcaption className="story-cap">[ 2000 – 6500 K ]</figcaption>
              </figure>
              <figure className="story-layer story-layer--win" ref={winRef}>
                <Img s={shots.allLightsColor} />
                <figcaption className="story-cap">[ All Lights · 2 of 2 connected ]</figcaption>
              </figure>
              <figure className="story-layer story-layer--menu" ref={menuRef}>
                <Img s={shots.menubar} />
                <figcaption className="story-cap story-cap--right">[ Menu bar extra ]</figcaption>
              </figure>
              <figure className="story-layer story-layer--dial" ref={dialRef}>
                <Img s={shots.dial} />
                <figcaption className="story-cap">[ One turn = 1 h ]</figcaption>
              </figure>
            </div>
          </div>
        </div>

        <ul className="story-facts">
          {FACTS.map((f, i) => (
            <li className="story-fact reveal" data-delay={String(i + 1)} key={f.k}>
              <p className="story-fact__k">
                <span className="story-fact__n">0{i + 1}</span>
                <span className="mono">{f.k}</span>
              </p>
              <p className="story-fact__v">{f.v}</p>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
