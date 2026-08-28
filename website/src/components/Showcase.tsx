import { useEffect, useRef, useState } from 'react';
import { gsap, ScrollTrigger, reducedMotion } from '../lib/gsap';
import { useReveal } from '../hooks/useReveal';
import { shots, type Shot, type ShotKey } from '../shots';
import './showcase.css';

type Chapter = {
  rail: string;
  title: string;
  body: string;
  tags: readonly string[];
  card: ShotKey;
  detail: ShotKey;
  cap: string;
};

const CHAPTERS: readonly Chapter[] = [
  {
    rail: 'Lights',
    title: 'Lights & colour',
    body: 'Power, brightness, colour temperature from 2000 to 6500 K and full xy colour — per bulb, or for All Lights at once. Bulbs stay connected, so a change lands the moment you let go of the wheel.',
    tags: ['xy colour', '153 – 500 mireds', 'per-light / all lights'],
    card: 'allLightsColor',
    detail: 'wheel',
    cap: '[ xy · characteristic 0005 ]',
  },
  {
    rail: 'Scenes',
    title: 'Scenes',
    body: 'Hue’s stock scenes — Bright, Relax, Energize, Savanna Sunset, Tropical Twilight, Arctic Aurora — one click away, plus your own snapshots with “Save current as scene…”.',
    tags: ['11 Hue scenes', 'snapshots', 'chips in every view'],
    card: 'scenes',
    detail: 'scenesGrid',
    cap: '[ Hue scenes · stock + yours ]',
  },
  {
    rail: 'Effects',
    title: 'Effects, and a Police light bar',
    body: 'The bulb’s built-in effects — Candle, Fireplace, Prism, Sparkle, Opal, Glisten, Underwater, Cosmos, Sunbeam, Enchant — and one driven from this Mac: Police, a red/blue strobe alternating between bulbs. Touch any control and it stops, restoring the previous state.',
    tags: ['10 bulb effects', 'Police · from this Mac', 'auto-restore'],
    card: 'allLightsEffects',
    detail: 'effectsGrid',
    cap: '[ tag 06 · 01 Candle … 11 Enchant ]',
  },
  {
    rail: 'Timer',
    title: 'Timer, on a rotary dial',
    body: 'Turn the dial — one turn is an hour, keep going for more — or tap a preset from 5 min to 8 h. Timer mode switches off at the end with a short fade; Sleep mode dims over the whole countdown. It survives a relaunch and keeps the Mac awake until it fires.',
    tags: ['5 min … 8 h', 'Timer / Sleep', '+5 min', 'per bulb'],
    card: 'timer',
    detail: 'dial',
    cap: '[ one turn = 1 h ]',
  },
  {
    rail: 'Schedules',
    title: 'Schedules, fades, Wake Mac',
    body: 'Two kinds, side by side. On the bulb: a wake-up or turn-off stored in the bulb’s own memory, fired by its clock with the Mac asleep and the phone away — and the Hue app’s routines listed next to it. On this Mac: weekly or one-off, wake-up fade-in, go-to-sleep fade-out, keep-awake and an optional pmset wake for laptops.',
    tags: ['wake-up fade-in', 'go-to-sleep fade-out', 'pmset wakeorpoweron', 'missed-schedule grace'],
    card: 'schedules',
    detail: 'wakeMac',
    cap: '[ pmset repeat wakeorpoweron ]',
  },
  {
    rail: 'Menu bar',
    title: 'The menu bar extra',
    body: 'All Lights, each bulb’s toggle and brightness, scene chips, an “Off in…” timer with the live countdown, and Disconnect All to hand a bulb back to the phone app — without opening the window.',
    tags: ['menu bar', 'Off in…', 'Disconnect All'],
    card: 'allLightsWhite',
    detail: 'menubar',
    cap: '[ menu bar extra ]',
  },
  {
    rail: 'Diagnostics',
    title: 'Diagnostics, down to the bytes',
    body: 'Bluetooth state, RSSI, firmware, decoded state, and every characteristic with its last raw value. Raw read/write, a power-on-default writer, and a live log that mirrors the app’s unified log.',
    tags: ['raw characteristic dump', 'power-on default 1005', 'live log'],
    card: 'diagnostics',
    detail: 'diagPanel',
    cap: '[ 0001 · 0007 · 1005 ]',
  },
];

const STRIP = [
  { key: 'ctCard', cap: '[ Colour temperature · 2000 – 6500 K ]', speed: 0.7 },
  { key: 'addLightSheet', cap: '[ Add Light · scanning for FE0F ]', speed: 1.35 },
  { key: 'lightRows', cap: '[ Per-light rows ]', speed: 0.9 },
  { key: 'pmsetCommand', cap: '[ pmset repeat wakeorpoweron ]', speed: 1.2 },
  { key: 'lightHeader', cap: '[ LCA003 · 1.163.1 · −43 dBm ]', speed: 0.8 },
] as const satisfies readonly { key: ShotKey; cap: string; speed: number }[];

const N = CHAPTERS.length;
const HOLD = 0.4; // fraction of each chapter's scroll spent resting before the shuffle
const D = 1 - HOLD; // transition length
const pad2 = (n: number) => String(n + 1).padStart(2, '0');

function Img({ s, eager }: { s: Shot; eager?: boolean }) {
  return (
    <img src={s.src} width={s.width} height={s.height} alt={s.alt} loading={eager ? 'eager' : 'lazy'} decoding="async" draggable={false} />
  );
}

/** Position `p` in the deck (0 = front). Cards recede up-right and fade. */
function cardState(p: number) {
  return {
    x: 58 * p,
    y: -40 * p,
    z: -180 * p,
    rotationY: -10,
    rotationX: 4,
    rotationZ: 0,
    opacity: p === 0 ? 1 : Math.max(0, 1 - 0.3 * p),
    xPercent: -50,
    yPercent: -50,
  };
}
const posOf = (k: number, active: number) => (k - active + N) % N;

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

/** True when the pinned scrollytelling must be replaced by a static, stacked layout. */
function useStatic() {
  const query = '(max-width: 900px)';
  const [s, setS] = useState(() => window.matchMedia(query).matches || reducedMotion());
  useEffect(() => {
    const mqs = [window.matchMedia(query), window.matchMedia('(prefers-reduced-motion: reduce)')];
    const on = () => setS(mqs.some((m) => m.matches));
    mqs.forEach((m) => m.addEventListener('change', on));
    return () => mqs.forEach((m) => m.removeEventListener('change', on));
  }, []);
  return s;
}

/* ── Pinned scrollytelling (desktop) ─────────────────────────── */
function Scrolly() {
  const pinRef = useRef<HTMLDivElement>(null);
  const stageRef = useRef<HTMLDivElement>(null);
  const deckRef = useRef<HTMLDivElement>(null);
  const railRef = useRef<HTMLDivElement>(null);
  const stRef = useRef<ScrollTrigger | null>(null);
  const tlRef = useRef<gsap.core.Timeline | null>(null);

  useEffect(() => {
    const pin = pinRef.current, stage = stageRef.current, deck = deckRef.current, rail = railRef.current;
    if (!pin || !stage || !deck || !rail) return;
    const cards = Array.from(deck.querySelectorAll<HTMLElement>('.sc-card'));
    const details = Array.from(deck.querySelectorAll<HTMLElement>('.sc-detail'));
    const texts = Array.from(pin.querySelectorAll<HTMLElement>('.sc-chapter'));
    const railBtns = Array.from(rail.querySelectorAll<HTMLElement>('.sc-rail__btn'));
    let last = -1;
    const setActive = (idx: number) => {
      if (idx === last) return;
      last = idx;
      railBtns.forEach((b, i) => {
        b.classList.toggle('is-active', i === idx);
        b.setAttribute('aria-current', i === idx ? 'step' : 'false');
      });
    };

    const ctx = gsap.context(() => {
      // Resting states for chapter 0.
      cards.forEach((c, k) => gsap.set(c, cardState(k)));
      gsap.set(details, { opacity: 0, y: 48, z: -40, scale: 0.94 });
      gsap.set(details[0], { opacity: 1, y: 0, z: 220, scale: 1 });
      gsap.set(texts, { opacity: 0, y: 28 });
      gsap.set(texts[0], { opacity: 1, y: 0 });

      const tl = gsap.timeline({ paused: true, defaults: { ease: 'power2.inOut' } });
      for (let t = 0; t < N - 1; t++) {
        const T0 = t + HOLD;
        cards.forEach((c, k) => {
          if (k === t) {
            // The front card swipes out down-right, then re-enters at the back of the deck.
            tl.to(c, {
              keyframes: [
                { x: 200, y: 130, z: 170, rotationZ: 7, rotationY: -18, opacity: 0, duration: D * 0.55, ease: 'power2.in' },
                { ...cardState(N - 1), duration: D * 0.45, ease: 'none' },
              ],
            }, T0);
          } else {
            tl.to(c, { ...cardState(posOf(k, t + 1)), duration: D }, T0);
          }
        });
        tl.to(details[t], { opacity: 0, y: -70, z: 320, scale: 1.05, duration: D * 0.5, ease: 'power2.in' }, T0);
        tl.to(details[t + 1], { opacity: 1, y: 0, z: 220, scale: 1, duration: D * 0.6, ease: 'power3.out' }, T0 + D * 0.4);
        tl.to(texts[t], { opacity: 0, y: -24, duration: D * 0.45, ease: 'power2.in' }, T0);
        tl.to(texts[t + 1], { opacity: 1, y: 0, duration: D * 0.55, ease: 'power3.out' }, T0 + D * 0.45);
      }
      tl.to({}, { duration: HOLD }, N - 1); // final rest
      tlRef.current = tl;

      stRef.current = ScrollTrigger.create({
        trigger: pin,
        pin: true,
        start: 'top top',
        end: () => '+=' + Math.round((N - 1 + HOLD) * 0.85 * window.innerHeight),
        scrub: 0.7,
        animation: tl,
        anticipatePin: 1,
        invalidateOnRefresh: true,
        onUpdate: (self) => {
          const time = self.progress * tl.duration();
          setActive(Math.min(N - 1, Math.round(Math.max(0, time - HOLD / 2))));
        },
      });
      setActive(0);

      // Pre-decode every deck image as the pin approaches, so the first shuffle never paints a blank frame.
      ScrollTrigger.create({
        trigger: pin,
        start: 'top bottom',
        once: true,
        onEnter: () => deck.querySelectorAll('img').forEach((img) => { img.decode().catch(() => {}); }),
      });
    }, pin);

    const offTilt = attachTilt(stage, deck, 5);
    return () => {
      offTilt();
      ctx.revert();
      stRef.current = null;
      tlRef.current = null;
      ScrollTrigger.refresh();
    };
  }, []);

  const jump = (i: number) => {
    const st = stRef.current, tl = tlRef.current;
    if (!st || !tl) return;
    const top = st.start + ((i + HOLD / 2) / tl.duration()) * (st.end - st.start);
    window.scrollTo({ top, behavior: 'smooth' });
  };

  return (
    <div className="sc-pin" ref={pinRef}>
      <div className="sc-pin__inner">
        <div className="sc-copy">
          <div className="sc-rail" ref={railRef} role="list" aria-label="Feature chapters">
            {CHAPTERS.map((c, i) => (
              <button type="button" className="sc-rail__btn" key={c.rail} onClick={() => jump(i)} role="listitem">
                <span className="sc-rail__n">{pad2(i)}</span>
                <span className="sc-rail__l">{c.rail}</span>
              </button>
            ))}
          </div>
          <div className="sc-chapters">
            {CHAPTERS.map((c, i) => (
              <article className="sc-chapter" key={c.title} aria-hidden={i === 0 ? undefined : true}>
                <p className="sc-chapter__n mono">{pad2(i)} / {pad2(N - 1)}</p>
                <h3 className="sc-chapter__t">{c.title}</h3>
                <p className="sc-chapter__p">{c.body}</p>
                <ul className="sc-tags">
                  {c.tags.map((t) => <li className="sc-tag" key={t}>{t}</li>)}
                </ul>
              </article>
            ))}
          </div>
        </div>

        <div className="sc-stage" ref={stageRef}>
          <div className="sc-deck" ref={deckRef}>
            {CHAPTERS.map((c, i) => (
              <figure className="sc-card" key={c.card + i}>
                <Img s={shots[c.card]} eager={i === 0} />
              </figure>
            ))}
            {CHAPTERS.map((c, i) => (
              <figure className={`sc-detail sc-detail--${i}`} key={c.detail + i}>
                <Img s={shots[c.detail]} eager={i === 0} />
                <figcaption className="sc-cap">{c.cap}</figcaption>
              </figure>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

/* ── Static chapters (mobile / reduced motion) ───────────────── */
function StaticList() {
  const root = useReveal<HTMLOListElement>(0.08);
  return (
    <ol className="sc-list" ref={root}>
      {CHAPTERS.map((c, i) => (
        <li className="sc-item" key={c.title}>
          <div className="sc-item__media reveal">
            <figure className="sc-item__card"><Img s={shots[c.card]} /></figure>
            <figure className="sc-item__detail"><Img s={shots[c.detail]} /></figure>
          </div>
          <div className="sc-item__copy reveal" data-delay="1">
            <p className="sc-chapter__n mono">{pad2(i)} / {pad2(N - 1)}</p>
            <h3 className="sc-chapter__t">{c.title}</h3>
            <p className="sc-chapter__p">{c.body}</p>
            <ul className="sc-tags">
              {c.tags.map((t) => <li className="sc-tag" key={t}>{t}</li>)}
            </ul>
          </div>
        </li>
      ))}
    </ol>
  );
}

/* ── Free-scrolling detail strip with per-item parallax ──────── */
function Strip() {
  const root = useReveal<HTMLDivElement>(0.05);
  useEffect(() => {
    const el = root.current;
    if (!el || reducedMotion()) return;
    const mobile = window.matchMedia('(max-width: 720px)').matches;
    const ctx = gsap.context(() => {
      el.querySelectorAll<HTMLElement>('.sc-strip__item').forEach((item) => {
        const speed = Number(item.dataset.speed || 1);
        const travel = (speed - 1) * (mobile ? 60 : 160);
        gsap.fromTo(item, { y: -travel }, {
          y: travel,
          ease: 'none',
          scrollTrigger: { trigger: el, start: 'top bottom', end: 'bottom top', scrub: 0.6 },
        });
      });
    }, el);
    return () => ctx.revert();
  }, [root]);

  return (
    <div className="sc-strip" ref={root}>
      {STRIP.map((s) => (
        <figure className="sc-strip__item reveal" data-speed={s.speed} key={s.key}>
          <div className="sc-strip__frame"><Img s={shots[s.key]} /></div>
          <figcaption className="sc-cap">{s.cap}</figcaption>
        </figure>
      ))}
    </div>
  );
}

export default function Showcase() {
  const head = useReveal<HTMLElement>(0.15);
  const isStatic = useStatic();
  return (
    <section id="features" className="section sc" aria-labelledby="features-title">
      <header className="section__inner sc-head" ref={head}>
        <p className="eyebrow reveal">[ 02 — Features ]</p>
        <h2 id="features-title" className="display sc-title reveal" data-delay="1">
          Every control.<br />Every effect.<br />All from the Mac.
        </h2>
        <p className="body sc-lede reveal" data-delay="2">
          Seven views in one window, and a menu-bar extra for the rest of the day. None of it needs a Bridge.
        </p>
      </header>

      {isStatic ? <div className="section__inner"><StaticList /></div> : <Scrolly />}

      <div className="section__inner">
        <Strip />
      </div>
    </section>
  );
}
