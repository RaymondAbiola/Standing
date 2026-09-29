"use client";

/// Shared primitives, kept small on purpose: an eyebrow-labelled section, a
/// stat, a chip, a panel row. The reference design leans on exactly these four
/// shapes, so most screens are assembled rather than styled.

export function Section({
  eyebrow,
  title,
  children,
  right,
}: {
  eyebrow: string;
  title?: string;
  children: React.ReactNode;
  right?: React.ReactNode;
}) {
  return (
    <section className="mx-auto max-w-[1000px] px-4 py-8">
      <div className="mb-4 flex flex-wrap items-baseline justify-between gap-3">
        <div>
          <p className="eyebrow">{eyebrow}</p>
          {title ? <h2 className="mt-2 text-[22px] font-semibold tracking-tight">{title}</h2> : null}
        </div>
        {right}
      </div>
      {children}
    </section>
  );
}

export function Stat({
  label,
  value,
  hint,
  tone = "plain",
}: {
  label: string;
  value: React.ReactNode;
  hint?: string;
  tone?: "plain" | "good" | "warn";
}) {
  const color = tone === "good" ? "var(--color-mint)" : tone === "warn" ? "var(--color-warn)" : "var(--ink)";
  return (
    <div className="panel px-4 py-3">
      <p className="eyebrow">{label}</p>
      <p className="num mt-2 text-[20px] font-medium" style={{color}}>
        {value}
      </p>
      {hint ? (
        <p className="mt-1 text-[12px]" style={{color: "var(--muted)"}}>
          {hint}
        </p>
      ) : null}
    </div>
  );
}

export function Chip({
  children,
  tone = "plain",
}: {
  children: React.ReactNode;
  tone?: "plain" | "good" | "warn" | "hold";
}) {
  const map = {
    plain: {bg: "var(--raised)", fg: "var(--muted)", dot: "var(--faint)"},
    good: {bg: "var(--color-mint-soft)", fg: "var(--color-mint)", dot: "var(--color-mint)"},
    warn: {bg: "var(--color-warn-soft)", fg: "var(--color-warn)", dot: "var(--color-warn)"},
    hold: {bg: "var(--raised)", fg: "var(--color-hold)", dot: "var(--color-hold)"},
  }[tone];

  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[11px] font-medium"
      style={{background: map.bg, color: map.fg}}
    >
      <span className="h-1.5 w-1.5 rounded-full" style={{background: map.dot}} />
      {children}
    </span>
  );
}

export function Button({
  children,
  onClick,
  disabled,
  variant = "quiet",
  type = "button",
}: {
  children: React.ReactNode;
  onClick?: () => void;
  disabled?: boolean;
  variant?: "primary" | "quiet" | "danger";
  type?: "button" | "submit";
}) {
  const style =
    variant === "primary"
      ? {background: "var(--ink)", color: "var(--ground)", borderColor: "var(--ink)"}
      : variant === "danger"
        ? {background: "transparent", color: "var(--color-warn)", borderColor: "var(--color-warn)"}
        : {background: "transparent", color: "var(--ink)", borderColor: "var(--line)"};

  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled}
      className="inline-flex min-h-11 items-center justify-center gap-2 rounded-full border px-4 text-[13px] font-medium transition-opacity disabled:cursor-not-allowed disabled:opacity-40"
      style={style}
    >
      {children}
    </button>
  );
}

export function Field({
  label,
  children,
  hint,
}: {
  label: string;
  children: React.ReactNode;
  hint?: string;
}) {
  return (
    <label className="block">
      <span className="eyebrow">{label}</span>
      <div className="mt-2">{children}</div>
      {hint ? (
        <span className="mt-1 block text-[12px]" style={{color: "var(--muted)"}}>
          {hint}
        </span>
      ) : null}
    </label>
  );
}

export function Input(props: React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      {...props}
      className="num min-h-11 w-full rounded-lg border bg-transparent px-3 text-[14px] outline-none focus:border-[var(--color-mint)]"
      style={{borderColor: "var(--line)", color: "var(--ink)"}}
    />
  );
}

export function Empty({children}: {children: React.ReactNode}) {
  return (
    <div className="panel px-4 py-10 text-center text-[13px]" style={{color: "var(--muted)"}}>
      {children}
    </div>
  );
}
