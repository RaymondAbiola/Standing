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
    <section className="mx-auto max-w-[1000px] px-4 py-8">
      <div className="mb-4 flex flex-wrap items-baseline justify-between gap-3">
        <p className="eyebrow">Live on chain</p>
        <p className="text-[12px]" style={{color: "var(--muted)"}}>
          Read directly from both deployments, no wallet needed
        </p>
      </div>

      {isError ? (
        <div className="panel px-4 py-5 text-[13px]" style={{color: "var(--color-warn)"}}>
          Could not reach the chains.
          <span className="num ml-2 text-[11px]" style={{color: "var(--muted)"}}>
            {error instanceof Error ? error.message.split("\n")[0] : ""}
          </span>
        </div>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2">
          {(data ?? []).map((c) => (
            <div key={c.chainId} className="panel px-5 py-4">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <p className="text-[14px] font-semibold tracking-tight">{c.label}</p>
                <a
                  href={`${c.explorer}/address/${c.standing}`}
                  target="_blank"
                  rel="noreferrer"
                  className="num text-[11px] underline decoration-dotted underline-offset-4"
                  style={{color: "var(--muted)"}}
                >
                  {c.standing.slice(0, 8)}&hellip;{c.standing.slice(-4)}
                </a>
              </div>

              <dl className="mt-4 grid grid-cols-2 gap-x-4 gap-y-3">
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
                <p className="mt-4">
                  <Chip tone="hold">
                    {c.held} {c.held === 1 ? "charge" : "charges"} waiting on a payer right now
                  </Chip>
                </p>
              ) : null}
            </div>
          ))}

          {isLoading && !data
            ? [0, 1].map((i) => (
                <div key={i} className="panel px-5 py-4 text-[13px]" style={{color: "var(--muted)"}}>
                  Reading chain&hellip;
                </div>
              ))
            : null}
        </div>
      )}
    </section>
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
      <dd className="num mt-1 text-[17px] font-medium" style={{color}}>
        {value}
      </dd>
    </div>
  );
}
