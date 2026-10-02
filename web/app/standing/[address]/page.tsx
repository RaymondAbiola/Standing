"use client";

import {useParams} from "next/navigation";

import {AddressLookup} from "@/components/AddressLookup";
import {Chip, Empty, Failed, Section, Stat} from "@/components/ui";
import {formatAmount, formatDuration, shortAddress} from "@/lib/format";
import {useAddressRecord, type AddressRecord} from "@/lib/publicReads";

export default function AddressPage() {
  const params = useParams<{address: string}>();
  const address = typeof params?.address === "string" ? params.address : "";
  const {data, isLoading, isError, error} = useAddressRecord(address);

  const valid = /^0x[0-9a-fA-F]{40}$/.test(address);

  return (
    <>
      <Section eyebrow="STANDING" title={shortAddress(address)}>
        <div className="panel px-5 py-5">
          <p className="num break-all text-[12px]" style={{color: "var(--muted)"}}>
            {address}
          </p>
          <div className="mt-4">
            <AddressLookup initial={address} />
          </div>
        </div>
      </Section>

      {!valid ? (
        <Section eyebrow="INVALID" title="Not an address">
          <Empty>Paste a 20 byte address to see its record.</Empty>
        </Section>
      ) : isError ? (
        <Section eyebrow="FAILED" title="Could not read the chains">
          <Failed error={error} what="this address's record" />
        </Section>
      ) : isLoading ? (
        <Section eyebrow="READING" title="Fetching both deployments">
          <Empty>Reading chain&hellip;</Empty>
        </Section>
      ) : (
        (data ?? []).map((r) => <ChainRecord key={r.chainId} record={r} address={address} />)
      )}
    </>
  );
}

function ChainRecord({record: r, address}: {record: AddressRecord; address: string}) {
  const untouched =
    r.payer.cleanSettlements === 0 &&
    r.payer.reversals === 0 &&
    r.merchant.settlements === 0 &&
    r.merchant.reversals === 0;

  return (
    <Section
      eyebrow={r.label}
      title={untouched ? "No history on this chain" : "Record"}
      right={
        <a
          href={`${r.explorer}/address/${address}`}
          target="_blank"
          rel="noreferrer"
          className="text-[12px] underline decoration-dotted underline-offset-4"
          style={{color: "var(--muted)"}}
        >
          explorer
        </a>
      }
    >
      {untouched ? (
        <Empty>
          This address has never paid or been paid through Standing here. A fresh address holds no reversal
          right, which is what makes churning wallets pointless.
        </Empty>
      ) : (
        <div className="space-y-4">
          <div>
            <p className="eyebrow mb-3">As a payer</p>
            <div className="grid gap-3 sm:grid-cols-4">
              <Stat
                label="Reversal right"
                value={r.payer.vested ? "Vested" : "Not vested"}
                tone={r.payer.vested ? "good" : "plain"}
                hint={
                  r.payer.vested
                    ? `${r.payer.cleanSettlements} clean settlements`
                    : `${r.payer.cyclesUntilVested} more clean cycles`
                }
              />
              <Stat label="Ceiling" value={formatAmount(r.payer.ceiling)} hint="Largest single reversal" />
              <Stat
                label="Settled cleanly"
                value={formatAmount(r.payer.cumulativeCleanSettled)}
                hint="The ceiling is a third of this"
              />
              <Stat
                label="Standing"
                value={r.payer.suspended ? "Suspended" : "Good"}
                tone={r.payer.suspended ? "warn" : "good"}
                hint={
                  r.payer.suspended
                    ? `${r.payer.cyclesUntilRestored} clean cycles to restore`
                    : `${r.payer.reversalsInWindow} of last ${r.payer.sampleSize || 0} reversed`
                }
              />
            </div>
            {r.payer.reversals > 0 ? (
              <p className="mt-3 flex flex-wrap gap-2">
                <Chip tone="warn">
                  {r.payer.reversals} lifetime {r.payer.reversals === 1 ? "reversal" : "reversals"}
                </Chip>
                <Chip tone={r.payer.distinctMerchantsReversed >= 3 ? "warn" : "plain"}>
                  across {r.payer.distinctMerchantsReversed}{" "}
                  {r.payer.distinctMerchantsReversed === 1 ? "merchant" : "merchants"}
                </Chip>
                {r.payer.distinctMerchantsReversed < 3 ? (
                  <Chip tone="plain">too concentrated to count as a pattern</Chip>
                ) : null}
              </p>
            ) : null}
          </div>

          <div>
            <p className="eyebrow mb-3">As a merchant</p>
            <div className="grid gap-3 sm:grid-cols-3 lg:grid-cols-5">
              <Stat
                label="Hold window"
                value={formatDuration(r.merchant.window)}
                tone={r.merchant.flagged ? "warn" : "good"}
                hint={r.merchant.flagged ? "Pinned by its reversal rate" : "Shortens with settlements"}
              />
              <Stat label="Settlements" value={r.merchant.settlements} hint="Tiers at 10, 100, 1000" />
              <Stat
                label="Reversed against"
                value={r.merchant.reversals}
                tone={r.merchant.flagged ? "warn" : "plain"}
                hint={`${r.merchant.distinctPayersReversed} distinct payers`}
              />
              <Stat
                label="Accepts"
                value={r.merchant.policySet ? "With conditions" : "Anyone"}
                hint={
                  r.merchant.policySet
                    ? `min ${r.merchant.minCleanSettlements} clean, max ${r.merchant.maxReversalsInWindow} reversals`
                    : "No acceptance policy set"
                }
              />
              <Stat
                label="Honours imported ceilings"
                value={
                  r.merchant.trustThreshold > 0n
                    ? `up to ${formatAmount(r.merchant.reversalCap)}`
                    : "In full"
                }
                tone={r.merchant.trustThreshold > 0n ? "warn" : "plain"}
                hint={
                  r.merchant.trustThreshold > 0n
                    ? `until a payer has settled ${formatAmount(r.merchant.trustThreshold)} here`
                    : "No cap on a stranger's global ceiling"
                }
              />
            </div>
          </div>
        </div>
      )}
    </Section>
  );
}
