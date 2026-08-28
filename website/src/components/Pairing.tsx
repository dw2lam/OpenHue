import type { ReactNode } from 'react';
import { useReveal } from '../hooks/useReveal';
import './pairing.css';

interface Step { title: string; body: ReactNode }

const K = ({ children }: { children: ReactNode }) => <kbd className="pair-key">{children}</kbd>;

const FIRST_LAUNCH: Step[] = [
  {
    title: 'Allow Bluetooth',
    body: (
      <>
        macOS asks <em>“OpenHue would like to use Bluetooth”</em> — click <K>Allow</K>. Denied it, or it never appeared?
        Enable the app under System Settings → Privacy &amp; Security → Bluetooth, then relaunch.
      </>
    ),
  },
  {
    title: 'Add Light',
    body: (
      <>
        Click <K>Add Light</K>. Power the bulb on and keep it within a couple of metres; it appears in the list with a
        signal indicator. Click <K>Add</K>.
      </>
    ),
  },
  {
    title: 'Connection Request',
    body: (
      <>
        Hue bulbs pair implicitly: the first encrypted read makes macOS show a <em>Connection Request</em> for the
        bulb. Click <K>Connect</K>. The Mac remembers the bond and reconnects silently from then on.
      </>
    ),
  },
];

const RECOVERY: Step[] = [
  {
    title: 'Make it discoverable — from the phone',
    body: (
      <>
        <div className="pair-path" aria-label="Hue app path">
          <span>Hue app</span><i>→</i><span>Settings</span><i>→</i><span>Voice Assistants</span><i>→</i>
          <span>Amazon Alexa <em>or</em> Google Home</span><i>→</i><b>Make Discoverable</b>
        </div>
        This is the same window Echo and Nest speakers use to pair with Bluetooth-only bulbs. No Bridge needed, and the
        phone app keeps working. Then, within a minute or two, click <K>Retry</K> in OpenHue (or add the light). If the
        phone app is still holding the connection, background it right after tapping Make Discoverable.
      </>
    ),
  },
  {
    title: 'Last resort — factory reset',
    body: (
      <>
        Switch the bulb off and on <strong>five times</strong>, about a second apart, ending <strong>on</strong>; it blinks
        on the last cycle. This unpairs the phone app too and gives the bulb a <strong>new Bluetooth address</strong>, so
        it shows up as a fresh “Hue Lamp”. Use <K>Add Light</K> → <K>Add as replacement for…</K> and pick the old entry —
        name, scenes and schedules carry over — then click <K>Connect</K> on the Connection Request.
      </>
    ),
  },
  {
    title: 'Stale bond',
    body: (
      <>
        If macOS still refuses, forget any old “Hue Lamp” in System Settings → Bluetooth (hover → ⓘ → Forget) and retry.
      </>
    ),
  },
  {
    title: 'Joined to a Hue Bridge?',
    body: (
      <>
        Once a bulb has joined a Bridge (Zigbee) its Bluetooth control is disabled entirely. Delete it from the Bridge
        first, or factory-reset it.
      </>
    ),
  },
];

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

const LIMITS: { k: string; body: string }[] = [
  { k: 'Bluetooth range', body: 'Bulbs must be within BLE range of the Mac — a room or two; walls hurt.' },
  { k: 'One device per bulb', body: 'While OpenHue is connected the Hue phone app can’t reach the bulb, and vice versa. Disconnect All hands it over.' },
  { k: 'Schedules', body: 'Schedules written to the bulb fire once and are disarmed; OpenHue re-arms them daily when connected. Weekly and fade schedules run on the Mac — awake, in range, app running.' },
  { k: 'Bridge-joined bulbs', body: 'Once a bulb joins a Hue Bridge its Bluetooth control is switched off. Unsupported until it is removed from the Bridge or reset.' },
];

function Steps({ steps, start }: { steps: Step[]; start: number }) {
  return (
    <ol className="pair-steps">
      {steps.map((s, i) => (
        <li key={s.title} className="pair-step reveal" data-delay={String(Math.min(4, i + 1))}>
          <span className="pair-step__n">{String(start + i).padStart(2, '0')}</span>
          <div className="pair-step__body">
            <h3 className="h3 pair-step__title">{s.title}</h3>
            <div className="body pair-step__text">{s.body}</div>
          </div>
        </li>
      ))}
    </ol>
  );
}

export default function Pairing() {
  const root = useReveal<HTMLElement>();
  return (
    <section id="pairing" className="section pair" ref={root}>
      <div className="section__inner">
        <header className="pair__head">
          <div>
            <p className="eyebrow reveal">[ 04 — Pairing &amp; protocol ]</p>
            <h2 className="h2 pair__title reveal" data-delay="1">Pair once.<br />The Mac keeps the bond.</h2>
          </div>
          <p className="body pair__lede reveal" data-delay="2">
            Three clicks on first launch. The only trick is a bulb that already belongs to your phone: it refuses a
            second bond until you make it discoverable — which the Hue app can do without a Bridge and without a reset.
          </p>
        </header>

        <div className="pair-group">
          <div className="pair-group__side">
            <p className="pair-group__k reveal">First launch</p>
            <p className="pair-group__note reveal" data-delay="1">Bluetooth permission, one bulb, one macOS dialog.</p>
          </div>
          <Steps steps={FIRST_LAUNCH} start={1} />
        </div>

        <div className="pair-group pair-group--gotcha">
          <div className="pair-group__side">
            <p className="pair-group__k reveal">If the Connection Request never appears</p>
            <p className="pair-group__note reveal" data-delay="1">
              The bulb is still bonded to your phone and is refusing new pairings. Bulbs only accept a new pairing while
              discoverable. The same steps are shown inside the app.
            </p>
          </div>
          <Steps steps={RECOVERY} start={4} />
        </div>

        <div className="pair-group pair-group--proto">
          <div className="pair-group__side">
            <p className="pair-group__k reveal">The protocol</p>
            <p className="pair-group__note reveal" data-delay="1">
              Bulbs advertise Signify's 16-bit service <code>FE0F</code>. Once connected, everything the app does goes
              through one light service; its characteristics share a base UUID and differ only in the second group.
            </p>
            <p className="pair-uuid reveal" data-delay="2">
              <span>Light service</span>
              <code>932c32bd-<b>XXXX</b>-47a2-835a-a8d455b859dd</code>
            </p>
          </div>

          <div className="pair-proto">
            <div className="pair-table-wrap reveal">
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

            <div className="pair-sub reveal" data-delay="1">
              <p className="pair-sub__k">Effects · tag <code>06</code></p>
              <div className="pair-fx">
                {EFFECT_TAGS.map(([tag, name]) => <span key={tag}><b>{tag}</b>{name}</span>)}
              </div>
            </div>

            <div className="pair-sub reveal" data-delay="2">
              <p className="pair-sub__k">Also on the bulb</p>
              <p className="pair-sub__text">
                <code>FE0F</code> device configuration (name, Zigbee address, pairing control) · <code>180A</code> device
                information · <code>97fe6561-1001</code> bulb clock, <code>uint32</code> LE Unix seconds · <code>9da2ddf1-0001</code> on-bulb
                alarms — the “MAC-protected” create packet turned out to carry a plain UUID v4, which is how OpenHue stores
                schedules in the bulb itself.
              </p>
            </div>
          </div>
        </div>

        <div className="pair-limits">
          {LIMITS.map((l, i) => (
            <div key={l.k} className="pair-limit reveal" data-delay={String(i + 1)}>
              <p className="pair-limit__k">{l.k}</p>
              <p className="pair-limit__body">{l.body}</p>
            </div>
          ))}
        </div>

        <p className="pair-credit reveal">
          The protocol was reverse-engineered by the community — chiefly{' '}
          <a href="https://github.com/flip-dots/HueBLE" target="_blank" rel="noopener">flip-dots/HueBLE</a> and{' '}
          <a href="https://github.com/glyphack/huec" target="_blank" rel="noopener">glyphack/huec</a>, whose packet captures
          made the alarm layout and the UUID finding possible, with macOS pairing notes from{' '}
          <a href="https://github.com/ai212983/blemacd" target="_blank" rel="noopener">ai212983/blemacd</a>. OpenHue is not
          affiliated with Signify or Philips Hue.
        </p>
      </div>
    </section>
  );
}
