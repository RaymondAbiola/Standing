"use client";

import {useAccount, useConnect, useDisconnect, useSwitchChain} from "wagmi";

import {arbitrumSepolia} from "@/lib/chains";
import {CHAIN_LABELS, DEPLOYMENTS} from "@/lib/deployments";
import {shortAddress} from "@/lib/format";
import {Button} from "./ui";

export function ConnectButton() {
  const {address, chainId, isConnected} = useAccount();
  const {connect, connectors, isPending} = useConnect();
  const {disconnect} = useDisconnect();
  const {switchChain} = useSwitchChain();

  if (!isConnected) {
    const injected = connectors[0];
    return (
      <Button variant="primary" onClick={() => injected && connect({connector: injected})} disabled={isPending}>
        {isPending ? "Connecting" : "Connect wallet"}
      </Button>
    );
  }

  // Either testnet is fine. Forcing one would hide the Robinhood Chain
  // deployment, which is the one that matters for the programme.
  const deployed = chainId ? Boolean(DEPLOYMENTS[chainId]) : false;

  if (!deployed) {
    return (
      <Button variant="danger" onClick={() => switchChain({chainId: arbitrumSepolia.id})}>
        Switch network
      </Button>
    );
  }

  return (
    <Button onClick={() => disconnect()}>
      <span className="num">{shortAddress(address)}</span>
      <span className="text-[11px]" style={{color: "var(--muted)"}}>
        {chainId ? CHAIN_LABELS[chainId] : ""}
      </span>
    </Button>
  );
}
