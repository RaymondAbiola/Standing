"use client";

import {useAccount, useWaitForTransactionReceipt, useWriteContract} from "wagmi";

import {Button, Chip, Empty, Section, Stat} from "@/components/ui";
import {HOLD_STATUS, REVERSAL_BLOCK, formatAmount, formatDuration, shortAddress} from "@/lib/format";
import {standingContract, useHolds, useMandates, useStanding} from "@/lib/hooks";
import {isConfigured} from "@/lib/wagmi";
import {NotConfigured, NotConnected} from "@/components/States";
import {useReadContracts} from "wagmi";

export default function PayerPage() {
  const {address, isConnected} = useAccount();
  const standing = useStanding(address);
  const mandates = useMandates("payer", address);
  const holds = useHolds("payer", address);

  const {writeContract, data: hash, isPending} = useWriteContract();
  const {isLoading: confirming} = useWaitForTransactionReceipt({hash});
  const busy = isPending || confirming;

  const open = (holds.data ?? []).filter((h) => h.status === 1);

  const blockers = useReadContracts({
    contracts: open.map((h) => ({
      ...standingContract,
      functionName: "reversalBlocker" as const,
      args: [h.holdId, address ?? "0x0000000000000000000000000000000000000000"] as const,
    })),
    query: {enabled: Boolean(address) && open.length > 0},
  });

  if (!isConfigured) return <NotConfigured />;
  if (!isConnected) return <NotConnected role="payer" />;

  return (
    <>
      <Section eyebrow="YOUR STANDING" title="What you have earned">
        <div className="grid gap-3 sm:grid-cols-4">
          <Stat
            label="Reversal right"
            value={standing.vested ? "Vested" : "Not vested"}
            tone={standing.vested ? "good" : "plain"}
            hint={
              standing.vested
                ? `${standing.record?.cleanSettlements ?? 0} clean settlements`
                : `${standing.cyclesUntilVested ?? 3} more clean cycles`
            }
          />
          <Stat
            label="Ceiling"
            value={formatAmount(standing.ceiling)}
            hint="Largest single charge you may reverse"
          />
          <Stat
            label="Settled cleanly"
            value={formatAmount(standing.record?.cumulativeCleanSettled)}
            hint="The ceiling is a third of this"
          />
          <Stat
            label="Status"
            value={standing.suspended ? "Suspended" : "Good standing"}
            tone={standing.suspended ? "warn" : "good"}
            hint={
              standing.suspended
                ? `${standing.cyclesUntilRestored ?? 0} clean cycles to restore`
                : `${standing.reversalsInWindow ?? 0} reversals in last 10`
            }
          />
        </div>
      </Section>

      <Section
        eyebrow="HOLDS"
        title="Charges waiting on you"
        right={
          <span className="text-[12px]" style={{color: "var(--muted)"}}>
            Reverse inside the window, or let it settle
          </span>
        }
      >
        {open.length === 0 ? (
          <Empty>No charge is currently held. A merchant charge will appear here with its countdown.</Empty>
        ) : (
          <div className="panel overflow-hidden">
            {open.map((h, i) => {
              const code = Number(blockers.data?.[i]?.result ?? 0);
              const canReverse = code === 0;
              return (
                <div key={h.holdId.toString()} className="row-line flex flex-wrap items-center gap-3 px-4 py-3">
                  <span className="num text-[12px]" style={{color: "var(--muted)"}}>
                    #{h.holdId.toString()}
                  </span>
                  <span className="num min-w-[86px] text-[15px] font-medium">{formatAmount(h.amount)}</span>
                  <span className="num text-[12px]" style={{color: "var(--muted)"}}>
                    to {shortAddress(h.merchant)}
                  </span>
                  <Countdown unlockAt={h.unlockAt} />
                  <div className="ml-auto flex items-center gap-2">
                    {!canReverse ? <Chip tone="plain">{REVERSAL_BLOCK[code] ?? "Blocked"}</Chip> : null}
                    <Button
                      variant="danger"
                      disabled={!canReverse || busy}
                      onClick={() =>
                        writeContract({...standingContract, functionName: "reverse", args: [h.holdId]})
                      }
                    >
                      Reverse
                    </Button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </Section>

      <Section
        eyebrow="MANDATES"
        title="Who can charge you"
        right={
          <Button
            variant="danger"
            disabled={busy}
            onClick={() => writeContract({...standingContract, functionName: "revokeAll", args: []})}
          >
            Revoke everything
          </Button>
        }
      >
        {(mandates.data ?? []).length === 0 ? (
          <Empty>No mandates yet. A merchant creates one from a set of terms you have signed.</Empty>
        ) : (
          <div className="panel overflow-hidden">
            {(mandates.data ?? []).map((m) => (
              <div key={m.id} className="row-line flex flex-wrap items-center gap-3 px-4 py-3">
                <span className="num text-[12px]" style={{color: "var(--muted)"}}>
                  {shortAddress(m.id)}
                </span>
                <span className="num text-[13px]">{shortAddress(m.merchant)}</span>
                <span className="num text-[13px]" style={{color: "var(--muted)"}}>
                  max {formatAmount(m.maxAmount)} / {formatDuration(m.minInterval)}
                </span>
                <div className="ml-auto">
                  <Button
                    variant="danger"
                    disabled={busy}
                    onClick={() =>
                      writeContract({...standingContract, functionName: "revokeMandate", args: [m.id]})
                    }
                  >
                    Revoke
                  </Button>
                </div>
              </div>
            ))}
          </div>
        )}
      </Section>

      <Section eyebrow="HISTORY" title="Settled and reversed">
        {(holds.data ?? []).filter((h) => h.status > 1).length === 0 ? (
          <Empty>Nothing has settled yet.</Empty>
        ) : (
          <div className="panel overflow-hidden">
            {(holds.data ?? [])
              .filter((h) => h.status > 1)
              .map((h) => (
                <div key={h.holdId.toString()} className="row-line flex items-center gap-3 px-4 py-3">
                  <span className="num text-[12px]" style={{color: "var(--muted)"}}>
                    #{h.holdId.toString()}
                  </span>
                  <span className="num text-[14px]">{formatAmount(h.amount)}</span>
                  <span className="num text-[12px]" style={{color: "var(--muted)"}}>
                    {shortAddress(h.merchant)}
                  </span>
                  <div className="ml-auto">
                    <Chip tone={h.status === 2 ? "good" : "warn"}>{HOLD_STATUS[h.status]}</Chip>
                  </div>
                </div>
              ))}
          </div>
        )}
      </Section>
    </>
  );
}

function Countdown({unlockAt}: {unlockAt: bigint}) {
  const left = unlockAt - BigInt(Math.floor(Date.now() / 1000));
  const open = left > 0n;
  return (
    <Chip tone={open ? "hold" : "plain"}>
      {open ? `${formatDuration(left)} left` : "window closed"}
    </Chip>
  );
}
