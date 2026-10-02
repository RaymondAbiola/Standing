"use client";

import {useState} from "react";

import {arbitrumSepolia, robinhoodTestnet} from "@/lib/chains";

const NETWORKS = [
  {
    name: "Arbitrum Sepolia",
    chainId: arbitrumSepolia.id,
    rpc: "https://sepolia-rollup.arbitrum.io/rpc",
    explorer: "https://sepolia.arbiscan.io",
  },
  {
    name: "Robinhood Chain Testnet",
    chainId: robinhoodTestnet.id,
    rpc: "https://rpc.testnet.chain.robinhood.com",
    explorer: "https://explorer.testnet.chain.robinhood.com",
  },
];

/// The parameters for adding either network by hand.
///
/// Programmatic switching goes through the wallet's own
/// `wallet_addEthereumChain` handler, which is not reliable: MetaMask has been
/// seen throwing inside its own bundle on that request. Robinhood testnet is
/// not preinstalled in any wallet, so without a manual fallback a visitor who
/// hits that bug simply cannot reach that deployment.
export function NetworkDetails() {
  const [open, setOpen] = useState(false);

  return (
    <div className="mt-5">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="text-[12px] underline decoration-dotted underline-offset-4"
        style={{color: "var(--muted)"}}
        aria-expanded={open}
      >
        {open ? "Hide network details" : "Add a network by hand instead"}
      </button>

      {open ? (
        <div className="mt-4 grid gap-3 sm:grid-cols-2">
          {NETWORKS.map((n) => (
            <div key={n.chainId} className="panel px-4 py-3">
              <p className="text-[13px] font-medium">{n.name}</p>
              <dl className="mt-2 space-y-1 text-[11px]">
                <Row label="RPC" value={n.rpc} />
                <Row label="Chain ID" value={String(n.chainId)} />
                <Row label="Symbol" value="ETH" />
                <Row label="Explorer" value={n.explorer} />
              </dl>
            </div>
          ))}
        </div>
      ) : null}
    </div>
  );
}

function Row({label, value}: {label: string; value: string}) {
  return (
    <div className="flex gap-2">
      <dt className="w-[62px] shrink-0" style={{color: "var(--muted)"}}>
        {label}
      </dt>
      <dd className="num break-all">{value}</dd>
    </div>
  );
}
