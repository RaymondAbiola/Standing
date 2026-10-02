"use client";

import {useAccount} from "wagmi";

import {arbitrumSepolia, robinhood, robinhoodTestnet} from "./chains";

const ZERO = "0x0000000000000000000000000000000000000000" as const;

export type Deployment = {
  standing: `0x${string}`;
  demoToken: `0x${string}`;
  explorer: string;
  label: string;
  /// Block the contracts were deployed in.
  ///
  /// Log queries start here rather than at `earliest`. Public RPCs reject the
  /// named tag outright ("expected fromBlock to be a hex string starting with
  /// 0x"), and even where they accept it, scanning three hundred million
  /// blocks for a contract deployed last week is a query no endpoint will
  /// serve.
  deployedAt: bigint;
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
    standing: "0xC91F89766f5B0A8a2918f7C672eAf41B90FBDCD7",
    demoToken: "0x9b14830dceb7f15f0Def9a25664C313a5C88Fdf5",
    explorer: "https://sepolia.arbiscan.io",
    label: "Arbitrum Sepolia",
    deployedAt: 314_840_104n,
  },
  [robinhoodTestnet.id]: {
    standing: "0x5719cd77c190420Ec38DC6dbea6Fc19D529Ad4E7",
    demoToken: "0xDC37130a3f2D07EAacf6d8d66352932c79474b8a",
    explorer: "https://explorer.testnet.chain.robinhood.com",
    label: "Robinhood Chain Testnet",
    deployedAt: 127_385_540n,
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
  deployedAt: bigint;
} {
  const {chainId} = useAccount();
  const deployment = chainId ? DEPLOYMENTS[chainId] : undefined;

  return {
    chainId,
    deployment,
    supported: Boolean(deployment),
    standing: deployment?.standing ?? ZERO,
    demoToken: deployment?.demoToken ?? ZERO,
    deployedAt: deployment?.deployedAt ?? 0n,
  };
}
