/// The locked-box diagram, drawn rather than described.
///
/// Four paragraphs of prose explain this in about a minute. The picture does it
/// in a few seconds, and it is the one idea a visitor has to leave with: the
/// money stops somewhere in between, and the payer can still pull it back while
/// it sits there.
///
/// The dashes travel because the static version read as an architecture
/// diagram. Motion along the paths is what says the money is moving, and the
/// one box with a pulsing edge is the one place it stops.
///
/// Inline SVG so it inherits the theme and reads in both light and dark.
export function MechanismDiagram() {
  return (
    <figure className="panel overflow-hidden px-4 py-6 sm:px-8 sm:py-10">
      <svg
        viewBox="0 0 760 236"
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
          <rect x="8" y="58" width="132" height="52" rx="11" fill="var(--raised)" stroke="var(--line)" />
          <text x="74" y="90" textAnchor="middle" fontSize="17" fill="var(--ink)" fontWeight="500">
            Payer
          </text>
        </g>

        {/* payer to escrow: the money on its way in */}
        <line x1="146" y1="84" x2="268" y2="84" stroke="var(--line)" strokeWidth="2" />
        <line
          x1="146"
          y1="84"
          x2="268"
          y2="84"
          stroke="var(--muted)"
          strokeWidth="2"
          markerEnd="url(#arrow)"
          className="flow"
        />
        <text x="207" y="72" textAnchor="middle" fontSize="13" fill="var(--muted)">
          charge
        </text>

        {/* escrow, the part that matters */}
        <g>
          <rect
            x="276"
            y="40"
            width="208"
            height="88"
            rx="13"
            fill="var(--card)"
            stroke="var(--color-mint)"
            strokeWidth="1.5"
          />
          {/* the pulsing edge: this is the box that holds things up */}
          <rect
            x="276"
            y="40"
            width="208"
            height="88"
            rx="13"
            fill="none"
            stroke="var(--color-mint)"
            className="edge"
          />
          <text x="380" y="72" textAnchor="middle" fontSize="17" fill="var(--ink)" fontWeight="600">
            Escrow
          </text>
          <text x="380" y="95" textAnchor="middle" fontSize="13" fill="var(--color-mint)">
            held until the window closes
          </text>
          <text x="380" y="116" textAnchor="middle" fontSize="12" fill="var(--muted)">
            the merchant has not been paid yet
          </text>
        </g>

        {/* escrow to merchant */}
        <line x1="492" y1="84" x2="614" y2="84" stroke="var(--line)" strokeWidth="2" />
        <line
          x1="492"
          y1="84"
          x2="614"
          y2="84"
          stroke="var(--muted)"
          strokeWidth="2"
          markerEnd="url(#arrow)"
          className="flow"
          style={{animationDelay: "550ms"}}
        />
        <text x="553" y="72" textAnchor="middle" fontSize="13" fill="var(--muted)">
          settle
        </text>

        {/* merchant */}
        <g>
          <rect x="620" y="58" width="132" height="52" rx="11" fill="var(--raised)" stroke="var(--line)" />
          <text x="686" y="90" textAnchor="middle" fontSize="17" fill="var(--ink)" fontWeight="500">
            Merchant
          </text>
        </g>

        {/* the reversal path, back to the payer */}
        <path
          d="M340 132 L340 180 L74 180 L74 118"
          fill="none"
          stroke="var(--color-mint)"
          strokeWidth="2"
          markerEnd="url(#arrowMint)"
          className="flow"
        />
        <text x="214" y="200" textAnchor="middle" fontSize="13" fill="var(--color-mint)">
          reverse, while the window is open
        </text>

        {/* what gates the reversal */}
        <text x="380" y="228" textAnchor="middle" fontSize="12" fill="var(--muted)">
          the right to reverse is earned: three clean settlements, capped at a third of what you have paid
        </text>
      </svg>
    </figure>
  );
}
