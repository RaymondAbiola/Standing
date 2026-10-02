"use client";

import Link from "next/link";
import {useSwitchChain} from "wagmi";

import {arbitrumSepolia, robinhoodTestnet} from "@/lib/chains";
import {CHAIN_LABELS} from "@/lib/deployments";
import {NetworkDetails} from "./NetworkDetails";
import {Button, Section} from "./ui";

/// Standing is deployed on two testnets and the addresses differ per chain,
/// so a wallet on anything else has nothing to read.
export function WrongChain({chainId}: {chainId: number | undefined}) {
  const {switchChain, error, isPending} = useSwitchChain();
  const where = chainId ? CHAIN_LABELS[chainId] || `chain ${chainId}` : "an unknown network";

  return (
    <Section eyebrow="WRONG NETWORK" title={`Standing is not deployed on ${where}`}>
      <div className="panel px-5 py-6">
        <p className="max-w-[60ch] text-[16px] leading-relaxed" style={{color: "var(--muted)"}}>
          Pick one of the two testnets it is live on. The contract addresses differ between them, so the app
          reads whichever chain your wallet is on.
        </p>
        <div className="mt-5 flex flex-wrap gap-3">
          <Button
            variant="primary"
            disabled={isPending}
            onClick={() => switchChain({chainId: arbitrumSepolia.id})}
          >
            Arbitrum Sepolia
          </Button>
          <Button disabled={isPending} onClick={() => switchChain({chainId: robinhoodTestnet.id})}>
            Robinhood Testnet
          </Button>
        </div>

        {error ? (
          <p className="mt-4 max-w-[60ch] text-[13px]" style={{color: "var(--color-warn)"}}>
            Your wallet refused the switch: {error.message.split("\n")[0]}. Some wallets throw on this
            request even when the network would work, so add it by hand below.
          </p>
        ) : null}

        <NetworkDetails />
      </div>
    </Section>
  );
}

export function NotConnected({role}: {role: "payer" | "merchant"}) {
  return (
    <Section eyebrow="CONNECT" title={`Connect a wallet to act as a ${role}`}>
      <div className="panel px-5 py-6 text-[16px] leading-relaxed" style={{color: "var(--muted)"}}>
        <p>
          Everything on this page is read from the chain against your address. Use the connect button in the
          header, on Arbitrum Sepolia.
        </p>
        <p className="mt-3">
          <Link href="/" className="underline decoration-dotted underline-offset-4">
            Read how it works first
          </Link>
        </p>
      </div>
    </Section>
  );
}
