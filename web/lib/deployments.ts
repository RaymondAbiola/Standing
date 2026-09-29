"use client";

import {useAccount} from "wagmi";

import {arbitrumSepolia, robinhood, robinhoodTestnet} from "./chains";

const ZERO = "0x0000000000000000000000000000000000000000" as const;

export type Deployment = {
  standing: `0x${string}`;
  demoToken: `0x${string}`;
  explorer: string;
  label: string;
};

/*
 * Addresses are per chain and must never be collapsed into one value.
 *
 * CREATE derives an address from the deployer and its nonce, and the same
 * deployer was used on both chains with independent nonce sequences. So the
 * same address holds different contracts depending on the chain: Standing on
 * Arbitrum Sepolia shares an address with the faucet token on Robinhood
 * testnet. A single env var would happily read one as the other.
 */
export const DEPLOYMENTS: Record<number, Deployment> = {
  [arbitrumSepolia.id]: {
    standing: "0xfa820CB11e871eB05334d0f9567F7804c68CdB98",
    demoToken: "0xa46c8271C5344a21932ebea331DD8086189986DF",
    explorer: "https://sepolia.arbiscan.io",
    label: "Arbitrum Sepolia",
  },
  [robinhoodTestnet.id]: {
    standing: "0x3D30B84664E33CE51015a6B310544F45d63aA5D3",
    demoToken: "0xfa820CB11e871eB05334d0f9567F7804c68CdB98",
    explorer: "https://explorer.testnet.chain.robinhood.com",
    label: "Robinhood Chain Testnet",
  },
};

export const SUPPORTED_CHAIN_IDS = [arbitrumSepolia.id, robinhoodTestnet.id] as const;

export const CHAIN_LABELS: Record<number, string> = {
  [arbitrumSepolia.id]: "Arbitrum Sepolia",
  [robinhoodTestnet.id]: "Robinhood Testnet",
  [robinhood.id]: "Robinhood Mainnet",
};

/// The deployment for the wallet's current chain, or undefined when the wallet
/// is somewhere Standing is not deployed.
export function useDeployment(): {
  chainId: number | undefined;
  deployment: Deployment | undefined;
  supported: boolean;
  standing: `0x${string}`;
  demoToken: `0x${string}`;
} {
  const {chainId} = useAccount();
  const deployment = chainId ? DEPLOYMENTS[chainId] : undefined;

  return {
    chainId,
    deployment,
    supported: Boolean(deployment),
    standing: deployment?.standing ?? ZERO,
    demoToken: deployment?.demoToken ?? ZERO,
  };
}
