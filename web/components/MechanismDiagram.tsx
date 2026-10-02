/// The locked-box diagram, drawn rather than described.
///
/// Four paragraphs of prose explain this in about a minute. The picture does it
/// in a few seconds, and it is the one idea a visitor has to leave with: the
/// money stops somewhere in between, and the payer can still pull it back while
/// it sits there.
///
/// Inline SVG so it inherits the theme and reads in both light and dark.
export function MechanismDiagram() {
  return (
    <figure className="panel overflow-hidden px-4 py-6 sm:px-8 sm:py-8">
      <svg
        viewBox="0 0 760 230"
        className="h-auto w-full"
        role="img"
        aria-labelledby="mech-title mech-desc"
      >
        <title id="mech-title">How a charge settles</title>
        <desc id="mech-desc">
          A charge leaves the payer and stops in escrow behind an unlock time. While it waits, the payer
          can reverse it and the money returns. Once the window closes, anyone can settle it and the
          merchant is paid.
        </desc>

        <defs>
          <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto">
            <path d="M0 0 L10 5 L0 10 z" fill="var(--muted)" />
          </marker>
          <marker
            id="arrowMint"
            viewBox="0 0 10 10"
            refX="9"
            refY="5"
            markerWidth="6"
            markerHeight="6"
            orient="auto"
          >
            <path d="M0 0 L10 5 L0 10 z" fill="var(--color-mint)" />
          </marker>
        </defs>

        {/* payer */}
        <g>
          <rect x="8" y="58" width="132" height="50" rx="10" fill="var(--raised)" stroke="var(--line)" />
          <text x="74" y="88" textAnchor="middle" fontSize="15" fill="var(--ink)" fontWeight="500">
            Payer
          </text>
        </g>

        {/* payer to escrow */}
        <line x1="146" y1="83" x2="268" y2="83" stroke="var(--muted)" strokeWidth="1.5" markerEnd="url(#arrow)" />
        <text x="207" y="72" textAnchor="middle" fontSize="12" fill="var(--muted)">
          charge
        </text>

        {/* escrow, the part that matters */}
        <g>
          <rect
            x="276"
            y="42"
            width="208"
            height="82"
            rx="12"
            fill="var(--card)"
            stroke="var(--color-mint)"
            strokeWidth="1.5"
          />
          <text x="380" y="72" textAnchor="middle" fontSize="15" fill="var(--ink)" fontWeight="600">
            Escrow
          </text>
          <text x="380" y="94" textAnchor="middle" fontSize="12" fill="var(--color-mint)">
            held until the window closes
          </text>
          <text x="380" y="112" textAnchor="middle" fontSize="11" fill="var(--muted)">
            the merchant has not been paid yet
          </text>
        </g>

        {/* escrow to merchant */}
        <line x1="492" y1="83" x2="614" y2="83" stroke="var(--muted)" strokeWidth="1.5" markerEnd="url(#arrow)" />
        <text x="553" y="72" textAnchor="middle" fontSize="12" fill="var(--muted)">
          settle
        </text>

        {/* merchant */}
        <g>
          <rect x="620" y="58" width="132" height="50" rx="10" fill="var(--raised)" stroke="var(--line)" />
          <text x="686" y="88" textAnchor="middle" fontSize="15" fill="var(--ink)" fontWeight="500">
            Merchant
          </text>
        </g>

        {/* the reversal path, back to the payer */}
        <path
          d="M340 128 L340 176 L74 176 L74 116"
          fill="none"
          stroke="var(--color-mint)"
          strokeWidth="1.5"
          strokeDasharray="5 4"
          markerEnd="url(#arrowMint)"
        />
        <text x="214" y="196" textAnchor="middle" fontSize="12" fill="var(--color-mint)">
          reverse, while the window is open
        </text>

        {/* what gates the reversal */}
        <text x="380" y="222" textAnchor="middle" fontSize="11" fill="var(--muted)">
          the right to reverse is earned: three clean settlements, capped at a third of what you have paid
        </text>
      </svg>
    </figure>
  );
}
