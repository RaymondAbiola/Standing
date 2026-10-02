"use client";

import {formatAmount} from "@/lib/format";
import {useChainStats} from "@/lib/publicReads";
import {Chip} from "./ui";

/// Live protocol state, read without a wallet.
///
/// A visitor who does not connect would otherwise see only claims. This is the
/// evidence: real charges, real reversals, real money sitting in escrow right
/// now, on both deployments. Both chains are shown rather than one, because the
/// Robinhood Chain deployment existing is itself part of the point.
export function LiveStats() {
  const {data, isLoading, isError, error} = useChainStats();

  return (
    <section className="shell py-10">
      <div className="mb-5 flex flex-wrap items-baseline justify-between gap-3">
        <p className="eyebrow">Live on chain</p>
        <p className="text-[13px]" style={{color: "var(--muted)"}}>
          Read directly from both deployments, no wallet needed
        </p>
      </div>

      {isError ? (
        <div className="panel px-5 py-6 text-[15px]" style={{color: "var(--color-warn)"}}>
          Could not reach the chains.
          <span className="num ml-2 text-[12px]" style={{color: "var(--muted)"}}>
            {error instanceof Error ? error.message.split("\n")[0] : ""}
          </span>
        </div>
      ) : isLoading && !data ? (
        <div className="grid gap-5 sm:grid-cols-2">
          {[0, 1].map((i) => (
            <CardSkeleton key={i} />
          ))}
        </div>
      ) : (
        <div className="grid gap-5 sm:grid-cols-2">
          {(data ?? []).map((c, i) => (
            <div
              key={c.chainId}
              className="panel rise px-6 py-5"
              style={{"--d": `${i * 110}ms`} as React.CSSProperties}
            >
              <div className="flex flex-wrap items-center justify-between gap-2">
                <p className="text-[16px] font-semibold tracking-tight">{c.label}</p>
                <a
                  href={`${c.explorer}/address/${c.standing}`}
                  target="_blank"
                  rel="noreferrer"
                  className="num ulink text-[12px]"
                  style={{color: "var(--muted)"}}
                >
                  {c.standing.slice(0, 8)}&hellip;{c.standing.slice(-4)}
                </a>
              </div>

              <dl className="mt-5 grid grid-cols-2 gap-x-6 gap-y-4">
                <Figure label="Charges taken" value={c.charges} />
                <Figure label="In escrow now" value={formatAmount(c.inEscrow)} tone="hold" />
                <Figure label="Settled" value={`${c.settled} · ${formatAmount(c.settledValue)}`} tone="good" />
                <Figure
                  label="Reversed"
                  value={`${c.reversed} · ${formatAmount(c.reversedValue)}`}
                  tone={c.reversed > 0 ? "warn" : "plain"}
                />
              </dl>

              {c.held > 0 ? (
                <p className="mt-5 flex items-center gap-2.5">
                  {/* the one live thing on the page, so it gets the only heartbeat */}
                  <span
                    className="halo inline-block h-2 w-2 shrink-0 rounded-full"
                    style={{background: "var(--color-hold)"}}
                    aria-hidden="true"
                  />
                  <Chip tone="hold">
                    {c.held} {c.held === 1 ? "charge" : "charges"} waiting on a payer right now
                  </Chip>
                </p>
              ) : null}
            </div>
          ))}
        </div>
      )}
    </section>
  );
}

/// Shaped like the card it replaces, so the layout does not jump when the reads
/// land. A spinner would say "something is happening"; this says what is coming.
function CardSkeleton() {
  return (
    <div className="panel px-6 py-5">
      <div className="flex items-center justify-between gap-2">
        <div className="skeleton h-5 w-40" />
        <div className="skeleton h-4 w-28" />
      </div>
      <div className="mt-5 grid grid-cols-2 gap-x-6 gap-y-4">
        {[0, 1, 2, 3].map((i) => (
          <div key={i}>
            <div className="skeleton h-3 w-24" />
            <div className="skeleton mt-2 h-6 w-20" />
          </div>
        ))}
      </div>
    </div>
  );
}

function Figure({
  label,
  value,
  tone = "plain",
}: {
  label: string;
  value: React.ReactNode;
  tone?: "plain" | "good" | "warn" | "hold";
}) {
  const color =
    tone === "good"
      ? "var(--color-mint)"
      : tone === "warn"
        ? "var(--color-warn)"
        : tone === "hold"
          ? "var(--color-hold)"
          : "var(--ink)";

  return (
    <div>
      <dt className="eyebrow">{label}</dt>
      <dd className="num mt-1.5 text-[21px] font-medium" style={{color}}>
        {value}
      </dd>
    </div>
  );
}
