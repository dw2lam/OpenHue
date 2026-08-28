import { useState } from 'react';
import { useReveal } from '../hooks/useReveal';
import { useLatestRelease, formatBytes, REPO_URL } from '../hooks/useLatestRelease';
import './download.css';

const XATTR = 'xattr -dr com.apple.quarantine /Applications/OpenHue.app';
const BUILD = './make-app.sh && open build/OpenHue.app';

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
          <p className="eyebrow reveal">[ 05 — Download ]</p>
          <h2 className="display dl__display reveal" data-delay="1">
            Free, open source,<br />and {size || 'yours'}.
          </h2>
          <div className="dl__readout reveal" role="status" data-delay="2">
            <span className="sr-only">Latest release: </span>
            OpenHue.dmg · v{rel.version}{size ? ` · ${size}` : ''} · macOS 14 or later
          </div>
          <div className="dl__actions reveal" data-delay="3">
            <a className="btn btn--solid" href={rel.dmgUrl} download>Download .dmg</a>
            <a className="btn btn--ghost" href={rel.zipUrl} download>Download .zip</a>
            <a className="btn btn--outline" href={REPO_URL} target="_blank" rel="noopener">View on GitHub</a>
          </div>
          <p className="dl__hint reveal" data-delay="4">
            Unzip or open the disk image and drag <strong>OpenHue.app</strong> to <strong>/Applications</strong>.{' '}
            <a href={rel.releaseUrl} target="_blank" rel="noopener">Release notes</a>
          </p>
        </div>

        <div className="dl__grid">
          <div className="dl-card reveal">
            <p className="dl-card__k">Requirements</p>
            <ul className="dl-list">
              <li><span>macOS 14 Sonoma or later</span><em>Apple silicon or Intel</em></li>
              <li><span>A Mac with Bluetooth LE</span><em>Every Mac since 2012</em></li>
              <li><span>Philips Hue bulbs with Bluetooth</span><em>Not joined to a Hue Bridge</em></li>
            </ul>
            <p className="dl-card__note">
              No Bridge, no account, no cloud. Everything lives in <code>~/Library/Application Support/OpenHue/</code> as
              plain JSON; the Bluetooth bonds live in macOS.
            </p>
          </div>

          <div className="dl-card reveal" data-delay="1">
            <p className="dl-card__k">First launch · Gatekeeper</p>
            <p className="dl-card__text">
              The build is signed with an Apple <em>Development</em> certificate, not a notarized Developer ID, so
              Gatekeeper refuses it once. Either <strong>right-click → Open → Open</strong>, or clear the quarantine flag:
            </p>
            <CodeBlock code={XATTR} label="the quarantine command" />
            <p className="dl-card__note">Then click Allow when macOS asks for Bluetooth, and add your first light.</p>
          </div>

          <div className="dl-card reveal" data-delay="2">
            <p className="dl-card__k">Build from source</p>
            <p className="dl-card__text">
              Xcode 26 and macOS 14 or later. The script builds a release <strong>OpenHue.app</strong> and signs it with
              your Apple Development identity if one is present.
            </p>
            <CodeBlock code={BUILD} label="the build command" />
            <p className="dl-card__note">
              Never <code>swift run</code>: the Bluetooth permission is attributed to the process that owns the prompt —
              Terminal, not the app — and the bare binary has no Info.plist, so CoreBluetooth reports <em>unauthorized</em>.
              Always launch the .app that make-app.sh produces.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}
