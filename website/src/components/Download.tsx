import { useState } from 'react';
import { useReveal } from '../hooks/useReveal';
import { useLatestRelease, formatBytes, REPO_URL } from '../hooks/useLatestRelease';
import './download.css';

const XATTR = 'xattr -dr com.apple.quarantine /Applications/OpenHue.app';
const BUILD = './make-app.sh && open build/OpenHue.app';
const REQUIREMENTS = ['macOS 14+', 'Apple silicon · Intel', 'Hue Bluetooth bulbs · no Bridge'];

function CodeBlock({ code, label }: { code: string; label: string }) {
  const [copied, setCopied] = useState(false);
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1600);
    } catch {
      /* clipboard unavailable — the text is still selectable */
    }
  };
  return (
    <div className="dl-code">
      <code className="dl-code__text">{code}</code>
      <button type="button" className="dl-code__copy" onClick={copy} aria-label={`Copy ${label}`} aria-live="polite">
        {copied ? 'Copied' : 'Copy'}
      </button>
    </div>
  );
}

export default function Download() {
  const root = useReveal<HTMLElement>();
  const rel = useLatestRelease();
  const size = formatBytes(rel.dmgBytes);

  return (
    <section id="download" className="section dl" ref={root}>
      <div className="section__inner">
        <div className="dl__hero">
          {/* Faint Hue-warm light behind the statement */}
          <div className="glow dl__glow" aria-hidden="true" />

          <p className="eyebrow reveal">[ 06 — Download ]</p>
          <div className="dl__icon-wrap reveal" data-delay="1">
            <img className="dl__icon" src="/icon.png" width="512" height="512" alt="OpenHue app icon — a white bulb with a Hue-coloured halo" loading="lazy" decoding="async" />
          </div>
          <h2 className="display dl__display reveal" data-delay="2">
            Free, open source,<br />and {size || 'yours'}.
          </h2>
          <div className="dl__readout reveal" role="status" data-delay="3">
            <span className="sr-only">Latest release: </span>
            OpenHue.dmg · v{rel.version}{size ? ` · ${size}` : ''} · macOS 14 or later
          </div>
          <div className="dl__actions reveal" data-delay="4">
            <a className="btn btn--solid" href={rel.dmgUrl} download>Download .dmg</a>
            <a className="btn btn--ghost" href={rel.zipUrl} download>Download .zip</a>
            <a className="btn btn--outline" href={REPO_URL} target="_blank" rel="noopener">View on GitHub</a>
          </div>
          <ul className="dl-tags reveal" data-delay="4" aria-label="Requirements">
            {REQUIREMENTS.map((t) => <li key={t}>{t}</li>)}
            <li className="dl-tags__link"><a href={rel.releaseUrl} target="_blank" rel="noopener">Release notes ↗</a></li>
          </ul>
        </div>

        <div className="dl__grid">
          <div className="dl-card reveal">
            <p className="dl-card__k">Gatekeeper</p>
            <p className="dl-card__line">Development-signed, not notarized — <b>right-click → Open</b> once, or:</p>
            <CodeBlock code={XATTR} label="the quarantine command" />
          </div>
          <div className="dl-card reveal" data-delay="1">
            <p className="dl-card__k">Build from source</p>
            <p className="dl-card__line">Xcode 26 · macOS 14+ · launch the .app, never <code>swift run</code>:</p>
            <CodeBlock code={BUILD} label="the build command" />
          </div>
        </div>
      </div>
    </section>
  );
}
