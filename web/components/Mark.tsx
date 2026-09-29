/// The brand mark: two brackets holding a pill, the charge held in escrow
/// through its window.
export function Mark({size = 22}: {size?: number}) {
  return (
    <svg width={size} height={size} viewBox="0 0 64 64" fill="none" aria-hidden="true">
      <path
        d="M24 10 H12 V54 H24"
        stroke="currentColor"
        strokeWidth="6"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <path
        d="M40 10 H52 V54 H40"
        stroke="currentColor"
        strokeWidth="6"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <rect x="28" y="16" width="8" height="32" rx="4" fill="var(--color-mint)" />
    </svg>
  );
}
