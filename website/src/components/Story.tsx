import { useEffect, useRef } from 'react';
import { gsap, ScrollTrigger, reducedMotion } from '../lib/gsap';
import { useReveal } from '../hooks/useReveal';
import { shots } from '../shots';
import { Frame, LiveCt, LiveDial, LiveText, LiveToggle, MENU, WIN, attachTilt, countdown, mmss, rightOn } from './live';
import './story.css';

const FACTS = [
  { k: 'BLE GATT · FE0F', v: 'The bulb’s own protocol, spoken from CoreBluetooth.' },
  { k: 'Schedules on the bulb', v: 'Fire on its clock — Mac asleep, phone away.' },
  { k: 'Swift 6 · macOS 14+', v: '4 MB. Open source. 102 tests.' },
] as const;

const menuCountdown = (t: number) => mmss(countdown(t).rem);

export default function Story() {
  const root = useReveal<HTMLElement>(0.1);
  const sceneRef = useRef<HTMLDivElement>(null);
  const stackRef = useRef<HTMLDivElement>(null);
  const tiltRef = useRef<HTMLDivElement>(null);
  const ctRef = useRef<HTMLDivElement>(null);
  const winRef = useRef<HTMLDivElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const dialRef = useRef<HTMLDivElement>(null);

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

    const offTilt = mobile ? () => {} : attachTilt(scene, tilt, 7);
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
            The Hue app.<br />On your Mac.
          </h2>
          <p className="story-line reveal" data-delay="2">
            Same bulbs, same scenes and effects — local, Bridge-free, open source.
          </p>
        </header>

        <div className="story-scene reveal" data-delay="2" ref={sceneRef} role="group" aria-label="OpenHue windows floating in perspective, with a live timer">
          <div className="glow story-glow" aria-hidden="true" />
          <div className="story-stack" ref={stackRef}>
            <div className="story-tilt" ref={tiltRef}>
              <div className="story-layer story-layer--ct" ref={ctRef}>
                <Frame s={shots.ctCard}><LiveCt s={shots.ctCard} /></Frame>
              </div>
              <div className="story-layer story-layer--win" ref={winRef}>
                <Frame s={shots.allLightsWhite} eager>
                  <LiveCt s={shots.allLightsWhite} header />
                  <LiveToggle s={shots.allLightsWhite} r={WIN.rowToggles[0]} on={rightOn} />
                </Frame>
              </div>
              <div className="story-layer story-layer--menu" ref={menuRef}>
                <Frame s={shots.menubar}>
                  <LiveText s={shots.menubar} r={MENU.timerText} bg="#0f0f0f" color="#9f9f9f" size={22} align="right" text={menuCountdown} />
                  <LiveToggle s={shots.menubar} r={MENU.toggles[1]} on={rightOn} />
                </Frame>
              </div>
              <div className="story-layer story-layer--dial" ref={dialRef}>
                <Frame s={shots.dial}><LiveDial s={shots.dial} /></Frame>
              </div>
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
