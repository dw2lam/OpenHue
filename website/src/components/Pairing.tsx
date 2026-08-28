import type { ReactNode } from 'react';
import { useReveal } from '../hooks/useReveal';
import './pairing.css';

/* Three clicks on first launch — title + one mono line each, no prose. */
const STEPS: { title: string; line: ReactNode }[] = [
  { title: 'Allow Bluetooth', line: <>“OpenHue would like to use Bluetooth” <i>→</i> <b>Allow</b></> },
  { title: 'Add Light', line: <>Power on <i>·</i> within 2 m <i>→</i> <b>Add</b></> },
  { title: 'Connection Request', line: <>macOS dialog <i>→</i> <b>Connect</b> <i>·</i> bonded from now on</> },
];

const LIMITS = ['BLE range · a room or two', 'One device per bulb', 'Bulb schedules re-arm daily', 'Bridge-joined = no Bluetooth'];

const CHARS: { name: string; id: string; fmt: ReactNode; rw: string }[] = [
  { name: 'Capabilities', id: '0001', fmt: <>15 bytes; TLV carrying the bulb's mireds range</>, rw: 'R' },
  { name: 'Power', id: '0002', fmt: <>1 byte, <code>00</code> / <code>01</code>. Reading it is what triggers the pairing dialog</>, rw: 'R · W · N' },
  { name: 'Brightness', id: '0003', fmt: <>1 byte, <code>1…254</code> — never write <code>0</code></>, rw: 'R · W · N' },
  { name: 'Colour temperature', id: '0004', fmt: <><code>uint16</code> LE mireds <code>153…500</code> (454 on some models); reads <code>FFFF</code> while in xy mode</>, rw: 'R · W · N' },
  { name: 'Colour xy', id: '0005', fmt: <>2 × <code>uint16</code> LE = <code>round(x·65535)</code>, <code>round(y·65535)</code>; reads <code>FFFFFFFF</code> while in CT mode</>, rw: 'R · W · N' },
  { name: 'Alert', id: '0006', fmt: <><code>00</code> none · <code>01</code> flash once · <code>02</code> flash repeatedly</>, rw: 'W' },
  { name: 'Combined state', id: '0007', fmt: <>TLV <code>[tag][len][value]…</code> — <code>01</code> on · <code>02</code> brightness · <code>03</code> mireds · <code>04</code> xy · <code>06</code> effect · <code>08</code> effect speed. The one read that returns the whole state</>, rw: 'R · W · N' },
  { name: 'Power-on default', id: '1005', fmt: <>Same TLV as <code>0007</code>, followed by <code>FF FF FF FF</code></>, rw: 'R · W' },
];

const EFFECT_TAGS: [string, string][] = [
  ['01', 'Candle'], ['02', 'Fireplace'], ['03', 'Prism'], ['0A', 'Sparkle'], ['0B', 'Opal'],
  ['0C', 'Glisten'], ['0E', 'Underwater'], ['0F', 'Cosmos'], ['10', 'Sunbeam'], ['11', 'Enchant'],
];

const ext = { target: '_blank', rel: 'noopener' } as const;

export default function Pairing() {
  const root = useReveal<HTMLElement>();
  return (
    <section id="pairing" className="section pair" ref={root}>
      <div className="section__inner">
        <header className="pair__head">
          <div>
            <p className="eyebrow reveal">[ 05 — Pairing ]</p>
            <h2 className="h2 pair__title reveal" data-delay="1">Pair once.<br />The Mac keeps the bond.</h2>
          </div>
          <ul className="pair-tags reveal" data-delay="2" aria-label="Pairing in short">
            <li>3 clicks</li><li>One macOS dialog</li><li>The Alexa trick · no reset</li>
          </ul>
        </header>

        {/* ── First launch: a tight 3-step strip ─────────────────── */}
        <ol className="pair-strip">
          {STEPS.map((s, i) => (
            <li key={s.title} className="pair-step reveal" data-delay={String(i + 1)}>
              <span className="pair-step__n">{String(i + 1).padStart(2, '0')}</span>
              <h3 className="h3 pair-step__title">{s.title}</h3>
              <p className="pair-step__line">{s.line}</p>
            </li>
          ))}
        </ol>

        {/* ── The trick ──────────────────────────────────────────── */}
        <div className="pair-gotcha glass reveal">
          <div className="pair-gotcha__head">
            <p className="pair-gotcha__k">The trick</p>
            <h3 className="h3 pair-gotcha__title">
              Tell the Hue app you're adding Alexa. That flips the bulb into Bluetooth discovery — so it can
              pair with your Mac too, and the phone app keeps working.
            </h3>
          </div>
          <div className="pair-path" aria-label="Hue app path">
            <span>HUE APP</span><i>→</i><span>SETTINGS</span><i>→</i><span>VOICE ASSISTANTS</span><i>→</i>
            <span>AMAZON ALEXA or GOOGLE HOME</span><i>→</i><b>MAKE DISCOVERABLE</b>
          </div>
          <p className="pair-gotcha__line">
            It's the same window Echo and Nest speakers use to pair over Bluetooth <i>·</i> <b>Retry</b> in OpenHue within 2 min
            <i>·</i> now phone <b>and</b> Mac hold a bond and reconnect on their own — that's what makes it stick
          </p>
          <p className="pair-gotcha__line pair-gotcha__line--reset">
            <em>Last resort</em> off/on ×5, end on <i>→</i> <b>Add Light</b> <i>→</i> <b>Add as replacement for…</b>
            <i>·</i> stale bond? forget “Hue Lamp” in System Settings <i>→</i> Bluetooth
          </p>
        </div>

        {/* ── Limits: four mono tags ─────────────────────────────── */}
        <ul className="pair-limits reveal" aria-label="Limits">
          {LIMITS.map((l) => <li key={l}>{l}</li>)}
        </ul>

        {/* ── Nerd content, off the main read ───────────────────── */}
        <details className="pair-notes">
          <summary className="pair-notes__sum">
            <span className="pair-notes__k">Protocol notes</span>
            <span className="pair-notes__meta">GATT · FE0F · 932c32bd-XXXX · effects · credits</span>
            <span className="pair-notes__caret" aria-hidden="true">+</span>
          </summary>
          <div className="pair-notes__body">
            <p className="pair-uuid">
              <span>Light service</span>
              <code>932c32bd-<b>XXXX</b>-47a2-835a-a8d455b859dd</code>
              <em>Bulbs advertise Signify's 16-bit service <code>FE0F</code>; every characteristic below shares this base.</em>
            </p>

            <div className="pair-table-wrap">
              <table className="pair-table">
                <thead>
                  <tr><th scope="col">Characteristic</th><th scope="col">XXXX</th><th scope="col">Format</th><th scope="col">Access</th></tr>
                </thead>
                <tbody>
                  {CHARS.map((c) => (
                    <tr key={c.id}>
                      <td className="pair-td--name">{c.name}</td>
                      <td className="pair-td--id">{c.id}</td>
                      <td className="pair-td--fmt">{c.fmt}</td>
                      <td className="pair-td--rw">{c.rw}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <div className="pair-sub">
              <p className="pair-sub__k">Effects · tag <code>06</code></p>
              <div className="pair-fx">
                {EFFECT_TAGS.map(([tag, name]) => <span key={tag}><b>{tag}</b>{name}</span>)}
              </div>
            </div>

            <div className="pair-sub">
              <p className="pair-sub__k">Also on the bulb</p>
              <p className="pair-sub__text">
                <code>FE0F</code> device configuration (name, Zigbee address, pairing control) · <code>180A</code> device
                information · <code>97fe6561-1001</code> bulb clock, <code>uint32</code> LE Unix seconds · <code>9da2ddf1-0001</code> on-bulb
                alarms — the “MAC-protected” create packet carries a plain UUID v4, which is how OpenHue stores schedules in the bulb.
              </p>
            </div>

            <p className="pair-credit">
              Reverse-engineered by the community — chiefly{' '}
              <a href="https://github.com/flip-dots/HueBLE" {...ext}>flip-dots/HueBLE</a> and{' '}
              <a href="https://github.com/glyphack/huec" {...ext}>glyphack/huec</a>, with macOS pairing notes from{' '}
              <a href="https://github.com/ai212983/blemacd" {...ext}>ai212983/blemacd</a>. Not affiliated with Signify or Philips Hue.
            </p>
          </div>
        </details>
      </div>
    </section>
  );
}
