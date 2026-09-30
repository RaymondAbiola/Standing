"use client";

import {useEffect, useMemo, useState} from "react";
import {useAccount, useChainId, useReadContract, useSignTypedData} from "wagmi";

import {
  MANDATE_TYPES,
  PERMIT2_ADDRESS,
  demoTokenAbi,
  permit2Abi,
  randomSalt,
  type MandateStruct,
} from "@/lib/demoAbis";
import {useDeployment} from "@/lib/deployments";
import {formatAmount, parseAmount} from "@/lib/format";
import {useStandingContract} from "@/lib/hooks";
import {useTx} from "@/lib/useTx";
import {Button, Chip, Field, Input, Section} from "./ui";

const MAX_UINT256 = (1n << 256n) - 1n;

/// Scoped on purpose. An unlimited Permit2 allowance would defeat the point of
/// routing through it, so the demo grants a bounded amount with an expiry.
const PERMIT_ALLOWANCE = "100000";
const PERMIT_DAYS = 365;

/// Everything a payer must do before a merchant can charge them, in order.
///
/// Four steps, and none of them are optional: fund the wallet, let Permit2
/// move the token, grant Standing a scoped allowance through Permit2, then
/// sign the terms. Without this a connected wallet sees empty tables and has
/// no way to make anything happen.
///
/// `createMandate` is permissionless, so the payer submits their own signature
/// here. In production the merchant's backend would submit it and pay the gas.
export function Authorise({onDone}: {onDone?: () => void}) {
  const {address} = useAccount();
  const chainId = useChainId();
  const {standing: STANDING_ADDRESS, demoToken: DEMO_TOKEN_ADDRESS, supported} = useDeployment();
  const standingContract = useStandingContract();

  const [merchant, setMerchant] = useState("");
  const [cap, setCap] = useState("30.00");
  const [intervalSecs, setIntervalSecs] = useState("2592000");
  const [postpaid, setPostpaid] = useState(false);
  const [signed, setSigned] = useState<{mandate: MandateStruct; signature: `0x${string}`} | null>(null);

  const {writeContract, busy: txBusy, error: writeError} = useTx();
  const {signTypedDataAsync, isPending: signing} = useSignTypedData();
  const busy = txBusy || signing;

  const balance = useReadContract({
    address: DEMO_TOKEN_ADDRESS,
    abi: demoTokenAbi,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: {enabled: Boolean(address) && supported},
  });

  const tokenAllowance = useReadContract({
    address: DEMO_TOKEN_ADDRESS,
    abi: demoTokenAbi,
    functionName: "allowance",
    args: address ? [address, PERMIT2_ADDRESS] : undefined,
    query: {enabled: Boolean(address) && supported},
  });

  const permitAllowance = useReadContract({
    address: PERMIT2_ADDRESS,
    abi: permit2Abi,
    functionName: "allowance",
    args: address ? [address, DEMO_TOKEN_ADDRESS, STANDING_ADDRESS] : undefined,
    query: {enabled: Boolean(address) && supported},
  });

  const funded = (balance.data ?? 0n) > 0n;
  const tokenApproved = (tokenAllowance.data ?? 0n) > 0n;
  const permitAmount = permitAllowance.data?.[0] ?? 0n;
  const permitExpiry = Number(permitAllowance.data?.[1] ?? 0n);
  const permitLive = permitAmount > 0n && permitExpiry > Math.floor(Date.now() / 1000);

  const merchantValid = /^0x[0-9a-fA-F]{40}$/.test(merchant.trim());

  const terms = useMemo((): MandateStruct | null => {
    if (!address || !merchantValid) return null;
    const now = BigInt(Math.floor(Date.now() / 1000));
    const secs = BigInt(Math.max(1, Number(intervalSecs) || 1));
    return {
      payer: address,
      merchant: merchant.trim() as `0x${string}`,
      token: DEMO_TOKEN_ADDRESS,
      maxAmount: parseAmount(cap || "0"),
      minInterval: secs,
      startsAt: now,
      expiresAt: now + 365n * 86_400n,
      maxCharges: 0,
      chargeKind: postpaid ? 1 : 0,
      salt: randomSalt(),
    };
  }, [address, merchant, merchantValid, cap, intervalSecs, postpaid]);

  // A signature commits to exact terms, so editing the form after signing has
  // to discard it. Otherwise the button would create a mandate on values the
  // form is no longer showing.
  useEffect(() => {
    setSigned(null);
  }, [merchant, cap, intervalSecs, postpaid]);

  if (!supported) return null;

  async function sign() {
    if (!terms) return;
    const signature = await signTypedDataAsync({
      domain: {
        name: "Standing",
        version: "1",
        chainId,
        verifyingContract: STANDING_ADDRESS,
      },
      types: MANDATE_TYPES,
      primaryType: "Mandate",
      message: terms,
    });
    setSigned({mandate: terms, signature});
  }

  return (
    <Section eyebrow="SET UP" title="Authorise a merchant to charge you">
      <div className="panel px-5 py-5">
        <p className="max-w-[64ch] text-[13px] leading-relaxed" style={{color: "var(--muted)"}}>
          Four steps, in order. The token allowance lets Permit2 move funds; the Permit2 allowance is what
          Standing draws against and it expires on its own, which is a kill switch separate from revoking the
          mandate.
        </p>

        <ol className="mt-5 space-y-3">
          <Step n={1} label="Get test dollars" done={funded} detail={`balance ${formatAmount(balance.data)} dUSDC`}>
            <Button
              disabled={busy}
              onClick={() =>
                address &&
                writeContract({
                  address: DEMO_TOKEN_ADDRESS,
                  abi: demoTokenAbi,
                  functionName: "mint",
                  args: [address, parseAmount("10000")],
                })
              }
            >
              Mint 10,000
            </Button>
          </Step>

          <Step n={2} label="Let Permit2 move the token" done={tokenApproved}>
            <Button
              disabled={busy || !funded}
              onClick={() =>
                writeContract({
                  address: DEMO_TOKEN_ADDRESS,
                  abi: demoTokenAbi,
                  functionName: "approve",
                  args: [PERMIT2_ADDRESS, MAX_UINT256],
                })
              }
            >
              Approve
            </Button>
          </Step>

          <Step
            n={3}
            label="Grant Standing a scoped allowance"
            done={permitLive}
            detail={permitLive ? `${formatAmount(permitAmount)} until ${new Date(permitExpiry * 1000).toLocaleDateString()}` : undefined}
          >
            <Button
              disabled={busy || !tokenApproved}
              onClick={() =>
                writeContract({
                  address: PERMIT2_ADDRESS,
                  abi: permit2Abi,
                  functionName: "approve",
                  args: [
                    DEMO_TOKEN_ADDRESS,
                    STANDING_ADDRESS,
                    parseAmount(PERMIT_ALLOWANCE),
                    Math.floor(Date.now() / 1000) + PERMIT_DAYS * 86_400,
                  ],
                })
              }
            >
              Grant
            </Button>
          </Step>

          <Step n={4} label="Sign the terms and create the mandate" done={Boolean(signed)}>
            <div className="flex flex-wrap items-center gap-2">
              <Button disabled={busy || !permitLive || !terms} onClick={() => void sign()}>
                {signed ? "Re-sign" : "Sign"}
              </Button>
              <Button
                variant="primary"
                disabled={busy || !signed}
                onClick={() => {
                  if (!signed) return;
                  writeContract({
                    ...standingContract,
                    functionName: "createMandate",
                    args: [signed.mandate, signed.signature],
                  });
                  onDone?.();
                }}
              >
                Create mandate
              </Button>
            </div>
          </Step>
        </ol>

        <div className="mt-6 grid gap-4 border-t pt-5 sm:grid-cols-2 lg:grid-cols-4" style={{borderColor: "var(--line)"}}>
          <Field label="Merchant address" hint={merchant && !merchantValid ? "Not a valid address" : "Who may charge you"}>
            <Input
              placeholder="0x…"
              value={merchant}
              onChange={(e) => setMerchant(e.target.value)}
              aria-label="Merchant address"
            />
          </Field>
          <Field label="Max per charge" hint="dUSDC">
            <Input inputMode="decimal" value={cap} onChange={(e) => setCap(e.target.value)} aria-label="Cap" />
          </Field>
          <Field label="Min seconds between charges" hint="A floor, not a schedule">
            <Input
              inputMode="numeric"
              value={intervalSecs}
              onChange={(e) => setIntervalSecs(e.target.value)}
              aria-label="Minimum interval in seconds"
            />
          </Field>
          <Field label="Charge kind" hint={postpaid ? "Settles at once, never reversible" : "Held for the merchant's window"}>
            <button
              type="button"
              onClick={() => setPostpaid((v) => !v)}
              className="min-h-11 w-full rounded-lg border px-3 text-left text-[13px]"
              style={{borderColor: "var(--line)", color: "var(--ink)"}}
            >
              {postpaid ? "Postpaid (usage)" : "Prepaid (subscription)"}
            </button>
          </Field>
        </div>

        {writeError ? (
          <p className="mt-4 text-[12px]" style={{color: "var(--color-warn)"}}>
            {writeError.message.split("\n")[0]}
          </p>
        ) : null}
      </div>
    </Section>
  );
}

function Step({
  n,
  label,
  done,
  detail,
  children,
}: {
  n: number;
  label: string;
  done: boolean;
  detail?: string;
  children: React.ReactNode;
}) {
  return (
    <li className="flex flex-wrap items-center gap-3">
      <span
        className="num grid h-6 w-6 shrink-0 place-items-center rounded-full text-[11px]"
        style={
          done
            ? {background: "var(--color-mint-soft)", color: "var(--color-mint)"}
            : {background: "var(--raised)", color: "var(--muted)"}
        }
      >
        {done ? "✓" : n}
      </span>
      <span className="text-[14px]">{label}</span>
      {detail ? (
        <span className="num text-[12px]" style={{color: "var(--muted)"}}>
          {detail}
        </span>
      ) : null}
      <span className="ml-auto flex items-center gap-2">
        {done ? <Chip tone="good">done</Chip> : null}
        {children}
      </span>
    </li>
  );
}
