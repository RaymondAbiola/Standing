"use client";

import {useAccount, useConnect, useDisconnect, useSwitchChain} from "wagmi";

import {arbitrumSepolia} from "@/lib/chains";
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

  const wrongChain = chainId !== arbitrumSepolia.id;

  if (wrongChain) {
    return (
      <Button variant="danger" onClick={() => switchChain({chainId: arbitrumSepolia.id})}>
        Switch to Arbitrum Sepolia
      </Button>
    );
  }

  return (
    <Button onClick={() => disconnect()}>
      <span className="num">{shortAddress(address)}</span>
    </Button>
  );
}
