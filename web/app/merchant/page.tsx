"use client";

import {useState} from "react";
import {useAccount, useReadContracts} from "wagmi";

import {NotConnected, WrongChain} from "@/components/States";
import {Button, Chip, Empty, Failed, Field, Input, Section, Stat} from "@/components/ui";
import {
  CHARGE_BLOCK,
  HOLD_STATUS,
  formatAmount,
  formatDuration,
  parseAmount,
  shortAddress,
} from "@/lib/format";
import {useHolds, useMandates, useMerchantStanding, useStandingContract} from "@/lib/hooks";
import {useTx} from "@/lib/useTx";
import {useDeployment} from "@/lib/deployments";

export default function MerchantPage() {
  const {address, isConnected} = useAccount();
  const {chainId, supported} = useDeployment();
  const standingContract = useStandingContract();
  const standing = useMerchantStanding(address);
  const mandates = useMandates("merchant", address);
  const holds = useHolds("merchant", address);

  const {writeContract, busy} = useTx();

  const [amounts, setAmounts] = useState<Record<string, string>>({});
  const [minClean, setMinClean] = useState("0");
  const [maxReversals, setMaxReversals] = useState("255");
  const [refuseSuspended, setRefuseSuspended] = useState(true);
  const [reversalCap, setReversalCap] = useState("0");
  const [trustThreshold, setTrustThreshold] = useState("0");

  const all = mandates.data ?? [];

  // Only mandates that can actually be billed belong under "charge a
  // customer". A revoked one cannot be charged, so listing it there is noise a
  // merchant has to read past on every visit.
  const rows = all.filter((m) => m.status === 1);
  const inactive = all.length - rows.length;
  const blockers = useReadContracts({
    contracts: rows.map((m) => ({
      ...standingContract,
      functionName: "chargeBlocker" as const,
      args: [m.id, parseAmount(amounts[m.id] || "0")] as const,
    })),
    query: {enabled: rows.length > 0},
  });

  // The contract refuses a cap with no threshold, because the cap only binds
  // below the threshold and would silently do nothing. Catch it here too: a
  // reverting transaction surfaces in the wallet as a funding error, since a
  // failed gas estimate falls back to an enormous limit, which is a confusing
  // way to learn you mistyped a policy.
  const capAmount = parseAmount(reversalCap || "0");
  const thresholdAmount = parseAmount(trustThreshold || "0");
  const capWithoutThreshold = capAmount > 0n && thresholdAmount === 0n;

  const held = (holds.data ?? []).filter((h) => h.status === 1);
  const settled = (holds.data ?? []).filter((h) => h.status === 2);
  const revenue = settled.reduce((acc, h) => acc + h.amount, 0n);

  if (!isConnected) return <NotConnected role="merchant" />;
  if (!supported) return <WrongChain chainId={chainId} />;

  return (
    <>
      <Section eyebrow="YOUR RECORD" title="What your history buys you">
        <div className="grid gap-3 sm:grid-cols-4">
          <Stat
            label="Hold window"
            value={formatDuration(standing.window)}
            tone={standing.flagged ? "warn" : "good"}
            hint={standing.flagged ? "Pinned at the maximum by your reversal rate" : "Shortens as you settle"}
          />
          <Stat
            label="Settlements"
            value={standing.record?.settlements ?? 0}
            hint="Next tier at 10, 100, 1000"
          />
          <Stat
            label="Reversals"
            value={standing.record?.reversals ?? 0}
            tone={standing.flagged ? "warn" : "plain"}
            hint={`${standing.record?.distinctPayersReversed ?? 0} distinct payers`}
          />
          <Stat label="Settled to you" value={formatAmount(revenue)} hint="Net of protocol fee" />
        </div>
      </Section>

      <Section
        eyebrow="MANDATES"
        title="Charge a customer"
        right={
          inactive > 0 ? (
            <span className="text-[12px]" style={{color: "var(--muted)"}}>
              {inactive} revoked, hidden
            </span>
          ) : undefined
        }
      >
        {mandates.isError ? (
          <Failed error={mandates.error} what="mandates naming you" />
        ) : rows.length === 0 ? (
          <Empty>
            No mandates name you yet. A payer signs terms offchain and anyone may submit them, so a mandate
            usually arrives from your own backend.
          </Empty>
        ) : (
          <div className="panel overflow-hidden">
            {rows.map((m, i) => {
              const code = Number(blockers.data?.[i]?.result ?? 0);
              const typed = amounts[m.id] ?? "";
              const ok = code === 0 && typed.length > 0;
              return (
                <div key={m.id} className="row-line flex flex-wrap items-center gap-3 px-4 py-3">
                  <div className="min-w-[190px]">
                    <p className="flex items-center gap-2 text-[13px]">
                      <span className="num">{shortAddress(m.payer)}</span>
                      <Chip tone={m.chargeKind === 1 ? "plain" : "good"}>
                        {m.chargeKind === 1 ? "postpaid" : "prepaid"}
                      </Chip>
                      {m.status === 2 ? <Chip tone="warn">revoked</Chip> : null}
                    </p>
                    <p className="num text-[11px]" style={{color: "var(--muted)"}}>
                      {shortAddress(m.id)} &middot; max {formatAmount(m.maxAmount)} /{" "}
                      {formatDuration(m.minInterval)} &middot; {m.chargeCount} charged
                    </p>
                  </div>
                  <div className="w-[130px]">
                    <Input
                      inputMode="decimal"
                      placeholder="0.00"
                      value={typed}
                      onChange={(e) => setAmounts((a) => ({...a, [m.id]: e.target.value}))}
                      aria-label="Amount to charge"
                    />
                  </div>
                  <div className="ml-auto flex items-center gap-2">
                    {typed && code !== 0 ? <Chip tone="plain">{CHARGE_BLOCK[code] ?? "Blocked"}</Chip> : null}
                    <Button
                      variant="primary"
                      disabled={!ok || busy}
                      onClick={() =>
                        writeContract({
                          ...standingContract,
                          functionName: "charge",
                          args: [m.id, parseAmount(typed)],
                        })
                      }
                    >
                      Charge
                    </Button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </Section>

      <Section
        eyebrow="ESCROW"
        title="Waiting to settle"
        right={
          <span className="text-[12px]" style={{color: "var(--muted)"}}>
            Anyone can settle a matured hold
          </span>
        }
      >
        {holds.isError ? (
          <Failed error={holds.error} what="your escrow" />
        ) : held.length === 0 ? (
          <Empty>Nothing in escrow. Charges appear here until their window closes.</Empty>
        ) : (
          <div className="panel overflow-hidden">
            {held.map((h) => {
              const left = h.unlockAt - BigInt(Math.floor(Date.now() / 1000));
              const matured = left <= 0n;
              return (
                <div key={h.holdId.toString()} className="row-line flex flex-wrap items-center gap-3 px-4 py-3">
                  <span className="num text-[12px]" style={{color: "var(--muted)"}}>
                    #{h.holdId.toString()}
                  </span>
                  <span className="num min-w-[86px] text-[15px] font-medium">{formatAmount(h.amount)}</span>
                  <span className="num text-[12px]" style={{color: "var(--muted)"}}>
                    from {shortAddress(h.payer)}
                  </span>
                  <Chip tone={matured ? "good" : "hold"}>
                    {matured ? "ready" : `${formatDuration(left)} left`}
                  </Chip>
                  <div className="ml-auto">
                    <Button
                      variant="primary"
                      disabled={!matured || busy}
                      onClick={() =>
                        writeContract({...standingContract, functionName: "finalize", args: [h.holdId]})
                      }
                    >
                      Settle
                    </Button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </Section>

      <Section eyebrow="ACCEPTANCE" title="Who you will serve">
        <div className="panel px-5 py-5">
          <p className="max-w-[62ch] text-[13px] leading-relaxed" style={{color: "var(--muted)"}}>
            Standing cannot suspend a payer who only ever reverses against you, because the rule that would
            catch it is the same rule protecting the customers of a broken merchant. This is what you do
            instead: read a payer&apos;s history and decline the next mandate.
          </p>
          <p className="mt-3 max-w-[62ch] text-[13px] leading-relaxed" style={{color: "var(--muted)"}}>
            The cap goes further. A payer&apos;s global ceiling records value but not counterparties, so it can
            be manufactured by settling to an address they control. Below, you state how much of a
            stranger&apos;s imported ceiling you will honour before they have settled anything with you. Terms
            are frozen into each charge, so tightening later cannot reach money already in escrow.
          </p>

          <div className="mt-5 grid gap-4 sm:grid-cols-3">
            <Field label="Min clean settlements" hint="0 accepts anyone">
              <Input
                inputMode="numeric"
                value={minClean}
                onChange={(e) => setMinClean(e.target.value)}
                aria-label="Minimum clean settlements"
              />
            </Field>
            <Field label="Max reversals in last 10" hint="255 means no limit">
              <Input
                inputMode="numeric"
                value={maxReversals}
                onChange={(e) => setMaxReversals(e.target.value)}
                aria-label="Maximum reversals in window"
              />
            </Field>
            <Field label="Reversal cap until trusted" hint="0 allows no reversals from a stranger">
              <Input
                inputMode="decimal"
                value={reversalCap}
                onChange={(e) => setReversalCap(e.target.value)}
                aria-label="Reversal cap until trusted"
              />
            </Field>
            <Field label="Settled with you to lift the cap" hint="0 disables the cap entirely">
              <Input
                inputMode="decimal"
                value={trustThreshold}
                onChange={(e) => setTrustThreshold(e.target.value)}
                aria-label="Trust threshold"
              />
            </Field>
            <Field label="Suspended payers">
              <button
                type="button"
                onClick={() => setRefuseSuspended((v) => !v)}
                className="min-h-11 w-full rounded-lg border px-3 text-left text-[13px]"
                style={{borderColor: "var(--line)", color: "var(--ink)"}}
              >
                {refuseSuspended ? "Refuse" : "Accept"}
              </button>
            </Field>
          </div>

          <div className="mt-5 flex flex-wrap items-center gap-3">
            <Button
              variant="primary"
              disabled={busy || capWithoutThreshold}
              onClick={() =>
                writeContract({
                  ...standingContract,
                  functionName: "setAcceptancePolicy",
                  args: [
                    Number(minClean || 0),
                    Number(maxReversals || 0),
                    refuseSuspended,
                    capAmount,
                    thresholdAmount,
                  ],
                })
              }
            >
              Save policy
            </Button>
            <Button
              disabled={busy}
              onClick={() =>
                writeContract({...standingContract, functionName: "clearAcceptancePolicy", args: []})
              }
            >
              Accept everyone
            </Button>
            {capWithoutThreshold ? (
              <Chip tone="warn">a cap needs a threshold, or it would never apply</Chip>
            ) : standing.policy?.set ? (
              <Chip tone="good">
                live: min {standing.policy.minCleanSettlements}, max {standing.policy.maxReversalsInWindow}
                {standing.policy.trustThreshold > 0n
                  ? `, cap ${formatAmount(standing.policy.reversalCap)} until ${formatAmount(standing.policy.trustThreshold)}`
                  : ""}
              </Chip>
            ) : (
              <Chip tone="plain">no policy set</Chip>
            )}
          </div>
        </div>
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
                    {shortAddress(h.payer)}
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
